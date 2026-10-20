bits_match : U32, U32, U32 -> Bool
bits_match = |i, mask, target| {
	U32.bitwise_and(i, mask) == target
}

DecodedAddress : {
	region : MemoryRegion,
	relative_addr : U32,
}

dac : MemoryRegion, U32 -> DecodedAddress
dac = |m, i| {
	{
		region: m,
		relative_addr: i,
	}
}

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
].{
	memory_map_decode : U32 -> DecodedAddress
	memory_map_decode = |addr| {
		if addr <= 0x3FFF {
			dac(SystemROM, addr)
		} else if 0x2000000 <= addr and addr <= 0x2FFFFFF {
			dac(CPUExternalRAM, (addr - 0x2000000).mod_by(0x40000))
		} else if 0x3000000 <= addr and addr <= 0x3FFFFFF {
			dac(CPUInternalRAM, (addr - 0x3000000).mod_by(0x8000))
		} else if 0x4000000 <= addr and addr <= 0x4FFFFFF {
			dac(
				IORegs,
				if bits_match(addr, 0b1111_1111_1111_1100, 0b1000_0000_0000) {
					(addr - 0x4000000).mod_by(0x10000)
				} else {
					addr - 0x4000000
				},
			)
		} else if 0x5000000 <= addr and addr <= 0x5FFFFFF {
			dac(PaletteRAM, (addr - 0x5000000).mod_by(0x400))
		} else if 0x6000000 <= addr and addr <= 0x6FFFFFF {
			# Bytes 0x06010000 - 0x06017FFF is mirrored from 0x06018000 - 0x0601FFFF.
			# The entire region from 0x06000000 - 0x06020000 is in turn mirrored every
			# 0x20000 bytes from 0x06000000 - 0x06FFFFFF.
			# TLDR: [A B C C], 0x20000 long
			vram_decoder : U32 -> U32
			vram_decoder = |i| {
				if i >= 0x6020000 {
					vram_decoder((i - 0x6020000).mod_by(0x20000) + 0x6000000)
				} else if i >= 0x6018000 {
					vram_decoder((i - 0x6018000).mod_by(0x8000) + 0x06010000)
				} else {
					i - 0x6000000
				}
			}
			dac(VRAM, vram_decoder(addr))
		} else if 0x7000000 <= addr and addr <= 0x7FFFFFF {
			dac(OAM, (addr - 0x7000000).mod_by(0x400))
		} else if 0x8000000 <= addr and addr <= 0x9FFFFFF {
			dac(GamePakROMWS0, addr - 0x8000000)
		} else if 0xA000000 <= addr and addr <= 0xBFFFFFF {
			dac(GamePakROMWS1, addr - 0xA000000)
		} else if 0xC000000 <= addr and addr <= 0xDFFFFFF {
			dac(GamePakROMWS2, addr - 0xC000000)
		} else if 0xE000000 <= addr and addr <= 0xFFFFFFF {
			dac(GamePakRAM, (addr - 0xE000000).mod_by(0x10000))
		} else {
			dac(Unused, addr)
		}
	}
}
