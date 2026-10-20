import Bits

Mode : [GP, JOY_BUS, EightBit, ThirtyTwoBit, SixteenBit, UART]

ReadResult(val_type, rg_type) : {
	val : val_type,
	reg : [Unchanged, Updated(rg_type)],
}

SerialRegs :: {
	siodata32_l : U16,
	siodata32_h : U16,
	siomulti2 : U16,
	siomulti3 : U16,
	siodata8 : U16,
	siocnt : U16,
	rcnt : U16,
	joycnt : U16,
	joyrecv_l : U16,
	joyrecv_h : U16,
	joytrans_l : U16,
	joytrans_h : U16,
	joystat : U16,
}.{
	init : () -> SerialRegs
	init = || {
		{
			siodata32_l: 0,
			siodata32_h: 0,
			siomulti2: 0,
			siomulti3: 0,
			siodata8: 0,
			siocnt: 0,
			rcnt: 0,
			joycnt: 0,
			joyrecv_l: 0,
			joyrecv_h: 0,
			joytrans_l: 0,
			joytrans_h: 0,
			joystat: 0,
		}
	}

	read8 : SerialRegs, U32 -> Try(ReadResult(U8, SerialRegs), [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x120 => Ok({ val: rgs.siodata32_l.to_u8_wrap(), reg: Unchanged })
			0x121 => Ok({ val: rgs.siodata32_l.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x122 => Ok({ val: rgs.siodata32_h.to_u8_wrap(), reg: Unchanged })
			0x123 => Ok({ val: rgs.siodata32_h.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x124 => Ok({ val: rgs.siomulti2.to_u8_wrap(), reg: Unchanged })
			0x125 => Ok({ val: rgs.siomulti2.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x126 => Ok({ val: rgs.siomulti3.to_u8_wrap(), reg: Unchanged })
			0x127 => Ok({ val: rgs.siomulti3.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x128 => Ok({ val: rgs.siocnt.to_u8_wrap(), reg: Unchanged })
			0x129 => Ok({ val: rgs.siocnt.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x12A => Ok({ val: rgs.siodata8.to_u8_wrap(), reg: Unchanged })
			0x12B => Ok({ val: rgs.siodata8.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x134 => Ok({ val: rgs.rcnt.to_u8_wrap(), reg: Unchanged })
			0x135 => Ok({ val: rgs.rcnt.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x136 | 0x137 => Ok({ val: 0, reg: Unchanged })
			0x140 => Ok({ val: rgs.joycnt.to_u8_wrap(), reg: Unchanged })
			0x141 => Ok({ val: rgs.joycnt.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x142 | 0x143 => Ok({ val: 0, reg: Unchanged })
			0x150 | 0x151 => {
				new_rgs = { ..rgs, joystat: rgs.joystat.bitwise_and(0b1111_1111_1111_1101) }
				sft = (addr.mod_by(2) * 8).to_u8_wrap()
				Ok({ val: rgs.joyrecv_l.shr_wrap(sft).to_u8_wrap(), reg: Updated(new_rgs) })
			}
			0x152 | 0x153 => {
				new_rgs = { ..rgs, joystat: rgs.joystat.bitwise_and(0b1111_1111_1111_1101) }
				sft = (addr.mod_by(2) * 8).to_u8_wrap()
				Ok({ val: rgs.joyrecv_h.shr_wrap(sft).to_u8_wrap(), reg: Updated(new_rgs) })
			}
			0x154 => Ok({ val: rgs.joytrans_l.to_u8_wrap(), reg: Unchanged })
			0x155 => Ok({ val: rgs.joytrans_l.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x156 => Ok({ val: rgs.joytrans_h.to_u8_wrap(), reg: Unchanged })
			0x157 => Ok({ val: rgs.joytrans_h.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x158 => Ok({ val: rgs.joystat.to_u8_wrap(), reg: Unchanged })
			0x159 => Ok({ val: rgs.joystat.shr_wrap(8).to_u8_wrap(), reg: Unchanged })
			0x15A | 0x15B => Ok({ val: 0, reg: Unchanged })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : SerialRegs, U32 -> Try(ReadResult(U16, SerialRegs), [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x120 => Ok({ val: rgs.siodata32_l, reg: Unchanged })
			0x122 => Ok({ val: rgs.siodata32_h, reg: Unchanged })
			0x124 => Ok({ val: rgs.siomulti2, reg: Unchanged })
			0x126 => Ok({ val: rgs.siomulti3, reg: Unchanged })
			0x128 => Ok({ val: rgs.siocnt, reg: Unchanged })
			0x12A => Ok({ val: rgs.siodata8, reg: Unchanged })
			0x134 => Ok({ val: rgs.rcnt, reg: Unchanged })
			0x136 => Ok({ val: 0, reg: Unchanged })
			0x140 => Ok({ val: rgs.joycnt, reg: Unchanged })
			0x142 => Ok({ val: 0, reg: Unchanged })
			0x150 => {
				new_rgs = { ..rgs, joystat: rgs.joystat.bitwise_and(0b1111_1111_1111_1101) }
				Ok({ val: rgs.joyrecv_l, reg: Updated(new_rgs) })
			}
			0x152 => {
				new_rgs = { ..rgs, joystat: rgs.joystat.bitwise_and(0b1111_1111_1111_1101) }
				Ok({ val: rgs.joyrecv_h, reg: Updated(new_rgs) })
			}
			0x154 => Ok({ val: rgs.joytrans_l, reg: Unchanged })
			0x156 => Ok({ val: rgs.joytrans_h, reg: Unchanged })
			0x158 => Ok({ val: rgs.joystat, reg: Unchanged })
			0x15A => Ok({ val: 0, reg: Unchanged })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : SerialRegs, U32 -> Try(ReadResult(U32, SerialRegs), [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x120 | 0x124 | 0x128 | 0x134 | 0x140 | 0x150 | 0x154 | 0x158 => {
				firstRead = read16(rgs, addr)?
				low = firstRead.val.to_u32()
				secondRead = read16(
					match firstRead.reg {
						Unchanged => rgs
						Updated(x) => x
					},
					addr.plus_wrap(2),
				)?
				Ok({
					val: low + secondRead.val.to_u32().shl_wrap(16),
					reg: match secondRead.reg {
						Unchanged => firstRead.reg
						x => x
					},
				})
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
			0x140 => {
				write16(rgs, 0x140, val.to_u16())
			}
			0x141 => Ok(rgs)
			offset if offset >= 0x142 and offset < 0x150 => Ok(rgs)
			offset if offset >= 0x150 and offset < 0x154 => Ok(rgs)
			0x154 | 0x155 => {
				old_val = rgs.joytrans_l
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x154, adjusted_val)
			}
			0x156 | 0x157 => {
				old_val = rgs.joytrans_h
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x156, adjusted_val)
			}
			0x158 | 0x159 => {
				old_val = rgs.joystat
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x158, adjusted_val)
			}
			offset if offset >= 0x15A and offset < 0x200 => Ok(rgs)
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
			0x140 => {
				mode = mode_decode(rgs.rcnt, rgs.siocnt)
				if mode == GP {
					Ok(rgs)
				} else {
					lower_tri_bits = Bits.get_seg_of_u16_certain(rgs.joycnt, 0, 3)
					updated_tri_bits = lower_tri_bits.bitwise_and(Bits.get_seg_of_u16_certain(val, 0, 3).bitwise_not())
					new_val = val.bitwise_and(0b100_0000) + updated_tri_bits
					Ok({ ..rgs, joycnt: new_val })
				}
			}
			offset if offset >= 0x142 and offset < 0x150 => Ok(rgs)
			0x150 => Ok(rgs)
			0x152 => Ok(rgs)
			0x154 => {
				mode = mode_decode(rgs.rcnt, rgs.siocnt)
				joystate_old = rgs.joystat
				Ok({
					..rgs,
					joystat: joystate_old.bitwise_or(0b1000),
					joytrans_l: if mode != JOY_BUS {
						rgs.joytrans_l
					} else {
						val
					},
				})
			}
			0x156 => {
				mode = mode_decode(rgs.rcnt, rgs.siocnt)
				joystate_old = rgs.joystat
				Ok({
					..rgs,
					joystat: joystate_old.bitwise_or(0b1000),
					joytrans_h: if mode != JOY_BUS {
						rgs.joytrans_h
					} else {
						val
					},
				})
			}
			0x158 => {
				mode = mode_decode(rgs.rcnt, rgs.siocnt)
				if mode != JOY_BUS {
					Ok(rgs)
				} else {
					old_val = rgs.joystat.bitwise_and(0b1111_1111_1100_1111)
					new_val = val.bitwise_and(0b11_0000)
					Ok({ ..rgs, joystat: old_val.bitwise_or(new_val) })
				}
			}
			offset if offset >= 0x15A and offset < 0x200 => Ok(rgs)
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
			0x140 => write16(write16(rgs, 0x140, lo)?, 0x142, 0)
			offset if offset >= 0x142 and offset < 0x150 => Ok(rgs)
			0x150 => write16(write16(rgs, 0x150, 0)?, 0x152, 0)
			0x154 => write16(write16(rgs, 0x154, lo)?, 0x156, hi)
			0x158 => write16(write16(rgs, 0x158, lo)?, 0x15A, 0)
			offset if offset >= 0x15A and offset < 0x200 => Ok(rgs)
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
