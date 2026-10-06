import Bits

SoundRegs :: {
	sound_cntl : U16,
	sound_cnth : U16,
	sound_cntx : U16,
	sound_bias : U16,
}.{
	init : () -> SoundRegs
	init = || {
		{
			sound_cntl: 0,
			sound_cnth: 0,
			sound_cntx: 0,
			sound_bias: 0x200,
		}
	}

	read8 : SoundRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
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
			0x84 => Ok(rgs.sound_cntx.bitwise_and(0b1000_1111).to_u8_wrap())
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
			0x80 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok(rgs.sound_cntl.bitwise_and(0b1111_1111_0111_0111))
				} else {
					Ok(0)
				}
			}
			0x82 => Ok(rgs.sound_cnth.bitwise_and(0b111_0111_0000_1111))
			0x84 => Ok(rgs.sound_cntx.bitwise_and(0b1000_1111))
			0x86 => Ok(0)
			0x88 => Ok(rgs.sound_bias.bitwise_and(0b1100_0011_1111_1110))
			0x8A => Ok(0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : SoundRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x80 => {
				low = read16(rgs, 0x80)?.to_u32()
				hi = read16(rgs, 0x82)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x84 => {
				low = read16(rgs, 0x84)?.to_u32()
				hi = read16(rgs, 0x86)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x88 => {
				low = read16(rgs, 0x88)?.to_u32()
				hi = read16(rgs, 0x8A)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : SoundRegs, U32, U8 -> Try(SoundRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
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
			0x80 => {
				if Bits.get_ith_bit_u16_certain(rgs.sound_cntx, 7) {
					Ok({ ..rgs, sound_cntl: val.bitwise_and(0b1111_1111_0111_0111) })
				} else {
					Ok(rgs)
				}
			}
			0x82 => {
				Ok({ ..rgs, sound_cnth: val.bitwise_and(0b111_0111_0000_1111) })
			}
			0x84 => {
				# Somehow this reg write in needs to update FIFOs
				# gonna be painful
				if Bits.get_ith_bit_u16_certain(val, 7) {
					Ok({ ..rgs, sound_cntx: rgs.sound_cntx.bitwise_and(0b1111).bitwise_or(0b1000_0000) })
				} else {
					Ok({
						..rgs,
						sound_cntl: 0,
						sound_cnth: rgs.sound_cnth.bitwise_and(0xFF00),
						sound_cntx: 0,
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
			0x80 => write16(write16(rgs, 0x80, lo)?, 0x82, hi)
			0x84 => write16(write16(rgs, 0x84, lo)?, 0x86, 0)
			0x88 => write16(write16(rgs, 0x88, lo)?, 0x8A, 0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}
}
