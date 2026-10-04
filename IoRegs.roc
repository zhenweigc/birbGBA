IoRegs :: {
	bg0cnt : U16,
	bg1cnt : U16,
	bg2cnt : U16,
	bg3cnt : U16,
}.{
	init : () -> IoRegs
	init = || {
		{
			bg0cnt: 0,
			bg1cnt: 0,
			bg2cnt: 0,
			bg3cnt: 0,
		}
	}

	read8 : IoRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x008 => Ok(rgs.bg0cnt.to_u8_wrap())
			0x009 => Ok(rgs.bg0cnt.shr_wrap(8).to_u8_wrap())
			0x00A => Ok(rgs.bg1cnt.to_u8_wrap())
			0x00B => Ok(rgs.bg1cnt.shr_wrap(8).to_u8_wrap())
			0x00C => Ok(rgs.bg2cnt.to_u8_wrap())
			0x00D => Ok(rgs.bg2cnt.shr_wrap(8).to_u8_wrap())
			0x00E => Ok(rgs.bg3cnt.to_u8_wrap())
			0x00F => Ok(rgs.bg3cnt.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : IoRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x008 => Ok(rgs.bg0cnt)
			0x00A => Ok(rgs.bg1cnt)
			0x00C => Ok(rgs.bg2cnt)
			0x00E => Ok(rgs.bg3cnt)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : IoRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x008 => {
				low = rgs.bg0cnt.to_u32()
				hi = read16(rgs, 0x00A)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x00C => {
				low = rgs.bg2cnt.to_u32()
				hi = read16(rgs, 0x00E)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : IoRegs, U32, U8 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		match addr {
			0x008 => {
				other_half = read8(rgs, 0x009)?.to_u16()
				res = other_half.shl_wrap(8) + val.to_u16()
				Ok({ ..rgs, bg0cnt: res.bitwise_and(0b1101_1111_1111_1111) })
			}
			0x009 => {
				other_half = read8(rgs, 0x008)?.to_u16()
				res = other_half + val.to_u16().shl_wrap(8)
				Ok({ ..rgs, bg0cnt: res.bitwise_and(0b1101_1111_1111_1111) })
			}
			0x00A => {
				other_half = read8(rgs, 0x00B)?.to_u16()
				res = other_half.shl_wrap(8) + val.to_u16()
				Ok({ ..rgs, bg1cnt: res.bitwise_and(0b1101_1111_1111_1111) })
			}
			0x00B => {
				other_half = read8(rgs, 0x00A)?.to_u16()
				res = other_half + val.to_u16().shl_wrap(8)
				Ok({ ..rgs, bg1cnt: res.bitwise_and(0b1101_1111_1111_1111) })
			}
			0x00C => {
				other_half = read8(rgs, 0x00D)?.to_u16()
				res = other_half.shl_wrap(8) + val.to_u16()
				Ok({ ..rgs, bg2cnt: res })
			}
			0x00D => {
				other_half = read8(rgs, 0x00C)?.to_u16()
				res = other_half + val.to_u16().shl_wrap(8)
				Ok({ ..rgs, bg2cnt: res })
			}
			0x00E => {
				other_half = read8(rgs, 0x00F)?.to_u16()
				res = other_half.shl_wrap(8) + val.to_u16()
				Ok({ ..rgs, bg3cnt: res })
			}
			0x00F => {
				other_half = read8(rgs, 0x00E)?.to_u16()
				res = other_half + val.to_u16().shl_wrap(8)
				Ok({ ..rgs, bg3cnt: res })
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : IoRegs, U32, U16 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x008 => Ok({ ..rgs, bg0cnt: val.bitwise_and(0b1101_1111_1111_1111) }) # Directly stolen from mGBA
			0x00A => Ok({ ..rgs, bg1cnt: val.bitwise_and(0b1101_1111_1111_1111) })
			0x00C => Ok({ ..rgs, bg2cnt: val })
			0x00E => Ok({ ..rgs, bg3cnt: val })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : IoRegs, U32, U32 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		match addr {
			0x008 => {
				lo = val.to_u16_wrap()
				hi = val.shr_wrap(16).to_u16_wrap()
				write16(write16(rgs, 0x008, lo)?, 0x00A, hi)
			}
			0x00C => {
				lo = val.to_u16_wrap()
				hi = val.shr_wrap(16).to_u16_wrap()
				write16(write16(rgs, 0x00C, lo)?, 0x00E, hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}
}
