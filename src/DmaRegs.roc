import Bits

DMAReg : {
	sad_l : U16,
	sad_h : U16,
	dad_l : U16,
	dad_h : U16,
	cnt_l : U16,
	cnt_h : U16,
	# Internal DMA progress info
	# separate from CPU-written stuff above
	source_addr : U32,
	dest_addr : U32,
	remaining : U32,
	phase : [Disabled, Waiting, Pending],
	ready_at : [None, At(U64)],
	data_latch : U32,
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

	schedule_pending : DmaRegs, U64 -> DmaRegs
	schedule_pending = |rgs, given_now| {
		# turns out there are CYCLE diff between pending initiated
		# and acutal IOing for DMA
		process = |reg| {
			if reg.phase == Pending and reg.ready_at == None {
				{ ..reg, ready_at: At(given_now + 2) }
			} else {
				reg
			}
		}
		{
			dma0: process(rgs.dma0),
			dma1: process(rgs.dma1),
			dma2: process(rgs.dma2),
			dma3: process(rgs.dma3),
		}
	}

	get_reg_ready_to_io : DmaRegs, U64 -> [None, Transfer(U8, DMAReg, [W16, W32])]
	get_reg_ready_to_io = |rgs, given_now| {
		var $num = 0.U8
		for reg in [rgs.dma0, rgs.dma1, rgs.dma2, rgs.dma3] {
			if reg.phase == Pending and reg.ready_at != None {
				match reg.ready_at {
					At(t) if t <= given_now => {
						return Transfer($num, reg, if (Bits.get_ith_bit_u16_certain(reg.cnt_h, 10)) W32 else W16)
					}
					_ => {
						$num = $num + 1
					}
				}
			} else {
				$num = $num + 1
			}
		}
		None
	}

	next_ready_at : DmaRegs -> [None, At(U64)]
	next_ready_at = |rgs| {
		var $res = None
		for reg in [rgs.dma0, rgs.dma1, rgs.dma2, rgs.dma3] {
			match reg.ready_at {
				At(t) if reg.phase == Pending => {
					$res = match $res {
						None => At(t)
						At(x) => if (t < x) At(t) else At(x)
					}
				}
				_ => {}
			}
		}
		$res
	}

	complete_unit : DmaRegs,
	U8 -> Try(
		(DmaRegs, U16),
		[
			DMAInvalidSelection,
			DMAImpossibleStepMode,
			DMARemainingAlreadyZero,
			DMANotInPending,
			DMAWrongMode,
		],
	)
	complete_unit = |rgs, selection| {
		put_back : DMAReg -> DmaRegs
		put_back = |reg_to_put| {
			match selection {
				0 => { ..rgs, dma0: reg_to_put }
				1 => { ..rgs, dma1: reg_to_put }
				2 => { ..rgs, dma2: reg_to_put }
				_ => { ..rgs, dma3: reg_to_put }
			}
		}
		reg = match selection {
			0 => rgs.dma0
			1 => rgs.dma1
			2 => rgs.dma2
			3 => rgs.dma3
			_ => return Err(DMAInvalidSelection)
		}
		validate_transfer(reg)?
		width = if (Bits.get_ith_bit_u16_certain(reg.cnt_h, 10)) 4 else 2.U32
		new_source = match Bits.get_seg_of_u16_certain(reg.cnt_h, 7, 2) {
			0 => reg.source_addr.plus_wrap(width)
			1 => reg.source_addr.minus_wrap(width)
			2 => reg.source_addr
			_ => return Err(DMAImpossibleStepMode)
		}
		new_dest = match Bits.get_seg_of_u16_certain(reg.cnt_h, 5, 2) {
			0 => reg.dest_addr.plus_wrap(width)
			1 => reg.dest_addr.minus_wrap(width)
			2 => reg.dest_addr
			_ => reg.dest_addr.plus_wrap(width)
		}
		new_remaining = if (reg.remaining > 0) reg.remaining - 1 else return Err(DMARemainingAlreadyZero)
		if new_remaining > 0 {
			new_reg = {
				..reg,
				source_addr: new_source,
				dest_addr: new_dest,
				remaining: new_remaining,
			}
			Ok((put_back(new_reg), 0))
		} else {
			new_reg = {
				..reg,
				source_addr: new_source,
				dest_addr: new_dest,
				remaining: new_remaining,
				cnt_h: reg.cnt_h.bitwise_and(0b111_1111_1111_1111),
				phase: Disabled,
				ready_at: None,
			}
			Ok((
				put_back(new_reg),
				# Return a new mask will be applied to Interrupt Request Flags(IF)
				if (Bits.get_ith_bit_u16_certain(new_reg.cnt_h, 14)) (1.U16).shl_wrap(8 + selection) else 0,
			))
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
			0x0BA => Ok({ ..rgs, dma0: write_cnt_h(rgs.dma0, val.bitwise_and(0xF7E0), 0x4000) })
			0x0BC => Ok({ ..rgs, dma1: { ..rgs.dma1, sad_l: val.bitwise_and(0xFFFE) } })
			0x0BE => Ok({ ..rgs, dma1: { ..rgs.dma1, sad_h: val.bitwise_and(0x0FFF) } })
			0x0C0 => Ok({ ..rgs, dma1: { ..rgs.dma1, dad_l: val.bitwise_and(0xFFFE) } })
			0x0C2 => Ok({ ..rgs, dma1: { ..rgs.dma1, dad_h: val.bitwise_and(0x07FF) } })
			0x0C4 => Ok({ ..rgs, dma1: { ..rgs.dma1, cnt_l: val.bitwise_and(0x3FFF) } })
			0x0C6 => Ok({ ..rgs, dma1: write_cnt_h(rgs.dma1, val.bitwise_and(0xF7E0), 0x4000) })
			0x0C8 => Ok({ ..rgs, dma2: { ..rgs.dma2, sad_l: val.bitwise_and(0xFFFE) } })
			0x0CA => Ok({ ..rgs, dma2: { ..rgs.dma2, sad_h: val.bitwise_and(0x0FFF) } })
			0x0CC => Ok({ ..rgs, dma2: { ..rgs.dma2, dad_l: val.bitwise_and(0xFFFE) } })
			0x0CE => Ok({ ..rgs, dma2: { ..rgs.dma2, dad_h: val.bitwise_and(0x07FF) } })
			0x0D0 => Ok({ ..rgs, dma2: { ..rgs.dma2, cnt_l: val.bitwise_and(0x3FFF) } })
			0x0D2 => Ok({ ..rgs, dma2: write_cnt_h(rgs.dma2, val.bitwise_and(0xF7E0), 0x4000) })
			0x0D4 => Ok({ ..rgs, dma3: { ..rgs.dma3, sad_l: val.bitwise_and(0xFFFE) } })
			0x0D6 => Ok({ ..rgs, dma3: { ..rgs.dma3, sad_h: val.bitwise_and(0x0FFF) } })
			0x0D8 => Ok({ ..rgs, dma3: { ..rgs.dma3, dad_l: val.bitwise_and(0xFFFE) } })
			0x0DA => Ok({ ..rgs, dma3: { ..rgs.dma3, dad_h: val.bitwise_and(0x0FFF) } })
			0x0DC => Ok({ ..rgs, dma3: { ..rgs.dma3, cnt_l: val } })
			0x0DE => Ok({ ..rgs, dma3: write_cnt_h(rgs.dma3, val.bitwise_and(0xFFE0), 0x10000) })
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

	validate_transfer : DMAReg -> Try(
		{},
		[
			DMANotInPending,
			DMAWrongMode,
			DMAImpossibleStepMode,
			DMARemainingAlreadyZero,
		],
	)
	validate_transfer = |reg| {
		if reg.phase != Pending {
			Err(DMANotInPending)
		} else if Bits.get_seg_of_u16_certain(reg.cnt_h, 11, 3) != 0 {
			# Not Immediate / Game Pak DRQ not here yet
			Err(DMAWrongMode)
		} else if reg.remaining == 0 {
			Err(DMARemainingAlreadyZero)
		} else if Bits.get_seg_of_u16_certain(reg.cnt_h, 7, 2) > 2 {
			Err(DMAImpossibleStepMode)
		} else {
			Ok({})
		}
	}

	set_data_latch : DmaRegs, U8, U32 -> Try(DmaRegs, [DMAInvalidSelection])
	set_data_latch = |rgs, selection, val| {
		reg = match selection {
			0 => rgs.dma0
			1 => rgs.dma1
			2 => rgs.dma2
			3 => rgs.dma3
			_ => return Err(DMAInvalidSelection)
		}
		new_reg = { ..reg, data_latch: val }
		match selection {
			0 => Ok({ ..rgs, dma0: new_reg })
			1 => Ok({ ..rgs, dma1: new_reg })
			2 => Ok({ ..rgs, dma2: new_reg })
			_ => Ok({ ..rgs, dma3: new_reg })
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
		source_addr: 0,
		dest_addr: 0,
		remaining: 0,
		phase: Disabled,
		ready_at: None,
		data_latch: 0,
	}
}

write_cnt_h : DMAReg, U16, U32 -> DMAReg
write_cnt_h = |reg, new_cnt_h, zero_count| {
	# a value of zero is treated as max length, 0x4000/0x10000h
	combine_u16 : U16, U16 -> U32
	combine_u16 = |lo, hi| lo.to_u32() + hi.to_u32().shl_wrap(16)
	b1 = if (Bits.get_ith_bit_u16_certain(reg.cnt_h, 15)) 1.U8 else 0
	b0 = if (Bits.get_ith_bit_u16_certain(new_cnt_h, 15)) 1.U8 else 0
	combined = b1.shl_wrap(1) + b0
	match combined {
		0 | 2 => { ..reg, cnt_h: new_cnt_h, phase: Disabled, ready_at: None }
		1 => {
			..reg,
			cnt_h: new_cnt_h,
			source_addr: combine_u16(reg.sad_l, reg.sad_h),
			dest_addr: combine_u16(reg.dad_l, reg.dad_h),
			remaining: if (reg.cnt_l != 0) reg.cnt_l.to_u32() else zero_count,
			phase: if (new_cnt_h.bitwise_and(0b11_0000_0000_0000) == 0) Pending else Waiting,
			ready_at: None,
		}
		_ => { ..reg, cnt_h: new_cnt_h }
	}
}
