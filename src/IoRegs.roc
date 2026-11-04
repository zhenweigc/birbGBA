import DisplayRegs
import DmaRegs
import TimerRegs
import SystemRegs
import SoundRegs
import SerialRegs
import KeyRegs

ReadResult(val_type, rg_type) : {
	val : val_type,
	device_mask : val_type, # 1 for device val and 0 for open bus val
	reg : [Unchanged, Updated(rg_type)],
}

IoRegs := {
	display : DisplayRegs,
	sound : SoundRegs,
	dmas : DmaRegs,
	timers : TimerRegs,
	serials : SerialRegs,
	keys : KeyRegs,
	system : SystemRegs,
}.{
	init : () -> IoRegs
	init = || {
		{
			display: DisplayRegs.init(),
			sound: SoundRegs.init(),
			dmas: DmaRegs.init(),
			timers: TimerRegs.init(),
			serials: SerialRegs.init(),
			keys: KeyRegs.init(),
			system: SystemRegs.init(),
		}
	}

	read8 : IoRegs, U32 -> Try(ReadResult(U8, IoRegs), [UnsupportedIORegOffset(U32), OutOfBounds])
	read8 = |rgs, addr| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => Ok({ val: DisplayRegs.read8(rgs.display, addr)?, device_mask: 0xFF, reg: Unchanged })
			offset if offset >= 0x60 and offset < 0xB0 => Ok({ val: SoundRegs.read8(rgs.sound, addr)?, device_mask: 0xFF, reg: Unchanged })
			offset if offset >= 0x0B0 and offset < 0x100 => Ok({ val: DmaRegs.read8(rgs.dmas, addr)?, device_mask: 0xFF, reg: Unchanged })
			offset if offset >= 0x100 and offset < 0x110 => Ok({ val: TimerRegs.read8(rgs.timers, addr)?, device_mask: 0xFF, reg: Unchanged })
			# space between timer regs and serial
			offset if offset >= 0x110 and offset < 0x120 => Ok({ val: 0, device_mask: 0, reg: Unchanged })
			offset if offset >= 0x130 and offset < 0x134 => Ok({ val: KeyRegs.read8(rgs.keys, addr)?, device_mask: 0xFF, reg: Unchanged })
			offset if (offset >= 0x120 and offset < 0x130) or (offset >= 0x134 and offset < 0x200) => {
				intermediate = SerialRegs.read8(rgs.serials, addr)?
				Ok({
					val: intermediate.val,
					device_mask: 0xFF,
					reg: catch_read_side_effect(rgs, intermediate.reg),
				})
			}
			offset if offset >= 0x200 => Ok({ val: SystemRegs.read8(rgs.system, addr)?, device_mask: 0xFF, reg: Unchanged })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : IoRegs, U32 -> Try(ReadResult(U16, IoRegs), [UnsupportedIORegOffset(U32), OutOfBounds])
	read16 = |rgs, addr| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => Ok({ val: DisplayRegs.read16(rgs.display, addr)?, device_mask: 0xFFFF, reg: Unchanged })
			offset if offset >= 0x60 and offset < 0xB0 => Ok({ val: SoundRegs.read16(rgs.sound, addr)?, device_mask: 0xFFFF, reg: Unchanged })
			offset if offset >= 0xB0 and offset < 0x100 => Ok({ val: DmaRegs.read16(rgs.dmas, addr)?, device_mask: 0xFFFF, reg: Unchanged })
			offset if offset >= 0x100 and offset < 0x110 => Ok({ val: TimerRegs.read16(rgs.timers, addr)?, device_mask: 0xFFFF, reg: Unchanged })
			offset if offset >= 0x110 and offset < 0x120 => Ok({ val: 0, device_mask: 0, reg: Unchanged })
			offset if (offset >= 0x120 and offset < 0x130) or (offset >= 0x134 and offset < 0x200) => {
				intermediate = SerialRegs.read16(rgs.serials, addr)?
				Ok({
					val: intermediate.val,
					device_mask: 0xFFFF,
					reg: catch_read_side_effect(rgs, intermediate.reg),
				})
			}
			offset if offset >= 0x130 and offset < 0x134 => Ok({ val: KeyRegs.read16(rgs.keys, addr)?, device_mask: 0xFFFF, reg: Unchanged })
			offset if offset >= 0x200 => Ok({ val: SystemRegs.read16(rgs.system, addr)?, device_mask: 0xFFFF, reg: Unchanged })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : IoRegs, U32 -> Try(ReadResult(U32, IoRegs), [UnsupportedIORegOffset(U32), OutOfBounds])
	read32 = |rgs, addr| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => Ok({ val: DisplayRegs.read32(rgs.display, addr)?, device_mask: 0xFFFFFFFF, reg: Unchanged })
			offset if offset >= 0x60 and offset < 0xB0 => Ok({ val: SoundRegs.read32(rgs.sound, addr)?, device_mask: 0xFFFFFFFF, reg: Unchanged })
			offset if offset >= 0xB0 and offset < 0x100 => Ok({ val: DmaRegs.read32(rgs.dmas, addr)?, device_mask: 0xFFFFFFFF, reg: Unchanged })
			offset if offset >= 0x100 and offset < 0x110 => Ok({ val: TimerRegs.read32(rgs.timers, addr)?, device_mask: 0xFFFFFFFF, reg: Unchanged })
			offset if offset >= 0x110 and offset < 0x120 => Ok({ val: 0, device_mask: 0, reg: Unchanged })
			offset if offset >= 0x130 and offset < 0x134 => Ok({ val: KeyRegs.read32(rgs.keys, addr)?, device_mask: 0xFFFFFFFF, reg: Unchanged })
			offset if (offset >= 0x120 and offset < 0x130) or (offset >= 0x134 and offset < 0x200) => {
				intermediate = SerialRegs.read32(rgs.serials, addr)?
				Ok({
					val: intermediate.val,
					device_mask: 0xFFFFFFFF,
					reg: catch_read_side_effect(rgs, intermediate.reg),
				})
			}
			offset if offset >= 0x200 => Ok({ val: SystemRegs.read32(rgs.system, addr)?, device_mask: 0xFFFFFFFF, reg: Unchanged })
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : IoRegs, U32, U8 -> Try(IoRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write8 = |rgs, addr, val| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => {
				Ok({ ..rgs, display: DisplayRegs.write8(rgs.display, addr, val)? })
			}
			offset if offset >= 0x60 and offset < 0xB0 => {
				Ok({ ..rgs, sound: SoundRegs.write8(rgs.sound, addr, val)? })
			}
			offset if offset >= 0xB0 and offset < 0x100 => {
				Ok({ ..rgs, dmas: DmaRegs.write8(rgs.dmas, addr, val)? })
			}
			offset if offset >= 0x100 and offset < 0x120 => {
				Ok({ ..rgs, timers: TimerRegs.write8(rgs.timers, addr, val)? })
			}
			offset if offset >= 0x120 and offset < 0x130 => {
				Ok({ ..rgs, serials: SerialRegs.write8(rgs.serials, addr, val)? })
			}
			offset if offset >= 0x130 and offset < 0x134 => {
				updated = { ..rgs, keys: KeyRegs.write8(rgs.keys, addr, val)? }
				if (offset == 0x132 or offset == 0x133) Ok(check_key_irq(updated)) else Ok(updated)
			}
			offset if offset >= 0x134 and offset < 0x200 => {
				Ok({ ..rgs, serials: SerialRegs.write8(rgs.serials, addr, val)? })
			}
			offset if offset >= 0x200 => {
				Ok({ ..rgs, system: SystemRegs.write8(rgs.system, addr, val)? })
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : IoRegs, U32, U16 -> Try(IoRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write16 = |rgs, addr, val| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => {
				Ok({ ..rgs, display: DisplayRegs.write16(rgs.display, addr, val)? })
			}
			offset if offset >= 0x60 and offset < 0xB0 => {
				Ok({ ..rgs, sound: SoundRegs.write16(rgs.sound, addr, val)? })
			}
			offset if offset >= 0xB0 and offset < 0x100 => {
				Ok({ ..rgs, dmas: DmaRegs.write16(rgs.dmas, addr, val)? })
			}
			offset if offset >= 0x100 and offset < 0x120 => {
				Ok({ ..rgs, timers: TimerRegs.write16(rgs.timers, addr, val)? })
			}
			offset if offset >= 0x120 and offset < 0x130 => {
				Ok({ ..rgs, serials: SerialRegs.write16(rgs.serials, addr, val)? })
			}
			offset if offset >= 0x130 and offset < 0x134 => {
				updated = { ..rgs, keys: KeyRegs.write16(rgs.keys, addr, val)? }
				if (offset == 0x132) Ok(check_key_irq(updated)) else Ok(updated)
			}
			offset if offset >= 0x134 and offset < 0x200 => {
				Ok({ ..rgs, serials: SerialRegs.write16(rgs.serials, addr, val)? })
			}
			offset if offset >= 0x200 => {
				Ok({ ..rgs, system: SystemRegs.write16(rgs.system, addr, val)? })
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : IoRegs, U32, U32 -> Try(IoRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write32 = |rgs, addr, val| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => {
				Ok({ ..rgs, display: DisplayRegs.write32(rgs.display, addr, val)? })
			}
			offset if offset >= 0x60 and offset < 0xB0 => {
				Ok({ ..rgs, sound: SoundRegs.write32(rgs.sound, addr, val)? })
			}
			offset if offset >= 0xB0 and offset < 0x100 => {
				Ok({ ..rgs, dmas: DmaRegs.write32(rgs.dmas, addr, val)? })
			}
			offset if offset >= 0x100 and offset < 0x120 => {
				Ok({ ..rgs, timers: TimerRegs.write32(rgs.timers, addr, val)? })
			}
			offset if offset >= 0x120 and offset < 0x130 => {
				Ok({ ..rgs, serials: SerialRegs.write32(rgs.serials, addr, val)? })
			}
			offset if offset >= 0x130 and offset < 0x134 => {
				updated = { ..rgs, keys: KeyRegs.write32(rgs.keys, addr, val)? }
				if (offset == 0x130) Ok(check_key_irq(updated)) else Ok(updated)
			}
			offset if offset >= 0x134 and offset < 0x200 => {
				Ok({ ..rgs, serials: SerialRegs.write32(rgs.serials, addr, val)? })
			}
			offset if offset >= 0x200 => {
				Ok({ ..rgs, system: SystemRegs.write32(rgs.system, addr, val)? })
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	set_pressed : IoRegs, U16 -> IoRegs
	set_pressed = |rgs, pressed| {
		new_keys = KeyRegs.set_pressed(rgs.keys, pressed)
		updated = { ..rgs, keys: new_keys }
		check_key_irq(updated)
	}
}

catch_read_side_effect : IoRegs, [Unchanged, Updated(SerialRegs)] -> [Unchanged, Updated(IoRegs)]
catch_read_side_effect = |rgs, reg| {
	match reg {
		Updated(new_reg) => Updated({ ..rgs, serials: new_reg })
		_ => Unchanged
	}
}

check_key_irq : IoRegs -> IoRegs
check_key_irq = |rgs| {
	(new_keys, should_request) = KeyRegs.poll_irq(rgs.keys)
	updated = { ..rgs, keys: new_keys }
	if (should_request) { ..updated, system: SystemRegs.hardware_request_interrupts(rgs.system, 0x1000) } else updated
}
