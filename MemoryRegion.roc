MemoryRegion := [
	GamePakRAM,
	GamePakROMWS0,
	GamePakROMWS1,
	GamePakROMWS2,
	OAM,
	VRAM,
	PaletteRAM,
	IORegs,
	CPUInternalRAM,
	CPUExternalRAM,
	SystemROM,
	Unused,
]

bits_match : U32, U32, U32 -> Bool
bits_match = |i, mask, target| {
	U32.bitwise_and(i, mask) == target
}

memory_map_decode : U32 -> MemoryRegion
memory_map_decode = |addr| {
	if addr <= 0x3FFF {
		SystemROM
	} else if 0x2000000 <= addr and addr <= 0x2FFFFFF {
		CPUExternalRAM
	} else if 0x3000000 <= addr and addr <= 0x3FFFFFF {
		CPUInternalRAM
	} else if 0x4000000 <= addr and addr <= 0x4FFFFFF {
		IORegs
	} else if 0x5000000 <= addr and addr <= 0x5FFFFFF {
		PaletteRAM
	} else if 0x6000000 <= addr and addr <= 0x6FFFFFF {
		VRAM
	} else if 0x7000000 <= addr and addr <= 0x7FFFFFF {
		OAM
	} else if 0x8000000 <= addr and addr <= 0x9FFFFFF {
		GamePakROMWS0
	} else if 0xA000000 <= addr and addr <= 0xBFFFFFF {
		GamePakROMWS1
	} else if 0xC000000 <= addr and addr <= 0xDFFFFFF {
		GamePakROMWS2
	} else if 0xE000000 <= addr and addr <= 0xFFFFFFF {
		GamePakRAM
	} else {
		Unused
	}
}

addr_solver : U32 -> U32
addr_solver = |addr| {
	match memory_map_decode(addr) {
		SystemROM => addr
		CPUExternalRAM => (addr - 0x2000000).mod_by(0x40000) + 0x2000000
		CPUInternalRAM => (addr - 0x3000000).mod_by(0x8000) + 0x3000000
		IORegs => if bits_match(addr, 0b1111_1111_1111_1100, 0b1000_0000_0000) {
			(addr - 0x4000000).mod_by(0x10000) + 0x4000000
		} else {
			addr
		}
		PaletteRAM => (addr - 0x5000000).mod_by(0x400) + 0x5000000
		VRAM => if addr < 0x6010000 {
			addr
		} else if addr <= 0x601FFFF {
			(addr - 0x6010000).mod_by(0x8000) + 0x6010000
		} else {
			addr_solver((addr - 0x6020000).mod_by(0x20000) + 0x06000000)
		}
		OAM => (addr - 0x7000000).mod_by(0x400) + 0x7000000
		GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => addr
		GamePakRAM => (addr - 0xE000000).mod_by(0x10000) + 0xE000000
		Unused => addr
	}
}
