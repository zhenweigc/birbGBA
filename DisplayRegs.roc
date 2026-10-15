import Bits

DisplayRegs :: {
	dispcnt : U16,
	green_swap : U16,
	dispstat : U16,
	vcount : U16,
	bg0cnt : U16,
	bg1cnt : U16,
	bg2cnt : U16,
	bg3cnt : U16,
	bg0hofs : U16,
	bg0vofs : U16,
	bg1hofs : U16,
	bg1vofs : U16,
	bg2hofs : U16,
	bg2vofs : U16,
	bg3hofs : U16,
	bg3vofs : U16,
	bg2pa : U16,
	bg2pb : U16,
	bg2pc : U16,
	bg2pd : U16,
	bg2xl : U16,
	bg2xh : U16,
	bg2yl : U16,
	bg2yh : U16,
	bg3pa : U16,
	bg3pb : U16,
	bg3pc : U16,
	bg3pd : U16,
	bg3xl : U16,
	bg3xh : U16,
	bg3yl : U16,
	bg3yh : U16,
	win0h : U16,
	win1h : U16,
	win0v : U16,
	win1v : U16,
	winin : U16,
	winout : U16,
	mosaic : U16,
	bldcnt : U16,
	bldalpha : U16,
	bldy : U16,
}.{
	init : () -> DisplayRegs
	init = || {
		{
			dispcnt: 0x80,
			green_swap: 0,
			dispstat: 0,
			vcount: 0,
			bg0cnt: 0,
			bg1cnt: 0,
			bg2cnt: 0,
			bg3cnt: 0,
			bg0hofs: 0,
			bg0vofs: 0,
			bg1hofs: 0,
			bg1vofs: 0,
			bg2hofs: 0,
			bg2vofs: 0,
			bg3hofs: 0,
			bg3vofs: 0,
			bg2pa: 0x100,
			bg2pb: 0,
			bg2pc: 0,
			bg2pd: 0x100,
			bg2xl: 0,
			bg2xh: 0,
			bg2yl: 0,
			bg2yh: 0,
			bg3pa: 0x100,
			bg3pb: 0,
			bg3pc: 0,
			bg3pd: 0x100,
			bg3xl: 0,
			bg3xh: 0,
			bg3yl: 0,
			bg3yh: 0,
			win0h: 0,
			win1h: 0,
			win0v: 0,
			win1v: 0,
			winin: 0,
			winout: 0,
			mosaic: 0,
			bldcnt: 0,
			bldalpha: 0,
			bldy: 0,
		}
	}

	read8 : DisplayRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0 => Ok(rgs.dispcnt.to_u8_wrap())
			0x1 => Ok(rgs.dispcnt.shr_wrap(8).to_u8_wrap())
			0x2 => Ok(rgs.green_swap.to_u8_wrap())
			0x3 => Ok(rgs.green_swap.shr_wrap(8).to_u8_wrap())
			0x4 => Ok(rgs.dispstat.to_u8_wrap())
			0x5 => Ok(rgs.dispstat.shr_wrap(8).to_u8_wrap())
			0x6 => Ok(rgs.vcount.to_u8_wrap())
			0x7 => Ok(rgs.vcount.shr_wrap(8).to_u8_wrap())
			0x008 => Ok(rgs.bg0cnt.to_u8_wrap())
			0x009 => Ok(rgs.bg0cnt.shr_wrap(8).to_u8_wrap())
			0x00A => Ok(rgs.bg1cnt.to_u8_wrap())
			0x00B => Ok(rgs.bg1cnt.shr_wrap(8).to_u8_wrap())
			0x00C => Ok(rgs.bg2cnt.to_u8_wrap())
			0x00D => Ok(rgs.bg2cnt.shr_wrap(8).to_u8_wrap())
			0x00E => Ok(rgs.bg3cnt.to_u8_wrap())
			0x00F => Ok(rgs.bg3cnt.shr_wrap(8).to_u8_wrap())
			0x48 => Ok(rgs.winin.to_u8_wrap())
			0x49 => Ok(rgs.winin.shr_wrap(8).to_u8_wrap())
			0x4A => Ok(rgs.winout.to_u8_wrap())
			0x4B => Ok(rgs.winout.shr_wrap(8).to_u8_wrap())
			0x50 => Ok(rgs.bldcnt.to_u8_wrap())
			0x51 => Ok(rgs.bldcnt.shr_wrap(8).to_u8_wrap())
			0x52 => Ok(rgs.bldalpha.to_u8_wrap())
			0x53 => Ok(rgs.bldalpha.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : DisplayRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0 => Ok(rgs.dispcnt)
			0x2 => Ok(rgs.green_swap)
			0x4 => Ok(rgs.dispstat)
			0x6 => Ok(rgs.vcount)
			0x008 => Ok(rgs.bg0cnt)
			0x00A => Ok(rgs.bg1cnt)
			0x00C => Ok(rgs.bg2cnt)
			0x00E => Ok(rgs.bg3cnt)
			0x48 => Ok(rgs.winin)
			0x4A => Ok(rgs.winout)
			0x50 => Ok(rgs.bldcnt)
			0x52 => Ok(rgs.bldalpha)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : DisplayRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x0 | 0x4 | 0x8 | 0xC | 0x48 | 0x50 => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : DisplayRegs, U32, U8 -> Try(DisplayRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0 | 0x1 => {
				old_val = rgs.dispcnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x0, adjusted_val)
			}
			0x002 | 0x003 => {
				old_val = rgs.green_swap
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x2, adjusted_val)
			}
			0x4 => {
				other_half = read8(rgs, 0x005)?.to_u16()
				adjusted_val = val.to_u16().bitwise_and(0b11_1000) + Bits.get_seg_of_u16_certain(rgs.dispstat, 0, 3) + Bits.get_seg_of_u16_certain(rgs.dispstat, 6, 2).shl_wrap(6)
				res = other_half.shl_wrap(8) + adjusted_val
				if res.shr_wrap(8) == rgs.vcount {
					Ok({ ..rgs, dispstat: res.bitwise_or(0b100) })
				} else {
					Ok({ ..rgs, dispstat: res.bitwise_and(0b1111_1111_1111_1011) })
				}
			}
			0x5 => {
				other_half = read8(rgs, 0x004)?.to_u16()
				res = other_half + val.to_u16().shl_wrap(8)
				if res.shr_wrap(8) == rgs.vcount {
					Ok({ ..rgs, dispstat: res.bitwise_or(0b100) })
				} else {
					Ok({ ..rgs, dispstat: res.bitwise_and(0b1111_1111_1111_1011) })
				}
			}
			0x6 | 0x7 => Ok(rgs) # vcount no write
			0x008 | 0x009 => {
				old_val = rgs.bg0cnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x8, adjusted_val)
			}
			0x00A | 0x00B => {
				old_val = rgs.bg1cnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xA, adjusted_val)
			}
			0x00C | 0x00D => {
				old_val = rgs.bg2cnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xC, adjusted_val)
			}
			0x00E | 0x00F => {
				old_val = rgs.bg3cnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xE, adjusted_val)
			}
			0x10 | 0x11 => {
				old_val = rgs.bg0hofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10, adjusted_val)
			}
			0x12 | 0x13 => {
				old_val = rgs.bg0vofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x12, adjusted_val)
			}
			0x14 | 0x15 => {
				old_val = rgs.bg1hofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x14, adjusted_val)
			}
			0x16 | 0x17 => {
				old_val = rgs.bg1vofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x16, adjusted_val)
			}
			0x18 | 0x19 => {
				old_val = rgs.bg2hofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x18, adjusted_val)
			}
			0x1A | 0x1B => {
				old_val = rgs.bg2vofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x1A, adjusted_val)
			}
			0x1C | 0x1D => {
				old_val = rgs.bg3hofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x1C, adjusted_val)
			}
			0x1E | 0x1F => {
				old_val = rgs.bg3vofs
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x1E, adjusted_val)
			}
			0x20 | 0x21 => {
				old_val = rgs.bg2pa
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x20, adjusted_val)
			}
			0x22 | 0x23 => {
				old_val = rgs.bg2pb
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x22, adjusted_val)
			}
			0x24 | 0x25 => {
				old_val = rgs.bg2pc
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x24, adjusted_val)
			}
			0x26 | 0x27 => {
				old_val = rgs.bg2pd
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x26, adjusted_val)
			}
			0x28 | 0x29 => {
				old_val = rgs.bg2xl
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x28, adjusted_val)
			}
			0x2A | 0x2B => {
				old_val = rgs.bg2xh
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x2A, adjusted_val)
			}
			0x2C | 0x2D => {
				old_val = rgs.bg2yl
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x2C, adjusted_val)
			}
			0x2E | 0x2F => {
				old_val = rgs.bg2yh
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x2E, adjusted_val)
			}
			0x30 | 0x31 => {
				old_val = rgs.bg3pa
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x30, adjusted_val)
			}
			0x32 | 0x33 => {
				old_val = rgs.bg3pb
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x32, adjusted_val)
			}
			0x34 | 0x35 => {
				old_val = rgs.bg3pc
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x34, adjusted_val)
			}
			0x36 | 0x37 => {
				old_val = rgs.bg3pd
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x36, adjusted_val)
			}
			0x38 | 0x39 => {
				old_val = rgs.bg3xl
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x38, adjusted_val)
			}
			0x3A | 0x3B => {
				old_val = rgs.bg3xh
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x3A, adjusted_val)
			}
			0x3C | 0x3D => {
				old_val = rgs.bg3yl
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x3C, adjusted_val)
			}
			0x3E | 0x3F => {
				old_val = rgs.bg3yh
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x3E, adjusted_val)
			}
			0x40 | 0x41 => {
				old_val = rgs.win0h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x40, adjusted_val)
			}
			0x42 | 0x43 => {
				old_val = rgs.win1h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x42, adjusted_val)
			}
			0x44 | 0x45 => {
				old_val = rgs.win0v
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x44, adjusted_val)
			}
			0x46 | 0x47 => {
				old_val = rgs.win1v
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x46, adjusted_val)
			}
			0x48 | 0x49 => {
				old_val = rgs.winin
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x48, adjusted_val)
			}
			0x4A | 0x4B => {
				old_val = rgs.winout
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x4A, adjusted_val)
			}
			0x4C | 0x4D => {
				old_val = rgs.mosaic
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x4C, adjusted_val)
			}
			0x04E | 0x4F => Ok(rgs)
			0x50 | 0x51 => {
				old_val = rgs.bldcnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x50, adjusted_val)
			}
			0x52 | 0x53 => {
				old_val = rgs.bldalpha
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x52, adjusted_val)
			}
			0x54 | 0x55 => {
				old_val = rgs.bldy
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x54, adjusted_val)
			}
			offset if offset >= 0x56 and offset <= 0x5F => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : DisplayRegs, U32, U16 -> Try(DisplayRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0 => Ok({ ..rgs, dispcnt: val.bitwise_and(0b1111_1111_1111_0111) })
			0x2 => Ok({ ..rgs, green_swap: val })
			0x4 => {
				seg1 = Bits.Bits.get_seg_of_u16_certain(rgs.dispstat, 0, 3)
				seg2 = Bits.Bits.get_seg_of_u16_certain(rgs.dispstat, 6, 2).shl_wrap(6)
				adjusted_val = val.bitwise_and(0b1111_1111_0011_1000) + seg1 + seg2
				if adjusted_val.shr_wrap(8) == rgs.vcount {
					Ok({ ..rgs, dispstat: adjusted_val.bitwise_or(0b100) })
				} else {
					Ok({ ..rgs, dispstat: adjusted_val.bitwise_and(0b1111_1111_1111_1011) })
				}
			}
			0x6 => Ok(rgs)
			0x008 => Ok({ ..rgs, bg0cnt: val.bitwise_and(0b1101_1111_1111_1111) }) # Directly stolen from mGBA
			0x00A => Ok({ ..rgs, bg1cnt: val.bitwise_and(0b1101_1111_1111_1111) })
			0x00C => Ok({ ..rgs, bg2cnt: val })
			0x00E => Ok({ ..rgs, bg3cnt: val })
			0x10 => Ok({ ..rgs, bg0hofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x12 => Ok({ ..rgs, bg0vofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x14 => Ok({ ..rgs, bg1hofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x16 => Ok({ ..rgs, bg1vofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x18 => Ok({ ..rgs, bg2hofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x1A => Ok({ ..rgs, bg2vofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x1C => Ok({ ..rgs, bg3hofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x1E => Ok({ ..rgs, bg3vofs: val.bitwise_and(0b0000_0001_1111_1111) })
			0x20 => Ok({ ..rgs, bg2pa: val })
			0x22 => Ok({ ..rgs, bg2pb: val })
			0x24 => Ok({ ..rgs, bg2pc: val })
			0x26 => Ok({ ..rgs, bg2pd: val })
			0x28 => Ok({ ..rgs, bg2xl: val })
			0x2A => Ok({ ..rgs, bg2xh: val.bitwise_and(0x0FFF) })
			0x2C => Ok({ ..rgs, bg2yl: val })
			0x2E => Ok({ ..rgs, bg2yh: val.bitwise_and(0x0FFF) })
			0x30 => Ok({ ..rgs, bg3pa: val })
			0x32 => Ok({ ..rgs, bg3pb: val })
			0x34 => Ok({ ..rgs, bg3pc: val })
			0x36 => Ok({ ..rgs, bg3pd: val })
			0x38 => Ok({ ..rgs, bg3xl: val })
			0x3A => Ok({ ..rgs, bg3xh: val.bitwise_and(0x0FFF) })
			0x3C => Ok({ ..rgs, bg3yl: val })
			0x3E => Ok({ ..rgs, bg3yh: val.bitwise_and(0x0FFF) })
			0x40 => Ok({ ..rgs, win0h: val })
			0x42 => Ok({ ..rgs, win1h: val })
			0x44 => Ok({ ..rgs, win0v: val })
			0x46 => Ok({ ..rgs, win1v: val })
			0x48 => Ok({ ..rgs, winin: val.bitwise_and(0b0011_1111_0011_1111) })
			0x4A => Ok({ ..rgs, winout: val.bitwise_and(0b0011_1111_0011_1111) })
			0x4C => Ok({ ..rgs, mosaic: val })
			0x04E => Ok(rgs)
			0x50 => Ok({ ..rgs, bldcnt: val.bitwise_and(0b0011_1111_1111_1111) })
			0x52 => Ok({ ..rgs, bldalpha: val.bitwise_and(0b0001_1111_0001_1111) }) # turns out this is writable according to mGBA
			0x54 => Ok({ ..rgs, bldy: val.bitwise_and(0b0000_0000_0001_1111) })
			offset if offset >= 0x056 and offset <= 0x05E and offset.mod_by(2) == 0 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : DisplayRegs, U32, U32 -> Try(DisplayRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x0 => write16(write16(rgs, 0x0, lo)?, 0x2, hi)
			0x4 => write16(write16(rgs, 0x004, lo)?, 0x006, 0)
			0x008 => write16(write16(rgs, 0x008, lo)?, 0x00A, hi)
			0x00C => write16(write16(rgs, 0x00C, lo)?, 0x00E, hi)
			0x10 => write16(write16(rgs, 0x010, lo)?, 0x0012, hi)
			0x14 => write16(write16(rgs, 0x014, lo)?, 0x0016, hi)
			0x18 => write16(write16(rgs, 0x018, lo)?, 0x001A, hi)
			0x1C => write16(write16(rgs, 0x01C, lo)?, 0x001E, hi)
			0x20 => write16(write16(rgs, 0x020, lo)?, 0x0022, hi)
			0x24 => write16(write16(rgs, 0x024, lo)?, 0x0026, hi)
			0x28 => write16(write16(rgs, 0x028, lo)?, 0x002A, hi)
			0x2C => write16(write16(rgs, 0x02C, lo)?, 0x002E, hi)
			0x30 => write16(write16(rgs, 0x030, lo)?, 0x0032, hi)
			0x34 => write16(write16(rgs, 0x034, lo)?, 0x0036, hi)
			0x38 => write16(write16(rgs, 0x038, lo)?, 0x003A, hi)
			0x3C => write16(write16(rgs, 0x03C, lo)?, 0x003E, hi)
			0x40 => write16(write16(rgs, 0x040, lo)?, 0x0042, hi)
			0x44 => write16(write16(rgs, 0x044, lo)?, 0x0046, hi)
			0x48 => write16(write16(rgs, 0x048, lo)?, 0x004A, hi)
			0x4C => write16(write16(rgs, 0x04C, lo)?, 0x004E, hi)
			0x50 => write16(write16(rgs, 0x050, lo)?, 0x0052, hi)
			0x54 => write16(write16(rgs, 0x054, lo)?, 0x0056, hi)
			0x58 | 0x5C => Ok(rgs) # Unused addr
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	advance_scanline : DisplayRegs -> (DisplayRegs, U16)
	advance_scanline = |rgs| {
		advanced_vcount = (rgs.vcount + 1).mod_by(228)
		bit0 = if (advanced_vcount > 159 and advanced_vcount < 227) {
			1
		} else {
			0
		}
		bit2 = if advanced_vcount == Bits.get_seg_of_u16_certain(rgs.dispstat, 8, 8) {
			1
		} else {
			0
		}
		low_3_bit = bit0 + bit2.shl_wrap(2)
		mask = (
			if advanced_vcount == 160 and Bits.get_ith_bit_u16_certain(rgs.dispstat, 3) {
				1
			} else {
				0
			}
		) + (
			if bit2 == 1 and Bits.get_ith_bit_u16_certain(rgs.dispstat, 5) {
				0b100
			} else {
				0
			}
		)
		(
			{
				..rgs,
				vcount: advanced_vcount,
				dispstat: rgs.dispstat.bitwise_and(0b1111_1111_1111_1000) + low_3_bit,
			},
			mask,
		)
	}
}
