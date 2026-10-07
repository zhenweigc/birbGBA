import Bits
TimerReg : {
	reload : U16,
	counter : U16,
	control : U16,
}

TimerRegs :: {
	timer0 : TimerReg,
	timer1 : TimerReg,
	timer2 : TimerReg,
	timer3 : TimerReg,
}.{
	init : () -> TimerRegs
	init = || {
		{
			timer0: timer_init(),
			timer1: timer_init(),
			timer2: timer_init(),
			timer3: timer_init(),
		}
	}

	read8 : TimerRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
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

	read16 : TimerRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
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

	read32 : TimerRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x100 | 0x104 | 0x108 | 0x10C => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : TimerRegs, U32, U8 -> Try(TimerRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x100 | 0x101 => {
				old_val = rgs.timer0.reload
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x100, adjusted_val)
			}
			0x102 | 0x103 => {
				old_val = rgs.timer0.control
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x102, adjusted_val)
			}
			0x104 | 0x105 => {
				old_val = rgs.timer1.reload
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x104, adjusted_val)
			}
			0x106 | 0x107 => {
				old_val = rgs.timer1.control
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x106, adjusted_val)
			}
			0x108 | 0x109 => {
				old_val = rgs.timer2.reload
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x108, adjusted_val)
			}
			0x10A | 0x10B => {
				old_val = rgs.timer2.control
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10A, adjusted_val)
			}
			0x10C | 0x10D => {
				old_val = rgs.timer3.reload
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10C, adjusted_val)
			}
			0x10E | 0x10F => {
				old_val = rgs.timer3.control
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10E, adjusted_val)
			}
			offset if offset >= 0x110 and offset <= 0x11F => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : TimerRegs, U32, U16 -> Try(TimerRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x100 => Ok({ ..rgs, timer0: { ..rgs.timer0, reload: val } })
			0x102 => Ok({ ..rgs, timer0: timer_write_control(rgs.timer0, val) })
			0x104 => Ok({ ..rgs, timer1: { ..rgs.timer1, reload: val } })
			0x106 => Ok({ ..rgs, timer1: timer_write_control(rgs.timer1, val) })
			0x108 => Ok({ ..rgs, timer2: { ..rgs.timer2, reload: val } })
			0x10A => Ok({ ..rgs, timer2: timer_write_control(rgs.timer2, val) })
			0x10C => Ok({ ..rgs, timer3: { ..rgs.timer3, reload: val } })
			0x10E => Ok({ ..rgs, timer3: timer_write_control(rgs.timer3, val) })
			offset if offset >= 0x110 and offset <= 0x11E => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : TimerRegs, U32, U32 -> Try(TimerRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x100 => write16(write16(rgs, 0x100, lo)?, 0x102, hi)
			0x104 => write16(write16(rgs, 0x104, lo)?, 0x106, hi)
			0x108 => write16(write16(rgs, 0x108, lo)?, 0x10A, hi)
			0x10C => write16(write16(rgs, 0x10C, lo)?, 0x10E, hi)
			0x110 | 0x114 | 0x118 | 0x11C => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
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
		counter: if !Bits.get_ith_bit_u16_certain(reg.control, 7)
			and Bits.get_ith_bit_u16_certain(adjusted_val, 7) {
			reg.reload
		} else {
			reg.counter
		},
	}
}
