import Bits

SystemRegs :: {
	interrupt_enables : U16,
	pending_interrupts : U16,
	waitcnt : U16,
	ime : U16,
	postflg : U8,
	haltcnt : [None(U8), Pending(U8)], # oh boy, I hate sideeffects
}.{
	init : () -> SystemRegs
	init = || {
		interrupt_enables: 0,
		pending_interrupts: 0,
		waitcnt: 0,
		ime: 0,
		postflg: 0,
		haltcnt: None(0),
	}

	read8 : SystemRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x200 => Ok(rgs.interrupt_enables.to_u8_wrap())
			0x201 => Ok(rgs.interrupt_enables.shr_wrap(8).to_u8_wrap())
			0x202 => Ok(rgs.pending_interrupts.to_u8_wrap())
			0x203 => Ok(rgs.pending_interrupts.shr_wrap(8).to_u8_wrap())
			0x204 => Ok(rgs.waitcnt.to_u8_wrap())
			0x205 => Ok(rgs.waitcnt.shr_wrap(8).to_u8_wrap())
			0x206 | 0x207 => Ok(0)
			0x208 => Ok(rgs.ime.to_u8_wrap())
			0x209 => Ok(rgs.ime.shr_wrap(8).to_u8_wrap())
			0x20A | 0x20B => Ok(0)
			0x300 => Ok(rgs.postflg)
			0x301 => Ok(0)
			0x302 | 0x303 => Ok(0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : SystemRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x200 => Ok(rgs.interrupt_enables)
			0x202 => Ok(rgs.pending_interrupts)
			0x204 => Ok(rgs.waitcnt)
			0x206 => Ok(0)
			0x208 => Ok(rgs.ime)
			0x20A => Ok(0)
			0x300 => {
				lo = read8(rgs, 0x300)?.to_u16()
				hi = read8(rgs, 0x301)?.to_u16().shl_wrap(8)
				Ok(lo + hi)
			}
			0x302 => Ok(0)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : SystemRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x200 | 0x204 | 0x208 | 0x300 => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : SystemRegs, U32, U8 -> Try(SystemRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x200 | 0x201 => {
				old_val = rgs.interrupt_enables
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x200, adjusted_val)
			}
			0x202 | 0x203 => {
				adjusted_val = Bits.replace_byte(0, isHi, val)
				write16(rgs, 0x202, adjusted_val)
			}
			0x204 | 0x205 => {
				old_val = rgs.waitcnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x204, adjusted_val)
			}
			0x206 | 0x207 => Ok(rgs)
			0x208 | 0x209 => {
				old_val = rgs.ime
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x208, adjusted_val)
			}
			offset if offset >= 0x20A and offset < 0x300 => Ok(rgs)
			0x300 => {
				# https://github.com/mgba-emu/mgba/issues/2309
				# Whenever come down to undocumented hardware behavior, shit will go lose.
				old_val = rgs.postflg
				Ok({
					..rgs,
					postflg: old_val.bitwise_or(val.bitwise_and(0b1)),
				})
			}
			0x301 => Ok({ ..rgs, haltcnt: Pending(val) })
			offset if offset >= 0x302 and offset < 0x800 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : SystemRegs, U32, U16 -> Try(SystemRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x200 => Ok({ ..rgs, interrupt_enables: val }) # mGBA somehow did not filter top 2 MSB, so I guess we will keep them as well.
			0x202 => {
				old_val = rgs.pending_interrupts
				new_val = old_val.bitwise_and(val.bitwise_not())
				Ok({ ..rgs, pending_interrupts: new_val })
			}
			0x204 => Ok({ ..rgs, waitcnt: val.bitwise_and(0x5FFF) })
			0x206 => Ok(rgs)
			0x208 => Ok({ ..rgs, ime: val.bitwise_and(0x1) })
			offset if offset >= 0x20A and offset < 0x300 => Ok(rgs)
			0x300 => {
				lo = val.to_u8_wrap()
				hi = val.shr_wrap(8).to_u8_wrap()
				Ok({
					..rgs,
					postflg: rgs.postflg.bitwise_or(lo.bitwise_and(0b1)),
					haltcnt: Pending(hi),
				})
			}
			offset if offset >= 0x302 and offset < 0x800 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : SystemRegs, U32, U32 -> Try(SystemRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x200 => write16(write16(rgs, 0x200, lo)?, 0x202, hi)
			0x204 => write16(write16(rgs, 0x204, lo)?, 0x206, 0)
			0x208 => write16(write16(rgs, 0x208, lo)?, 0x20A, 0)
			offset if offset >= 0x20A and offset < 0x300 => Ok(rgs)
			0x300 => write16(write16(rgs, 0x300, lo)?, 0x302, 0)
			offset if offset >= 0x302 and offset < 0x800 => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	process_haltcnt : SystemRegs -> (SystemRegs, [NoReq, Request(U8)])
	process_haltcnt = |rgs| {
		match rgs.haltcnt {
			None(_) => (rgs, NoReq)
			Pending(x) => ({ ..rgs, haltcnt: None(x) }, Request(x))
		}
	}

	hardware_request_interrupts : SystemRegs, U16 -> SystemRegs
	hardware_request_interrupts = |rgs, val| {
		# IF modification initiated via hardware
		new_val = Bits.get_seg_of_u16_certain(val, 0, 14)
		{ ..rgs, pending_interrupts: rgs.pending_interrupts.bitwise_or(new_val) }
	}

	enable_pending : SystemRegs -> U16
	enable_pending = |rgs| Bits.get_seg_of_u16_certain(rgs.interrupt_enables, 0, 14).bitwise_and(rgs.pending_interrupts)

	interrupt_req_fired : SystemRegs -> Bool
	interrupt_req_fired = |rgs| enable_pending(rgs) != 0 and Bits.get_ith_bit_u16_certain(rgs.ime, 0)
}
