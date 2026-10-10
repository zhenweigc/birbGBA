import DisplayRegs
import DmaRegs
import TimerRegs
import SystemRegs
import SoundRegs
import SerialRegs
import KeyRegs

IoRegs :: {
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

	read8 : IoRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => DisplayRegs.read8(rgs.display, addr)
			offset if offset >= 0x60 and offset < 0xB0 => SoundRegs.read8(rgs.sound, addr)
			offset if offset >= 0x0B0 and offset < 0x100 => DmaRegs.read8(rgs.dmas, addr)
			offset if offset >= 0x100 and offset < 0x120 => TimerRegs.read8(rgs.timers, addr)
			offset if offset >= 0x120 and offset < 0x130 => SerialRegs.read8(rgs.serials, addr)
			offset if offset >= 0x130 and offset < 0x134 => KeyRegs.read8(rgs.keys, addr)
			offset if offset >= 0x134 and offset < 0x200 => SerialRegs.read8(rgs.serials, addr)
			offset if offset >= 0x200 => SystemRegs.read8(rgs.system, addr)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : IoRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => DisplayRegs.read16(rgs.display, addr)
			offset if offset >= 0x60 and offset < 0xB0 => SoundRegs.read16(rgs.sound, addr)
			offset if offset >= 0xB0 and offset < 0x100 => DmaRegs.read16(rgs.dmas, addr)
			offset if offset >= 0x100 and offset < 0x120 => TimerRegs.read16(rgs.timers, addr)
			offset if offset >= 0x120 and offset < 0x130 => SerialRegs.read16(rgs.serials, addr)
			offset if offset >= 0x130 and offset < 0x134 => KeyRegs.read16(rgs.keys, addr)
			offset if offset >= 0x134 and offset < 0x200 => SerialRegs.read16(rgs.serials, addr)
			offset if offset >= 0x200 => SystemRegs.read16(rgs.system, addr)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : IoRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			offset if offset >= 0 and offset < 0x60 => DisplayRegs.read32(rgs.display, addr)
			offset if offset >= 0x60 and offset < 0xB0 => SoundRegs.read32(rgs.sound, addr)
			offset if offset >= 0xB0 and offset < 0x100 => DmaRegs.read32(rgs.dmas, addr)
			offset if offset >= 0x100 and offset < 0x120 => TimerRegs.read32(rgs.timers, addr)
			offset if offset >= 0x120 and offset < 0x130 => SerialRegs.read32(rgs.serials, addr)
			offset if offset >= 0x130 and offset < 0x134 => KeyRegs.read32(rgs.keys, addr)
			offset if offset >= 0x134 and offset < 0x200 => SerialRegs.read32(rgs.serials, addr)
			offset if offset >= 0x200 => SystemRegs.read32(rgs.system, addr)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : IoRegs, U32, U8 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
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
				Ok({ ..rgs, keys: KeyRegs.write8(rgs.keys, addr, val)? })
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

	write16 : IoRegs, U32, U16 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
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
				Ok({ ..rgs, keys: KeyRegs.write16(rgs.keys, addr, val)? })
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

	write32 : IoRegs, U32, U32 -> Try(IoRegs, [UnsupportedIORegOffset(U32)])
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
				Ok({ ..rgs, keys: KeyRegs.write32(rgs.keys, addr, val)? })
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
}
