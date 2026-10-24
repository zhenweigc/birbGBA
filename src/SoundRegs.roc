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

SoundFIFO :: {
	buffer : List(U32),
	read_pos : U8,
	# valid data #, Do not confuse with len of buffer
	count : U8,
	pipe_word : U32,
	pipe_remaining : U8,
	sample : U8,
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
	fifo_a : SoundFIFO,
	fifo_b : SoundFIFO,
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
			fifo_a: sound_fifo_init(),
			fifo_b: sound_fifo_init(),
		}
	}

	# The two bool is to tell if either fifo needs new vals to be inserted
	on_timer_overflow : SoundRegs, U8 -> Try((SoundRegs, { fifo_a : Bool, fifo_b : Bool }), [OutOfBounds])
	on_timer_overflow = |rgs, overflow_mask| {
		if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
			timer_a = Bits.get_seg_of_u16_certain(rgs.sound_cnth, 10, 1).to_u8_wrap()
			timer_b = Bits.get_seg_of_u16_certain(rgs.sound_cnth, 14, 1).to_u8_wrap()
			tick_a = Bits.get_ith_bit_u16_certain(overflow_mask.to_u16(), timer_a)
			tick_b = Bits.get_ith_bit_u16_certain(overflow_mask.to_u16(), timer_b)
			(new_fifo_a, bool_fifo_a) = if tick_a {
				(sound_fifo_sample(rgs.fifo_a)?, rgs.fifo_a.count < 4)
			} else {
				(rgs.fifo_a, False)
			}
			(new_fifo_b, bool_fifo_b) = if tick_b {
				(sound_fifo_sample(rgs.fifo_b)?, rgs.fifo_b.count < 4)
			} else {
				(rgs.fifo_b, False)
			}
			Ok((
				{
					..rgs,
					fifo_a: new_fifo_a,
					fifo_b: new_fifo_b,
				},
				{ fifo_a: bool_fifo_a, fifo_b: bool_fifo_b },
			))
		} else {
			Ok((rgs, { fifo_a: False, fifo_b: False }))
		}
	}

	read8 : SoundRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x60 => Ok(rgs.sound1.sound1_cntl.bitwise_and(0b111_1111).to_u8_wrap())
			0x61 => Ok(rgs.sound1.sound1_cntl.shr_wrap(8).to_u8_wrap())
			0x62 => Ok(rgs.sound1.sound1_cnth.bitwise_and(0b1111_1111_1100_0000).to_u8_wrap())
			0x63 => Ok(rgs.sound1.sound1_cnth.shr_wrap(8).to_u8_wrap())
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
			0x68 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound2.sound2_cntl.to_u8_wrap().bitwise_and(0b1100_0000))
				} else {
					Ok(0)
				}
			}
			0x69 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound2.sound2_cntl.shr_wrap(8).to_u8_wrap())
				} else {
					Ok(0)
				}
			}
			0x6A | 0x6B => Ok(0)
			0x6C => Ok(0)
			0x6D => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound2.sound2_cnth.shr_wrap(8).to_u8_wrap().bitwise_and(0b100_0000))
				} else {
					Ok(0)
				}
			}
			0x6E | 0x6F => Ok(0)
			0x70 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound3.sound3_cntl.bitwise_and(0b1110_0000).to_u8_wrap())
				} else {
					Ok(0)
				}
			}
			0x71 => Ok(0)
			0x72 => Ok(0)
			0x73 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound3.sound3_cnth.shr_wrap(8).to_u8_wrap().bitwise_and(0b1110_0000))
				} else {
					Ok(0)
				}
			}
			0x74 => Ok(0)
			0x75 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound3.sound3_cntx.shr_wrap(8).to_u8_wrap().bitwise_and(0b100_0000))
				} else {
					Ok(0)
				}
			}
			0x76 | 0x77 => Ok(0)
			0x78 => Ok(0)
			0x79 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound4.sound4_cntl.shr_wrap(8).to_u8_wrap())
				} else {
					Ok(0)
				}
			}
			0x7A | 0x7B => Ok(0)
			0x7C => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound4.sound4_cnth.to_u8_wrap())
				} else {
					Ok(0)
				}
			}
			0x7D => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound4.sound4_cnth.shr_wrap(8).to_u8_wrap().bitwise_and(0b100_0000))
				} else {
					Ok(0)
				}
			}
			0x7E | 0x7F => Ok(0)
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
			0x83 => Ok(rgs.sound_cnth.shr_wrap(8).to_u8_wrap().bitwise_and(0b111_0111))
			0x84 => Ok(
				rgs.sound_cntx.bitwise_and(0b1000_1110).to_u8_wrap()
					+ (
						if rgs.sound1state.enabled {
							1
						} else {
							0
						}
					),
			)
			0x85 => Ok(rgs.sound_cntx.shr_wrap(8).to_u8_wrap().bitwise_and(0b1000_1111))
			0x86 | 0x87 => Ok(0)
			0x88 => Ok(rgs.sound_bias.bitwise_and(0b1100_0011_1111_1110).to_u8_wrap())
			0x89 => Ok(rgs.sound_bias.shr_wrap(8).to_u8_wrap().bitwise_and(0b1100_0011))
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
			0x68 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound2.sound2_cntl.bitwise_and(0b1111_1111_1100_0000))
				} else {
					Ok(0)
				}
			}
			0x6A => Ok(0)
			0x6C => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound2.sound2_cnth.bitwise_and(0b10000_00000_00000))
				} else {
					Ok(0)
				}
			}
			0x6E => Ok(0)
			0x70 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound3.sound3_cntl.bitwise_and(0b1110_0000))
				} else {
					Ok(0)
				}
			}
			0x72 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound3.sound3_cnth.bitwise_and(0b1110_0000_0000_0000))
				} else {
					Ok(0)
				}
			}
			0x74 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound3.sound3_cntx.bitwise_and(0b100_0000_0000_0000))
				} else {
					Ok(0)
				}
			}
			0x76 => Ok(0)
			0x78 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound4.sound4_cntl.bitwise_and(0b1111_1111_0000_0000))
				} else {
					Ok(0)
				}
			}
			0x7A => Ok(0)
			0x7C => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound4.sound4_cnth.bitwise_and(0b100_0000_1111_1111))
				} else {
					Ok(0)
				}
			}
			0x7E => Ok(0)
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
					+ (
						if rgs.sound1state.enabled {
							1
						} else {
							0
						}
					),
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
			0x60 | 0x64 | 0x68 | 0x6C | 0x70 | 0x74 | 0x78 | 0x7C | 0x80 | 0x84 | 0x88 => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : SoundRegs, U32, U8 -> Try(SoundRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
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
			0x68 | 0x69 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound2.sound2_cntl
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x68, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x6A | 0x6B => Ok(rgs)
			0x6C | 0x6D => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound2.sound2_cnth
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x6C, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x6E | 0x6F => Ok(rgs)
			0x70 | 0x71 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound3.sound3_cntl
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x70, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x72 | 0x73 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound3.sound3_cnth
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x72, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x74 | 0x75 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound3.sound3_cntx
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x74, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x76 | 0x77 => Ok(rgs)
			0x78 | 0x79 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound4.sound4_cntl
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x78, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x7A | 0x7B => Ok(rgs)
			0x7C | 0x7D => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					old_val = rgs.sound4.sound4_cnth
					adjusted_val = Bits.replace_byte(old_val, isHi, val)
					write16(rgs, 0x7C, adjusted_val)
				} else {
					Ok(rgs)
				}
			}
			0x7E | 0x7F => Ok(rgs)
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
			0xA0 | 0xA1 | 0xA2 | 0xA3 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, fifo_a: sound_fifo_push_byte(rgs.fifo_a, (addr - 0xA0).to_u8_wrap(), val)? })
			} else Ok(rgs)
			0xA4 | 0xA5 | 0xA6 | 0xA7 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, fifo_b: sound_fifo_push_byte(rgs.fifo_b, (addr - 0xA4).to_u8_wrap(), val)? })
			} else Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : SoundRegs, U32, U16 -> Try(SoundRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
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
			0x68 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound2: {
						..rgs.sound2,
						sound2_cntl: val,
					},
				})
			} else {
				Ok(rgs)
			}
			0x6A => Ok(rgs)
			0x6C => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound2: {
						..rgs.sound2,
						sound2_cnth: val.bitwise_and(0b100_0111_1111_1111),
					},
				})
			} else {
				Ok(rgs)
			}
			0x6E => Ok(rgs)
			0x70 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound3: {
						..rgs.sound3,
						sound3_cntl: val.bitwise_and(0b1110_0000),
					},
				})
			} else {
				Ok(rgs)
			}
			0x72 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound3: {
						..rgs.sound3,
						sound3_cnth: val.bitwise_and(0b1110_0000_1111_1111),
					},
				})
			} else {
				Ok(rgs)
			}
			0x74 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound3: {
						..rgs.sound3,
						sound3_cntx: val.bitwise_and(0b100_0111_1111_1111),
					},
				})
			} else {
				Ok(rgs)
			}
			0x76 => Ok(rgs)
			0x78 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound4: {
						..rgs.sound4,
						sound4_cntl: val.bitwise_and(0b1111_1111_0011_1111),
					},
				})
			} else {
				Ok(rgs)
			}
			0x7A => Ok(rgs)
			0x7C => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({
					..rgs,
					sound4: {
						..rgs.sound4,
						sound4_cnth: val.bitwise_and(0b100_0000_1111_1111),
					},
				})
			} else {
				Ok(rgs)
			}
			0x7E => Ok(rgs)
			0x80 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok({ ..rgs, sound_cntl: val.bitwise_and(0b1111_1111_0111_0111) })
				} else {
					Ok(rgs)
				}
			}
			0x82 => {
				new_fifo_a = if (Bits.get_ith_bit_u16_certain(val, 11)) sound_fifo_reset(rgs.fifo_a) else rgs.fifo_a
				new_fifo_b = if (Bits.get_ith_bit_u16_certain(val, 15)) sound_fifo_reset(rgs.fifo_b) else rgs.fifo_b
				Ok({ ..rgs, sound_cnth: val.bitwise_and(0b111_0111_0000_1111), fifo_a: new_fifo_a, fifo_b: new_fifo_b })
			}
			0x84 => {
				if Bits.get_ith_bit_u16_certain(val, 7) {
					Ok({ ..rgs, sound_cntx: rgs.sound_cntx.bitwise_and(0b1111).bitwise_or(0b1000_0000) })
				} else {
					(new_fifo_a, new_fifo_b) = if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
						(sound_fifo_reset(rgs.fifo_a), sound_fifo_reset(rgs.fifo_b))
					} else {
						(rgs.fifo_a, rgs.fifo_b)
					}
					# Oh boy sound is off and here comes masterbroom
					Ok({
						..rgs,
						sound_cntl: 0,
						sound_cnth: rgs.sound_cnth.bitwise_and(0xFF00),
						sound_cntx: 0,
						sound1: sound1_init(),
						sound1state: sound1_state_init(),
						sound2: sound2_init(),
						sound3: sound3_init(),
						sound4: sound4_init(),
						fifo_a: new_fifo_a,
						fifo_b: new_fifo_b,
					})
				}
			}
			0x86 => Ok(rgs)
			0x88 => Ok({ ..rgs, sound_bias: val.bitwise_and(0b1100_0011_1111_1110) })
			0x8A => Ok(rgs)
			0xA0 | 0xA2 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, fifo_a: sound_fifo_push_half(rgs.fifo_a, (addr - 0xA0).to_u8_wrap(), val)? })
			} else Ok(rgs)
			0xA4 | 0xA6 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, fifo_b: sound_fifo_push_half(rgs.fifo_b, (addr - 0xA4).to_u8_wrap(), val)? })
			} else Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : SoundRegs, U32, U32 -> Try(SoundRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x60 => write16(write16(rgs, 0x60, lo)?, 0x62, hi)
			0x64 => write16(write16(rgs, 0x64, lo)?, 0x66, 0)
			0x70 => write16(write16(rgs, 0x70, lo)?, 0x72, hi)
			0x74 => write16(write16(rgs, 0x74, lo)?, 0x76, 0)
			0x78 => write16(write16(rgs, 0x78, lo)?, 0x7A, hi)
			0x7C => write16(write16(rgs, 0x7C, lo)?, 0x7E, 0)
			0x80 => write16(write16(rgs, 0x80, lo)?, 0x82, hi)
			0x84 => write16(write16(rgs, 0x84, lo)?, 0x86, 0)
			0x88 => write16(write16(rgs, 0x88, lo)?, 0x8A, 0)
			0x68 => write16(write16(rgs, 0x68, lo)?, 0x6A, 0)
			0x6C => write16(write16(rgs, 0x6C, lo)?, 0x6E, 0)
			0xA0 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, fifo_a: sound_fifo_push_word(rgs.fifo_a, val)? })
			} else Ok(rgs)
			0xA4 => if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
				Ok({ ..rgs, fifo_b: sound_fifo_push_word(rgs.fifo_b, val)? })
			} else Ok(rgs)
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
		sweep_timer: if (sweep_period == 0) 8 else sweep_period, # Stolen from mGBA
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

sound_fifo_init : () -> SoundFIFO
sound_fifo_init = || {
	{
		buffer: List.repeat(0, 7),
		read_pos: 0,
		count: 0,
		pipe_word: 0,
		pipe_remaining: 0,
		sample: 0,
	}
}

sound_fifo_push_byte : SoundFIFO, U8, U8 -> Try(SoundFIFO, [OutOfBounds])
sound_fifo_push_byte = |fifo, offset, val| {
	idx = (fifo.read_pos + fifo.count).mod_by(7).to_u64()
	old_word = fifo.buffer.get(idx)?
	mask = (0b1111_1111.U32).shl_wrap(offset * 8).bitwise_not()
	final_val = old_word.bitwise_and(mask) + val.to_u32().shl_wrap(offset * 8)
	sound_fifo_push_word(fifo, final_val)
}

sound_fifo_push_half : SoundFIFO, U8, U16 -> Try(SoundFIFO, [OutOfBounds])
sound_fifo_push_half = |fifo, offset, val| {
	idx = (fifo.read_pos + fifo.count).mod_by(7).to_u64()
	old_word = fifo.buffer.get(idx)?
	mask = (0b1111_1111_1111_1111.U32).shl_wrap(offset * 8).bitwise_not()
	final_val = old_word.bitwise_and(mask) + val.to_u32().shl_wrap(offset * 8)
	sound_fifo_push_word(fifo, final_val)
}

sound_fifo_push_word : SoundFIFO, U32 -> Try(SoundFIFO, [OutOfBounds])
sound_fifo_push_word = |fifo, val| {
	if fifo.count < 7 {
		idx = (fifo.read_pos + fifo.count).mod_by(7).to_u64()
		Ok({ ..fifo, buffer: List.set(fifo.buffer, idx, val)?, count: fifo.count + 1 })
	} else {
		# Overflow behavior, copied from NBA
		Ok(sound_fifo_reset(fifo))
	}
}

sound_fifo_sample : SoundFIFO -> Try(SoundFIFO, [OutOfBounds])
sound_fifo_sample = |fifo| {
	pipe_loaded = if fifo.pipe_remaining == 0 and fifo.count > 0 {
		{
			..fifo,
			pipe_word: fifo.buffer.get(fifo.read_pos.to_u64())?,
			pipe_remaining: 4,
			count: fifo.count - 1,
			read_pos: (fifo.read_pos + 1).mod_by(7),
		}
	} else {
		fifo
	}
	(new_pipe_word, new_pipe_remaining) = if pipe_loaded.pipe_remaining > 0 {
		(pipe_loaded.pipe_word.shr_wrap(8), pipe_loaded.pipe_remaining - 1)
	} else {
		(pipe_loaded.pipe_word, pipe_loaded.pipe_remaining)
	}
	Ok({
		..pipe_loaded,
		sample: pipe_loaded.pipe_word.to_u8_wrap(),
		pipe_word: new_pipe_word,
		pipe_remaining: new_pipe_remaining,
	})
}

sound_fifo_reset : SoundFIFO -> SoundFIFO
sound_fifo_reset = |fifo| {
	{ ..fifo, buffer: List.repeat(0, 7), read_pos: 0, count: 0 }
}
