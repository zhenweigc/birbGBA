import Bits
Sound1Reg : {
	sound1_cntl : U16,
	sound1_cnth : U16,
	sound1_cntx : U16,
}

Sound1State : {
	enabled : Bool,
	length_counter : U8,
	current_volume : U8,
	envelope_timer : U8,
	envelope_running : Bool,
	frequency_timer : U32,
	duty_position : U8,
	sweep_shadow : U16,
	sweep_timer : U8,
	sweep_enabled : Bool,
	sweep_negate_used : Bool,
}

Sound2Reg : {
	sound2_cntl : U16,
	sound2_cnth : U16,
}

Sound3Reg : {
	sound3_cntl : U16,
	sound3_cnth : U16,
	sound3_cntx : U16,
}

Sound4Reg : {
	sound4_cntl : U16,
	sound4_cnth : U16,
}

SoundRegs :: {
	sound1 : Sound1Reg,
	sound1state : Sound1State,
	sound2 : Sound2Reg,
	sound3 : Sound3Reg,
	sound4 : Sound4Reg,
	sound_cntl : U16,
	sound_cnth : U16,
	sound_cntx : U16,
	sound_bias : U16,
}.{
	init : () -> SoundRegs
	init = || {
		{
			sound1: sound1_init(),
			sound1state: sound1_state_init(),
			sound2: sound2_init(),
			sound3: sound3_init(),
			sound4: sound4_init(),
			sound_cntl: 0,
			sound_cnth: 0,
			sound_cntx: 0,
			sound_bias: 0x200,
		}
	}

	read8 : SoundRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x60 => Ok(rgs.sound1.sound1_cntl.bitwise_and(0b111_1111).to_u8_wrap())
			0x61 => Ok(rgs.sound1.sound1_cntl.bitwise_and(0b111_1111).shr_wrap(8).to_u8_wrap())
			0x62 => Ok(rgs.sound1.sound1_cnth.bitwise_and(0b1111_1111_1100_0000).to_u8_wrap())
			0x63 => Ok(rgs.sound1.sound1_cnth.bitwise_and(0b1111_1111_1100_0000).shr_wrap(8).to_u8_wrap())
			0x64 | 0x65 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					raw_16 = rgs.sound1.sound1_cntx.bitwise_and(0b100_0000_0000_0000)
					if addr.mod_by(2) == 0 {
						Ok(raw_16.to_u8_wrap())
					} else {
						Ok(raw_16.shr_wrap(8).to_u8_wrap())
					}
				} else {
					Ok(0)
				}
			}
			0x66 | 0x67 => Ok(0)
			0x80 | 0x81 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					raw_16 = rgs.sound_cntl.bitwise_and(0b1111_1111_0111_0111)
					if addr.mod_by(2) == 0 {
						Ok(raw_16.to_u8_wrap())
					} else {
						Ok(raw_16.shr_wrap(8).to_u8_wrap())
					}
				} else {
					Ok(0)
				}
			}
			0x82 => Ok(rgs.sound_cnth.bitwise_and(0b111_0111_0000_1111).to_u8_wrap())
			0x83 => Ok(rgs.sound_cnth.bitwise_and(0b111_0111_0000_1111).shr_wrap(8).to_u8_wrap())
			0x84 => Ok(
				rgs.sound_cntx.bitwise_and(0b1000_1110).to_u8_wrap()
					+ if rgs.sound1state.enabled {
						1
					} else {
						0
					},
			)
			0x85 => Ok(rgs.sound_cntx.bitwise_and(0b1000_1111).shr_wrap(8).to_u8_wrap())
			0x86 | 0x87 => Ok(0)
			0x88 => Ok(rgs.sound_bias.bitwise_and(0b1100_0011_1111_1110).to_u8_wrap())
			0x89 => Ok(rgs.sound_bias.bitwise_and(0b1100_0011_1111_1110).shr_wrap(8).to_u8_wrap())
			0x8A | 0x8B => Ok(0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : SoundRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x60 => Ok(rgs.sound1.sound1_cntl.bitwise_and(0b111_1111))
			0x62 => Ok(rgs.sound1.sound1_cnth.bitwise_and(0b1111_1111_1100_0000))
			0x64 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound1.sound1_cntx.bitwise_and(0b100_0000_0000_0000))
				} else {
					Ok(0)
				}
			}
			0x66 => Ok(0)
			0x80 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound_cntl.bitwise_and(0b1111_1111_0111_0111))
				} else {
					Ok(0)
				}
			}
			0x82 => Ok(rgs.sound_cnth.bitwise_and(0b111_0111_0000_1111))
			0x84 => Ok(
				rgs.sound_cntx.bitwise_and(0b1000_1110)
					+ if rgs.sound1state.enabled {
						1
					} else {
						0
					},
			)
			0x86 => Ok(0)
			0x88 => Ok(rgs.sound_bias.bitwise_and(0b1100_0011_1111_1110))
			0x8A => Ok(0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : SoundRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x60 | 0x64 | 0x80 | 0x84 | 0x88 => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : SoundRegs, U32, U8 -> Try(SoundRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x60 | 0x61 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				old_val = rgs.sound1.sound1_cntl
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x60, adjusted_val)
			} else {
				Ok(rgs)
			}
			0x62 | 0x63 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				old_val = rgs.sound1.sound1_cnth
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				if !isHi {
					Ok({
						..rgs,
						sound1: { ..rgs.sound1, sound1_cnth: adjusted_val },
						sound1state: {
							..rgs.sound1state,
							length_counter: 64 - Bits.get_seg_of_u8_certain(val, 0, 6).to_u8_wrap(),
						},
					})
				} else {
					Ok({
						..rgs,
						sound1: { ..rgs.sound1, sound1_cnth: adjusted_val },
						sound1state: {
							..rgs.sound1state,
							enabled: if Bits.get_seg_of_u8_certain(val, 3, 5) == 0 {
								False
							} else {
								rgs.sound1state.enabled
							},
						},
					})
				}
			} else {
				Ok(rgs)
			}
			0x64 | 0x65 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound1.sound1_cntx
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x64, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x66 | 0x67 => Ok(rgs)
			0x80 | 0x81 => {
				old_val = rgs.sound_cntl
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x80, adjusted_val)
			}
			0x82 | 0x83 => {
				old_val = rgs.sound_cnth
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x82, adjusted_val)
			}
			0x84 => {
				old_val = rgs.sound_cntx
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x84, adjusted_val)
			}
			0x85 => Ok(rgs)
			0x86 | 0x87 => Ok(rgs)
			0x88 | 0x89 => {
				old_val = rgs.sound_bias
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x88, adjusted_val)
			}
			0x8A | 0x8B => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : SoundRegs, U32, U16 -> Try(SoundRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x60 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, sound1: { ..rgs.sound1, sound1_cntl: val.bitwise_and(0b111_1111) } })
			} else {
				Ok(rgs)
			}
			0x62 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound1: {
						..rgs.sound1,
						sound1_cnth: val,
					},
					sound1state: {
						..rgs.sound1state,
						length_counter: 64 - Bits.get_seg_of_u16_certain(val, 0, 6).to_u8_wrap(),
						enabled: if Bits.get_seg_of_u16_certain(val, 11, 5) == 0 {
							False
						} else {
							rgs.sound1state.enabled
						},
					},
				})
			} else {
				Ok(rgs)
			}
			0x64 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					if Bits.get_ith_bit_u16_certain(val, 15) {
						new_sound1 = { ..rgs.sound1, sound1_cntx: val.bitwise_and(0b100_0111_1111_1111) }
						Ok({
							..rgs,
							sound1: new_sound1,
							sound1state: sound1_trigger(new_sound1, rgs.sound1state),
						})
					} else {
						Ok({ ..rgs, sound1: { ..rgs.sound1, sound1_cntx: val.bitwise_and(0b100_0111_1111_1111) } })
					}
				} else {
					Ok(rgs)
				}
			}
			0x66 => Ok(rgs)
			0x80 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok({ ..rgs, sound_cntl: val.bitwise_and(0b1111_1111_0111_0111) })
				} else {
					Ok(rgs)
				}
			}
			0x82 => {
				# Somehow this reg write in needs to update FIFOs
				# gonna be painful
				Ok({ ..rgs, sound_cnth: val.bitwise_and(0b111_0111_0000_1111) })
			}
			0x84 => {
				if Bits.get_ith_bit_u16_certain(val, 7) {
					Ok({ ..rgs, sound_cntx: rgs.sound_cntx.bitwise_and(0b1111).bitwise_or(0b1000_0000) })
				} else {
					# Oh boy sound is off and here comes masterbroom
					Ok({
						..rgs,
						sound_cntl: 0,
						sound_cnth: rgs.sound_cnth.bitwise_and(0xFF00),
						sound_cntx: 0,
						sound1: sound1_init(),
						sound1state: sound1_state_init(),
					})
				}
			}
			0x86 => Ok(rgs)
			0x88 => Ok({ ..rgs, sound_bias: val.bitwise_and(0b1100_0011_1111_1110) })
			0x8A => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : SoundRegs, U32, U32 -> Try(SoundRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x60 => write16(write16(rgs, 0x60, lo)?, 0x62, hi)
			0x64 => write16(write16(rgs, 0x64, lo)?, 0x66, 0)
			0x80 => write16(write16(rgs, 0x80, lo)?, 0x82, hi)
			0x84 => write16(write16(rgs, 0x84, lo)?, 0x86, 0)
			0x88 => write16(write16(rgs, 0x88, lo)?, 0x8A, 0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}
}

sound1_init : () -> Sound1Reg
sound1_init = || {
	{
		sound1_cntl: 0,
		sound1_cnth: 0,
		sound1_cntx: 0,
	}
}

sound1_state_init : () -> Sound1State
sound1_state_init = || {
	{
		enabled: False,
		length_counter: 0,
		current_volume: 0,
		envelope_timer: 0,
		envelope_running: False,
		frequency_timer: 0,
		duty_position: 0,
		sweep_shadow: 0,
		sweep_timer: 0,
		sweep_enabled: False,
		sweep_negate_used: False,
	}
}

sound1_trigger : Sound1Reg, Sound1State -> Sound1State
sound1_trigger = |reg, state| {
	cur_vol = Bits.get_seg_of_u16_certain(reg.sound1_cnth, 12, 4).to_u8_wrap()
	envelope_period = Bits.get_seg_of_u16_certain(reg.sound1_cnth, 8, 3).to_u8_wrap()
	envelope_increase = Bits.get_ith_bit_u16_certain(reg.sound1_cnth, 11)
	envelops = Bits.get_seg_of_u16_certain(reg.sound1_cnth, 11, 5)
	sweep_period = Bits.get_seg_of_u16_certain(reg.sound1_cntl, 4, 3).to_u8_wrap()
	sweep_shift = Bits.get_seg_of_u16_certain(reg.sound1_cntl, 0, 3).to_u8_wrap()
	sweep_decrease = Bits.get_ith_bit_u16_certain(reg.sound1_cntl, 3)
	new_sweep_shadow = Bits.get_seg_of_u16_certain(reg.sound1_cntx, 0, 11)
	{
		..state,
		enabled: envelops != 0 and sweep_shift == 0 or
			(envelops != 0 and sweep_shift != 0 and (sweep_decrease or
				(new_sweep_shadow.shr_wrap(sweep_shift) + new_sweep_shadow) <= 2047)),
		length_counter: if state.length_counter == 0 {
			64
		} else {
			state.length_counter
		},
		current_volume: cur_vol,
		envelope_running: envelope_period != 0
			and ((cur_vol < 15 and envelope_increase)
				or (cur_vol > 0 and !envelope_increase)),
		envelope_timer: envelope_period,
		sweep_shadow: new_sweep_shadow,
		sweep_timer: if sweep_period == 0 {
			8
		} else {
			sweep_period
		}, # Stolen from mGBA
		sweep_enabled: sweep_period != 0 or sweep_shift != 0,
		sweep_negate_used: (envelops != 0 and sweep_shift != 0 and sweep_decrease),
	}
}

sound2_init : () -> Sound2Reg
sound2_init = || {
	{
		sound2_cntl: 0,
		sound2_cnth: 0,
	}
}

sound3_init : () -> Sound3Reg
sound3_init = || {
	{
		sound3_cntl: 0,
		sound3_cnth: 0,
		sound3_cntx: 0,
	}
}

sound4_init : () -> Sound4Reg
sound4_init = || {
	{
		sound4_cntl: 0,
		sound4_cnth: 0,
	}
}
