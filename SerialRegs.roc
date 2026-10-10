import Bits

Mode : [GP, JOY_BUS, EightBit, ThirtyTwoBit, SixteenBit, UART]

SerialRegs :: {
	siodata32_l : U16,
	siodata32_h : U16,
	siomulti2 : U16,
	siomulti3 : U16,
	siodata8 : U16,
	siocnt : U16,
	rcnt : U16,
}.{
	init : () -> SerialRegs
	init = || {
		{
			siodata32_l: 0,
			siodata32_h: 0,
			siomulti2: 0,
			siomulti3: 0,
			siodata8: 0,
			rcnt: 0,
			siocnt: 0,
		}
	}

	read8 : SerialRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x120 => Ok(rgs.siodata32_l.to_u8_wrap())
			0x121 => Ok(rgs.siodata32_l.shr_wrap(8).to_u8_wrap())
			0x122 => Ok(rgs.siodata32_h.to_u8_wrap())
			0x123 => Ok(rgs.siodata32_h.shr_wrap(8).to_u8_wrap())
			0x124 => Ok(rgs.siomulti2.to_u8_wrap())
			0x125 => Ok(rgs.siomulti2.shr_wrap(8).to_u8_wrap())
			0x126 => Ok(rgs.siomulti3.to_u8_wrap())
			0x127 => Ok(rgs.siomulti3.shr_wrap(8).to_u8_wrap())
			0x128 => Ok(rgs.siocnt.to_u8_wrap())
			0x129 => Ok(rgs.siocnt.shr_wrap(8).to_u8_wrap())
			0x12A => Ok(rgs.siodata8.to_u8_wrap())
			0x12B => Ok(rgs.siodata8.shr_wrap(8).to_u8_wrap())
			0x134 => Ok(rgs.rcnt.to_u8_wrap())
			0x135 => Ok(rgs.rcnt.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : SerialRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x120 => Ok(rgs.siodata32_l)
			0x122 => Ok(rgs.siodata32_h)
			0x124 => Ok(rgs.siomulti2)
			0x126 => Ok(rgs.siomulti3)
			0x128 => Ok(rgs.siocnt)
			0x12A => Ok(rgs.siodata8)
			0x134 => Ok(rgs.rcnt)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : SerialRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x120 | 0x124 | 0x128 => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : SerialRegs, U32, U8 -> Try(SerialRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x120 | 0x121 => {
				old_val = rgs.siodata32_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x120, adjusted_val)
			}
			0x122 | 0x123 => {
				old_val = rgs.siodata32_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x122, adjusted_val)
			}
			0x124 | 0x125 => {
				old_val = rgs.siomulti2
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x124, adjusted_val)
			}
			0x126 | 0x127 => {
				old_val = rgs.siomulti3
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x126, adjusted_val)
			}
			0x128 | 0x129 => {
				old_val = rgs.siocnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x128, adjusted_val)
			}
			0x12A | 0x12B => {
				old_val = rgs.siodata8
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x12A, adjusted_val)
			}
			offset if offset >= 0x12C and offset < 0x130 => Ok(rgs)
			0x134 | 0x135 => {
				old_val = rgs.rcnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x134, adjusted_val)
			}
			offset if offset >= 0x136 and offset < 0x140 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : SerialRegs, U32, U16 -> Try(SerialRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x120 => Ok({ ..rgs, siodata32_l: val })
			0x122 => Ok({ ..rgs, siodata32_h: val })
			0x124 => Ok({ ..rgs, siomulti2: val })
			0x126 => Ok({ ..rgs, siomulti3: val })
			0x128 => {
				mode = mode_decode(rgs.rcnt, val)
				Ok({
					..rgs,
					siocnt: match mode {
						EightBit | ThirtyTwoBit => val.bitwise_and(0b0101_0000_1000_1011).bitwise_or(0b100) # P130
						SixteenBit => val.bitwise_and(0b110_0000_1000_0011) # 138
						UART => val.bitwise_and(0b111_1111_1000_1111) # 144
						_ => val.bitwise_and(0b111_1111_1111_1111) # according to mGBA gotta kick out bit 15
					},
				})
			}
			0x12A => Ok({ ..rgs, siodata8: val })
			offset if offset >= 0x12C and offset < 0x130 => Ok(rgs)
			0x134 => {
				mode = mode_decode(val, rgs.siocnt)
				Ok({
					..rgs,
					rcnt: if mode == GP {
						val.bitwise_and(0b1100_0001_1111_1111)
					} else {
						val.bitwise_and(0b1100_0001_1111_0000) + Bits.get_seg_of_u16_certain(rgs.rcnt, 0, 4)
					},
				})
			}
			offset if offset >= 0x136 and offset < 0x140 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : SerialRegs, U32, U32 -> Try(SerialRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x120 => write16(write16(rgs, 0x120, lo)?, 0x122, hi)
			0x124 => write16(write16(rgs, 0x124, lo)?, 0x126, hi)
			0x128 => write16(write16(rgs, 0x128, lo)?, 0x12A, hi)
			offset if offset >= 0x12C and offset < 0x130 => Ok(rgs)
			0x134 => write16(write16(rgs, 0x134, lo)?, 0x136, 0)
			offset if offset >= 0x136 and offset < 0x140 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}
}

mode_decode : U16, U16 -> Mode
mode_decode = |rcnt, siocnt| {
	# P126 of Nintendo GBA manual
	if Bits.get_seg_of_u16_certain(rcnt, 14, 2) == 2 {
		GP
	} else if Bits.get_seg_of_u16_certain(rcnt, 14, 2) == 3 {
		JOY_BUS
	} else if Bits.get_seg_of_u16_certain(siocnt, 12, 2) == 0 {
		EightBit
	} else if Bits.get_seg_of_u16_certain(siocnt, 12, 2) == 1 {
		ThirtyTwoBit
	} else if Bits.get_seg_of_u16_certain(siocnt, 12, 2) == 2 {
		SixteenBit
	} else {
		UART
	}
}
