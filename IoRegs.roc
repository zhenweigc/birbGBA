DMAReg : {
	sad_l : U16,
	sad_h : U16,
	dad_l : U16,
	dad_h : U16,
	cnt_l : U16,
	cnt_h : U16,
}

TimerReg : {
	reload : U16,
	counter : U16,
	control : U16,
}

IoRegs :: {
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
	dma0 : DMAReg,
	dma1 : DMAReg,
	dma2 : DMAReg,
	dma3 : DMAReg,
	timer0 : TimerReg,
	timer1 : TimerReg,
	timer2 : TimerReg,
	timer3 : TimerReg,
}.{
	init : () -> IoRegs
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
			dma0: dma_init(),
			dma1: dma_init(),
			dma2: dma_init(),
			dma3: dma_init(),
			timer0: timer_init(),
			timer1: timer_init(),
			timer2: timer_init(),
			timer3: timer_init(),
		}
	}

	read8 : IoRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
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
			0x0B8 | 0x0B9 | 0x0C4 | 0x0C5 | 0x0D0 | 0x0D1 | 0x0DC | 0x0DD => Ok(0)
			0x0BA => Ok(rgs.dma0.cnt_h.to_u8_wrap())
			0x0BB => Ok(rgs.dma0.cnt_h.shr_wrap(8).to_u8_wrap())
			0x0C6 => Ok(rgs.dma1.cnt_h.to_u8_wrap())
			0x0C7 => Ok(rgs.dma1.cnt_h.shr_wrap(8).to_u8_wrap())
			0x0D2 => Ok(rgs.dma2.cnt_h.to_u8_wrap())
			0x0D3 => Ok(rgs.dma2.cnt_h.shr_wrap(8).to_u8_wrap())
			0x0DE => Ok(rgs.dma3.cnt_h.to_u8_wrap())
			0x0DF => Ok(rgs.dma3.cnt_h.shr_wrap(8).to_u8_wrap())
			0x100 => Ok(rgs.timer0.counter.to_u8_wrap())
			0x101 => Ok(rgs.timer0.counter.shr_wrap(8).to_u8_wrap())
			0x102 => Ok(rgs.timer0.control.to_u8_wrap())
			0x103 => Ok(rgs.timer0.control.shr_wrap(8).to_u8_wrap())
			0x104 => Ok(rgs.timer1.counter.to_u8_wrap())
			0x105 => Ok(rgs.timer1.counter.shr_wrap(8).to_u8_wrap())
			0x106 => Ok(rgs.timer1.control.to_u8_wrap())
			0x107 => Ok(rgs.timer1.control.shr_wrap(8).to_u8_wrap())
			0x108 => Ok(rgs.timer2.counter.to_u8_wrap())
			0x109 => Ok(rgs.timer2.counter.shr_wrap(8).to_u8_wrap())
			0x10A => Ok(rgs.timer2.control.to_u8_wrap())
			0x10B => Ok(rgs.timer2.control.shr_wrap(8).to_u8_wrap())
			0x10C => Ok(rgs.timer3.counter.to_u8_wrap())
			0x10D => Ok(rgs.timer3.counter.shr_wrap(8).to_u8_wrap())
			0x10E => Ok(rgs.timer3.control.to_u8_wrap())
			0x10F => Ok(rgs.timer3.control.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : IoRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
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
			0x0B8 | 0x0C4 | 0x0D0 | 0x0DC => Ok(0)
			0x0BA => Ok(rgs.dma0.cnt_h)
			0x0C6 => Ok(rgs.dma1.cnt_h)
			0x0D2 => Ok(rgs.dma2.cnt_h)
			0x0DE => Ok(rgs.dma3.cnt_h)
			0x100 => Ok(rgs.timer0.counter)
			0x102 => Ok(rgs.timer0.control)
			0x104 => Ok(rgs.timer1.counter)
			0x106 => Ok(rgs.timer1.control)
			0x108 => Ok(rgs.timer2.counter)
			0x10A => Ok(rgs.timer2.control)
			0x10C => Ok(rgs.timer3.counter)
			0x10E => Ok(rgs.timer3.control)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : IoRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x0 => {
				low = rgs.dispcnt.to_u32()
				hi = read16(rgs, 0x2)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x4 => {
				low = rgs.dispstat.to_u32()
				hi = read16(rgs, 0x6)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
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
			0x48 => {
				low = rgs.winin.to_u32()
				hi = read16(rgs, 0x04A)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x50 => {
				low = rgs.bldcnt.to_u32()
				hi = read16(rgs, 0x052)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x0B8 => Ok(rgs.dma0.cnt_h.to_u32().shl_wrap(16))
			0x0C4 => Ok(rgs.dma1.cnt_h.to_u32().shl_wrap(16))
			0x0D0 => Ok(rgs.dma2.cnt_h.to_u32().shl_wrap(16))
			0x0DC => Ok(rgs.dma3.cnt_h.to_u32().shl_wrap(16))
			0x100 => {
				low = rgs.timer0.counter.to_u32()
				hi = read16(rgs, 0x102)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x104 => {
				low = rgs.timer1.counter.to_u32()
				hi = read16(rgs, 0x106)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x108 => {
				low = rgs.timer2.counter.to_u32()
				hi = read16(rgs, 0x10A)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			0x10C => {
				low = rgs.timer3.counter.to_u32()
				hi = read16(rgs, 0x10E)?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : IoRegs, U32, U8 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0 | 0x1 => {
				old_val = rgs.dispcnt
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x0, adjusted_val)
			}
			0x002 | 0x003 => {
				old_val = rgs.green_swap
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x2, adjusted_val)
			}
			0x4 => {
				other_half = read8(rgs, 0x005)?.to_u16()
				adjusted_val = val.to_u16().bitwise_and(0b11_1000) + get_seg_of_u16_certain(rgs.dispstat, 0, 3) + get_seg_of_u16_certain(rgs.dispstat, 6, 2).shl_wrap(6)
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
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x8, adjusted_val)
			}
			0x00A | 0x00B => {
				old_val = rgs.bg1cnt
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xA, adjusted_val)
			}
			0x00C | 0x00D => {
				old_val = rgs.bg2cnt
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xC, adjusted_val)
			}
			0x00E | 0x00F => {
				old_val = rgs.bg3cnt
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xE, adjusted_val)
			}
			0x10 | 0x11 => {
				old_val = rgs.bg0hofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x10, adjusted_val)
			}
			0x12 | 0x13 => {
				old_val = rgs.bg0vofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x12, adjusted_val)
			}
			0x14 | 0x15 => {
				old_val = rgs.bg1hofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x14, adjusted_val)
			}
			0x16 | 0x17 => {
				old_val = rgs.bg1vofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x16, adjusted_val)
			}
			0x18 | 0x19 => {
				old_val = rgs.bg2hofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x18, adjusted_val)
			}
			0x1A | 0x1B => {
				old_val = rgs.bg2vofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x1A, adjusted_val)
			}
			0x1C | 0x1D => {
				old_val = rgs.bg3hofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x1C, adjusted_val)
			}
			0x1E | 0x1F => {
				old_val = rgs.bg3vofs
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x1E, adjusted_val)
			}
			0x20 | 0x21 => {
				old_val = rgs.bg2pa
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x20, adjusted_val)
			}
			0x22 | 0x23 => {
				old_val = rgs.bg2pb
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x22, adjusted_val)
			}
			0x24 | 0x25 => {
				old_val = rgs.bg2pc
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x24, adjusted_val)
			}
			0x26 | 0x27 => {
				old_val = rgs.bg2pd
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x26, adjusted_val)
			}
			0x28 | 0x29 => {
				old_val = rgs.bg2xl
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x28, adjusted_val)
			}
			0x2A | 0x2B => {
				old_val = rgs.bg2xh
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x2A, adjusted_val)
			}
			0x2C | 0x2D => {
				old_val = rgs.bg2yl
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x2C, adjusted_val)
			}
			0x2E | 0x2F => {
				old_val = rgs.bg2yh
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x2E, adjusted_val)
			}
			0x30 | 0x31 => {
				old_val = rgs.bg3pa
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x30, adjusted_val)
			}
			0x32 | 0x33 => {
				old_val = rgs.bg3pb
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x32, adjusted_val)
			}
			0x34 | 0x35 => {
				old_val = rgs.bg3pc
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x34, adjusted_val)
			}
			0x36 | 0x37 => {
				old_val = rgs.bg3pd
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x36, adjusted_val)
			}
			0x38 | 0x39 => {
				old_val = rgs.bg3xl
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x38, adjusted_val)
			}
			0x3A | 0x3B => {
				old_val = rgs.bg3xh
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x3A, adjusted_val)
			}
			0x3C | 0x3D => {
				old_val = rgs.bg3yl
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x3C, adjusted_val)
			}
			0x3E | 0x3F => {
				old_val = rgs.bg3yh
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x3E, adjusted_val)
			}
			0x40 | 0x41 => {
				old_val = rgs.win0h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x40, adjusted_val)
			}
			0x42 | 0x43 => {
				old_val = rgs.win1h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x42, adjusted_val)
			}
			0x44 | 0x45 => {
				old_val = rgs.win0v
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x44, adjusted_val)
			}
			0x46 | 0x47 => {
				old_val = rgs.win1v
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x46, adjusted_val)
			}
			0x48 | 0x49 => {
				old_val = rgs.winin
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x48, adjusted_val)
			}
			0x4A | 0x4B => {
				old_val = rgs.winout
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x4A, adjusted_val)
			}
			0x4C | 0x4D => {
				old_val = rgs.mosaic
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x4C, adjusted_val)
			}
			0x04E | 0x4F => Ok(rgs)
			0x50 | 0x51 => {
				old_val = rgs.bldcnt
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x50, adjusted_val)
			}
			0x52 | 0x53 => {
				old_val = rgs.bldalpha
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x52, adjusted_val)
			}
			0x54 | 0x55 => {
				old_val = rgs.bldy
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x54, adjusted_val)
			}
			offset if offset >= 0x56 and offset <= 0x5F => Ok(rgs)
			0x0B0 | 0x0B1 => {
				old_val = rgs.dma0.sad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xB0, adjusted_val)
			}
			0x0B2 | 0x0B3 => {
				old_val = rgs.dma0.sad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xB2, adjusted_val)
			}
			0x0B4 | 0x0B5 => {
				old_val = rgs.dma0.dad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xB4, adjusted_val)
			}
			0x0B6 | 0x0B7 => {
				old_val = rgs.dma0.dad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xB6, adjusted_val)
			}
			0x0B8 | 0x0B9 => {
				old_val = rgs.dma0.cnt_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xB8, adjusted_val)
			}
			0x0BA | 0x0BB => {
				old_val = rgs.dma0.cnt_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xBA, adjusted_val)
			}
			0x0BC | 0x0BD => {
				old_val = rgs.dma1.sad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xBC, adjusted_val)
			}
			0x0BE | 0x0BF => {
				old_val = rgs.dma1.sad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xBE, adjusted_val)
			}
			0x0C0 | 0x0C1 => {
				old_val = rgs.dma1.dad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xC0, adjusted_val)
			}
			0x0C2 | 0x0C3 => {
				old_val = rgs.dma1.dad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xC2, adjusted_val)
			}
			0x0C4 | 0x0C5 => {
				old_val = rgs.dma1.cnt_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xC4, adjusted_val)
			}
			0x0C6 | 0x0C7 => {
				old_val = rgs.dma1.cnt_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xC6, adjusted_val)
			}
			0x0C8 | 0x0C9 => {
				old_val = rgs.dma2.sad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xC8, adjusted_val)
			}
			0x0CA | 0x0CB => {
				old_val = rgs.dma2.sad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xCA, adjusted_val)
			}
			0x0CC | 0x0CD => {
				old_val = rgs.dma2.dad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xCC, adjusted_val)
			}
			0x0CE | 0x0CF => {
				old_val = rgs.dma2.dad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xCE, adjusted_val)
			}
			0x0D0 | 0x0D1 => {
				old_val = rgs.dma2.cnt_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xD0, adjusted_val)
			}
			0x0D2 | 0x0D3 => {
				old_val = rgs.dma2.cnt_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xD2, adjusted_val)
			}
			0x0D4 | 0x0D5 => {
				old_val = rgs.dma3.sad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xD4, adjusted_val)
			}
			0x0D6 | 0x0D7 => {
				old_val = rgs.dma3.sad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xD6, adjusted_val)
			}
			0x0D8 | 0x0D9 => {
				old_val = rgs.dma3.dad_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xD8, adjusted_val)
			}
			0x0DA | 0x0DB => {
				old_val = rgs.dma3.dad_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xDA, adjusted_val)
			}
			0x0DC | 0x0DD => {
				old_val = rgs.dma3.cnt_l
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xDC, adjusted_val)
			}
			0x0DE | 0x0DF => {
				old_val = rgs.dma3.cnt_h
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0xDE, adjusted_val)
			}
			offset if offset >= 0x0E0 and offset <= 0x0FF => Ok(rgs)
			0x100 | 0x101 => {
				old_val = rgs.timer0.reload
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x100, adjusted_val)
			}
			0x102 | 0x103 => {
				old_val = rgs.timer0.control
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x102, adjusted_val)
			}
			0x104 | 0x105 => {
				old_val = rgs.timer1.reload
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x104, adjusted_val)
			}
			0x106 | 0x107 => {
				old_val = rgs.timer1.control
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x106, adjusted_val)
			}
			0x108 | 0x109 => {
				old_val = rgs.timer2.reload
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x108, adjusted_val)
			}
			0x10A | 0x10B => {
				old_val = rgs.timer2.control
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x10A, adjusted_val)
			}
			0x10C | 0x10D => {
				old_val = rgs.timer3.reload
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x10C, adjusted_val)
			}
			0x10E | 0x10F => {
				old_val = rgs.timer3.control
				adjusted_val = replace_byte(old_val, isHi, val)
				write16(rgs, 0x10E, adjusted_val)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : IoRegs, U32, U16 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0 => Ok({ ..rgs, dispcnt: val.bitwise_and(0b1111_1111_1111_0111) })
			0x2 => Ok({ ..rgs, green_swap: val })
			0x4 => {
				seg1 = get_seg_of_u16_certain(rgs.dispstat, 0, 3)
				seg2 = get_seg_of_u16_certain(rgs.dispstat, 6, 2).shl_wrap(6)
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
			0x0B0 => Ok({ ..rgs, dma0: { ..rgs.dma0, sad_l: val.bitwise_and(0xFFFE) } })
			0x0B2 => Ok({ ..rgs, dma0: { ..rgs.dma0, sad_h: val.bitwise_and(0x07FF) } })
			0x0B4 => Ok({ ..rgs, dma0: { ..rgs.dma0, dad_l: val.bitwise_and(0xFFFE) } })
			0x0B6 => Ok({ ..rgs, dma0: { ..rgs.dma0, dad_h: val.bitwise_and(0x07FF) } })
			0x0B8 => Ok({ ..rgs, dma0: { ..rgs.dma0, cnt_l: val.bitwise_and(0x3FFF) } })
			0x0BA => Ok({ ..rgs, dma0: { ..rgs.dma0, cnt_h: val.bitwise_and(0xF7E0) } })
			0x0BC => Ok({ ..rgs, dma1: { ..rgs.dma1, sad_l: val.bitwise_and(0xFFFE) } })
			0x0BE => Ok({ ..rgs, dma1: { ..rgs.dma1, sad_h: val.bitwise_and(0x0FFF) } })
			0x0C0 => Ok({ ..rgs, dma1: { ..rgs.dma1, dad_l: val.bitwise_and(0xFFFE) } })
			0x0C2 => Ok({ ..rgs, dma1: { ..rgs.dma1, dad_h: val.bitwise_and(0x07FF) } })
			0x0C4 => Ok({ ..rgs, dma1: { ..rgs.dma1, cnt_l: val.bitwise_and(0x3FFF) } })
			0x0C6 => Ok({ ..rgs, dma1: { ..rgs.dma1, cnt_h: val.bitwise_and(0xF7E0) } })
			0x0C8 => Ok({ ..rgs, dma2: { ..rgs.dma2, sad_l: val.bitwise_and(0xFFFE) } })
			0x0CA => Ok({ ..rgs, dma2: { ..rgs.dma2, sad_h: val.bitwise_and(0x0FFF) } })
			0x0CC => Ok({ ..rgs, dma2: { ..rgs.dma2, dad_l: val.bitwise_and(0xFFFE) } })
			0x0CE => Ok({ ..rgs, dma2: { ..rgs.dma2, dad_h: val.bitwise_and(0x07FF) } })
			0x0D0 => Ok({ ..rgs, dma2: { ..rgs.dma2, cnt_l: val.bitwise_and(0x3FFF) } })
			0x0D2 => Ok({ ..rgs, dma2: { ..rgs.dma2, cnt_h: val.bitwise_and(0xF7E0) } })
			0x0D4 => Ok({ ..rgs, dma3: { ..rgs.dma3, sad_l: val.bitwise_and(0xFFFE) } })
			0x0D6 => Ok({ ..rgs, dma3: { ..rgs.dma3, sad_h: val.bitwise_and(0x0FFF) } })
			0x0D8 => Ok({ ..rgs, dma3: { ..rgs.dma3, dad_l: val.bitwise_and(0xFFFE) } })
			0x0DA => Ok({ ..rgs, dma3: { ..rgs.dma3, dad_h: val.bitwise_and(0x0FFF) } })
			0x0DC => Ok({ ..rgs, dma3: { ..rgs.dma3, cnt_l: val } })
			0x0DE => Ok({ ..rgs, dma3: { ..rgs.dma3, cnt_h: val.bitwise_and(0xFFE0) } })
			offset if offset >= 0x0E0 and offset <= 0x0FE and offset.mod_by(2) == 0 => Ok(rgs)
			0x100 => Ok({ ..rgs, timer0: { ..rgs.timer0, reload: val } })
			0x102 => Ok({ ..rgs, timer0: timer_write_control(rgs.timer0, val) })
			0x104 => Ok({ ..rgs, timer1: { ..rgs.timer1, reload: val } })
			0x106 => Ok({ ..rgs, timer1: timer_write_control(rgs.timer1, val) })
			0x108 => Ok({ ..rgs, timer2: { ..rgs.timer2, reload: val } })
			0x10A => Ok({ ..rgs, timer2: timer_write_control(rgs.timer2, val) })
			0x10C => Ok({ ..rgs, timer3: { ..rgs.timer3, reload: val } })
			0x10E => Ok({ ..rgs, timer3: timer_write_control(rgs.timer3, val) })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : IoRegs, U32, U32 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
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
			0x0B0 => write16(write16(rgs, 0x0B0, lo)?, 0x00B2, hi)
			0x0B4 => write16(write16(rgs, 0x0B4, lo)?, 0x00B6, hi)
			0x0B8 => write16(write16(rgs, 0x0B8, lo)?, 0x00BA, hi)
			0x0BC => write16(write16(rgs, 0x0BC, lo)?, 0x00BE, hi)
			0x0C0 => write16(write16(rgs, 0x0C0, lo)?, 0x00C2, hi)
			0x0C4 => write16(write16(rgs, 0x0C4, lo)?, 0x0C6, hi)
			0x0C8 => write16(write16(rgs, 0x0C8, lo)?, 0x0CA, hi)
			0x0CC => write16(write16(rgs, 0x0CC, lo)?, 0x0CE, hi)
			0x0D0 => write16(write16(rgs, 0x0D0, lo)?, 0x0D2, hi)
			0x0D4 => write16(write16(rgs, 0x0D4, lo)?, 0x0D6, hi)
			0x0D8 => write16(write16(rgs, 0x0D8, lo)?, 0x0DA, hi)
			0x0DC => write16(write16(rgs, 0x0DC, lo)?, 0x0DE, hi)
			offset if offset >= 0x0E0 and offset <= 0x0FC and offset.mod_by(4) == 0 => Ok(rgs)
			0x100 => write16(write16(rgs, 0x100, lo)?, 0x102, hi)
			0x104 => write16(write16(rgs, 0x104, lo)?, 0x106, hi)
			0x108 => write16(write16(rgs, 0x108, lo)?, 0x10A, hi)
			0x10C => write16(write16(rgs, 0x10C, lo)?, 0x10E, hi)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}
}

get_ith_bit_u16_certain : U16, U8 -> Bool
get_ith_bit_u16_certain = |i, j| {
	U16.shr_wrap(U16.shl_wrap(i, 16 - j - 1), 15) == 1
}

get_seg_of_u16_certain : U16, U8, U8 -> U16
get_seg_of_u16_certain = |i, lsb, len| {
	tmp = 16 - len
	U16.shr_wrap(U16.shl_wrap(U16.shr_wrap(i, lsb), tmp), tmp)
}

replace_byte : U16, Bool, U8 -> U16
replace_byte = |old_val, isHi, incoming_val| {
	if isHi {
		incoming_val.to_u16().shl_wrap(8) + old_val.bitwise_and(0b0000_0000_1111_1111)
	} else {
		incoming_val.to_u16() + old_val.bitwise_and(0b1111_1111_0000_0000)
	}
}

timer_init : () -> TimerReg
timer_init = || {
	{
		reload: 0,
		counter: 0,
		control: 0,
	}
}

timer_write_control : TimerReg, U16 -> TimerReg
timer_write_control = |reg, val| {
	adjusted_val = val.bitwise_and(0b1100_0111)
	{
		..reg,
		control: adjusted_val,
		counter: if !get_ith_bit_u16_certain(reg.control, 7) and get_ith_bit_u16_certain(adjusted_val, 7) {
			reg.reload
		} else {
			reg.counter
		},
	}
}

dma_init : () -> DMAReg
dma_init = || {
	{
		sad_l: 0,
		sad_h: 0,
		dad_l: 0,
		dad_h: 0,
		cnt_l: 0,
		cnt_h: 0,
	}
}
