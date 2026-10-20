import Bits
DMAReg : {
	sad_l : U16,
	sad_h : U16,
	dad_l : U16,
	dad_h : U16,
	cnt_l : U16,
	cnt_h : U16,
}

DmaRegs :: {
	dma0 : DMAReg,
	dma1 : DMAReg,
	dma2 : DMAReg,
	dma3 : DMAReg,
}.{
	init : () -> DmaRegs
	init = || {
		{
			dma0: dma_init(),
			dma1: dma_init(),
			dma2: dma_init(),
			dma3: dma_init(),
		}
	}

	read8 : DmaRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x0B8 | 0x0B9 | 0x0C4 | 0x0C5 | 0x0D0 | 0x0D1 | 0x0DC | 0x0DD => Ok(0)
			0x0BA => Ok(rgs.dma0.cnt_h.to_u8_wrap())
			0x0BB => Ok(rgs.dma0.cnt_h.shr_wrap(8).to_u8_wrap())
			0x0C6 => Ok(rgs.dma1.cnt_h.to_u8_wrap())
			0x0C7 => Ok(rgs.dma1.cnt_h.shr_wrap(8).to_u8_wrap())
			0x0D2 => Ok(rgs.dma2.cnt_h.to_u8_wrap())
			0x0D3 => Ok(rgs.dma2.cnt_h.shr_wrap(8).to_u8_wrap())
			0x0DE => Ok(rgs.dma3.cnt_h.to_u8_wrap())
			0x0DF => Ok(rgs.dma3.cnt_h.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : DmaRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x0B8 | 0x0C4 | 0x0D0 | 0x0DC => Ok(0)
			0x0BA => Ok(rgs.dma0.cnt_h)
			0x0C6 => Ok(rgs.dma1.cnt_h)
			0x0D2 => Ok(rgs.dma2.cnt_h)
			0x0DE => Ok(rgs.dma3.cnt_h)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : DmaRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x0B8 => Ok(rgs.dma0.cnt_h.to_u32().shl_wrap(16))
			0x0C4 => Ok(rgs.dma1.cnt_h.to_u32().shl_wrap(16))
			0x0D0 => Ok(rgs.dma2.cnt_h.to_u32().shl_wrap(16))
			0x0DC => Ok(rgs.dma3.cnt_h.to_u32().shl_wrap(16))
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : DmaRegs, U32, U8 -> Try(DmaRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x0B0 | 0x0B1 => {
				old_val = rgs.dma0.sad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xB0, adjusted_val)
			}
			0x0B2 | 0x0B3 => {
				old_val = rgs.dma0.sad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xB2, adjusted_val)
			}
			0x0B4 | 0x0B5 => {
				old_val = rgs.dma0.dad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xB4, adjusted_val)
			}
			0x0B6 | 0x0B7 => {
				old_val = rgs.dma0.dad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xB6, adjusted_val)
			}
			0x0B8 | 0x0B9 => {
				old_val = rgs.dma0.cnt_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xB8, adjusted_val)
			}
			0x0BA | 0x0BB => {
				old_val = rgs.dma0.cnt_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xBA, adjusted_val)
			}
			0x0BC | 0x0BD => {
				old_val = rgs.dma1.sad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xBC, adjusted_val)
			}
			0x0BE | 0x0BF => {
				old_val = rgs.dma1.sad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xBE, adjusted_val)
			}
			0x0C0 | 0x0C1 => {
				old_val = rgs.dma1.dad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xC0, adjusted_val)
			}
			0x0C2 | 0x0C3 => {
				old_val = rgs.dma1.dad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xC2, adjusted_val)
			}
			0x0C4 | 0x0C5 => {
				old_val = rgs.dma1.cnt_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xC4, adjusted_val)
			}
			0x0C6 | 0x0C7 => {
				old_val = rgs.dma1.cnt_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xC6, adjusted_val)
			}
			0x0C8 | 0x0C9 => {
				old_val = rgs.dma2.sad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xC8, adjusted_val)
			}
			0x0CA | 0x0CB => {
				old_val = rgs.dma2.sad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xCA, adjusted_val)
			}
			0x0CC | 0x0CD => {
				old_val = rgs.dma2.dad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xCC, adjusted_val)
			}
			0x0CE | 0x0CF => {
				old_val = rgs.dma2.dad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xCE, adjusted_val)
			}
			0x0D0 | 0x0D1 => {
				old_val = rgs.dma2.cnt_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xD0, adjusted_val)
			}
			0x0D2 | 0x0D3 => {
				old_val = rgs.dma2.cnt_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xD2, adjusted_val)
			}
			0x0D4 | 0x0D5 => {
				old_val = rgs.dma3.sad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xD4, adjusted_val)
			}
			0x0D6 | 0x0D7 => {
				old_val = rgs.dma3.sad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xD6, adjusted_val)
			}
			0x0D8 | 0x0D9 => {
				old_val = rgs.dma3.dad_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xD8, adjusted_val)
			}
			0x0DA | 0x0DB => {
				old_val = rgs.dma3.dad_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xDA, adjusted_val)
			}
			0x0DC | 0x0DD => {
				old_val = rgs.dma3.cnt_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xDC, adjusted_val)
			}
			0x0DE | 0x0DF => {
				old_val = rgs.dma3.cnt_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0xDE, adjusted_val)
			}
			offset if offset >= 0x0E0 and offset <= 0x0FF => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : DmaRegs, U32, U16 -> Try(DmaRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
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
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : DmaRegs, U32, U32 -> Try(DmaRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
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
			_ => Err(UnsupportedIORegOffset(addr))
		}
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
