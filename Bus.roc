import MemoryRegion
import IoRegs

ReadResult(val_type, type) : {
	val : val_type,
	state : [Unchanged, Updated(type)],
}

Bus :: {
	ewram : List(U8),
	iwram : List(U8),
	paletteram : List(U8),
	vram : List(U8),
	oam : List(U8),
	gamepak_rom : List(U8),
	bios : List(U8),
	io_regs : IoRegs,
}.{
	init : List(U8), List(U8) -> Try(Bus, [ROMSizeTooLarge, InvalidBIOSSize])
	init = |bios, rom| {
		if rom.len() > 0x02000000 {
			Err(ROMSizeTooLarge)
		} else if bios.len() != 0x4000 {
			Err(InvalidBIOSSize)
		} else {
			Ok({
				ewram: List.repeat(0, 0x40000),
				iwram: List.repeat(0, 0x8000),
				paletteram: List.repeat(0, 1024),
				vram: List.repeat(0, 0x18000),
				oam: List.repeat(0, 0x400),
				gamepak_rom: rom,
				bios: bios,
				io_regs: IoRegs.init(),
			})
		}
	}

	read8 : Bus,
	U32 -> Try(
		ReadResult(U8, Bus),
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			UnsupportedIORegOffset(U32),
		],
	)
	read8 = |bus, addr| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		match region {
			CPUExternalRAM => Ok({ val: (bus.ewram).get(U32.to_u64(relative_addr))?, state: Unchanged })
			CPUInternalRAM => Ok({ val: (bus.iwram).get(U32.to_u64(relative_addr))?, state: Unchanged })
			PaletteRAM => Ok({ val: (bus.paletteram).get(U32.to_u64(relative_addr))?, state: Unchanged })
			VRAM => {
				dispcnt = IoRegs.read16(bus.io_regs, 0)?.val
				mode = dispcnt.bitwise_and(0b111)
				window_offset = (addr - 0x6000000).mod_by(0x20000)
				if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
					Ok({ val: 0, state: Unchanged })
				} else {
					Ok({ val: (bus.vram).get(U32.to_u64(relative_addr))?, state: Unchanged })
				}
			}
			OAM => Ok({ val: (bus.oam).get(U32.to_u64(relative_addr))?, state: Unchanged })
			GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Ok({ val: (bus.gamepak_rom).get(U32.to_u64(relative_addr))?, state: Unchanged })
			SystemROM => Ok({ val: (bus.bios).get(U32.to_u64(relative_addr))?, state: Unchanged })
			IORegs => {
				intermediate = IoRegs.read8(bus.io_regs, relative_addr)?
				Ok({
					val: intermediate.val,
					state: match intermediate.reg {
						Unchanged => Unchanged
						Updated(x) => Updated({ ..bus, io_regs: x })
					},
				})
			}
			_ => Err(UnsupportedRegion(region))
		}
	}

	write8 : Bus,
	U32,
	U8 -> Try(
		Bus,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			UnsupportedIORegOffset(U32),
			WriteIntoROM(U32),
		],
	)
	write8 = |bus, addr, cxt| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		match region {
			CPUExternalRAM => Ok({
				..bus,
				ewram: (bus.ewram).set(relative_addr.to_u64(), cxt)?,
			})
			CPUInternalRAM => Ok({
				..bus,
				iwram: (bus.iwram).set(relative_addr.to_u64(), cxt)?,
			})
			PaletteRAM => {
				aligned_addr = if relative_addr.mod_by(2) == 0 {
					relative_addr
				} else {
					relative_addr - 1
				}
				Ok({
					..bus,
					paletteram: (bus.paletteram).set(aligned_addr.to_u64(), cxt)?.set(aligned_addr.plus(1).to_u64(), cxt)?,
				})
			}
			VRAM => {
				dispcnt = IoRegs.read16(bus.io_regs, 0)?.val
				mode = dispcnt.bitwise_and(0b111)
				window_offset = (addr - 0x06000000).mod_by(0x20000)
				maximum_addr = if mode < 3 {
					0x10000
				} else if mode < 6 {
					0x14000
				} else {
					0x14000 # technically banned, but somehow mGBA allows it
				}
				aligned_addr = if relative_addr.mod_by(2) == 0 {
					relative_addr
				} else {
					relative_addr - 1
				}
				if window_offset >= maximum_addr {
					Ok(bus)
				} else {
					Ok({ ..bus, vram: (bus.vram).set(aligned_addr.to_u64(), cxt)?.set(aligned_addr.plus(1).to_u64(), cxt)? })
				}
			}
			OAM => Ok(bus) # GBAtek explicitly said no 1byte write
			GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Err(WriteIntoROM(addr))
			SystemROM => Ok(bus)
			IORegs => Ok({
				..bus,
				io_regs: IoRegs.write8(bus.io_regs, relative_addr, cxt)?,
			})
			_ => Err(UnsupportedRegion(region))
		}
	}

	read16 : Bus,
	U32 -> Try(
		ReadResult(U16, Bus),
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	read16 = |bus, addr| {
		if addr.mod_by(2) == 1 {
			Err(MisalignedAddress(addr))
		} else {
			read_le16 : List(U8), U32 -> Try(U16, [OutOfBounds])
			read_le16 = |lst, relative_addr| {
				i = lst.get(relative_addr.plus(1).to_u64())?
				j = lst.get(relative_addr.to_u64())?
				Ok(i.to_u16().shl_wrap(8) + j.to_u16())
			}
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			match region {
				CPUExternalRAM => Ok({
					val: read_le16(bus.ewram, relative_addr)?,
					state: Unchanged,
				})
				CPUInternalRAM => Ok({
					val: read_le16(bus.iwram, relative_addr)?,
					state: Unchanged,
				})
				PaletteRAM => Ok({
					val: read_le16(bus.paletteram, relative_addr)?,
					state: Unchanged,
				})
				VRAM => {
					dispcnt = IoRegs.read16(bus.io_regs, 0)?.val
					mode = dispcnt.bitwise_and(0b111)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						# If cond directly stolen from mGBA
						Ok({ val: 0, state: Unchanged })
					} else {
						Ok({
							val: read_le16(bus.vram, relative_addr)?,
							state: Unchanged,
						})
					}
				}
				OAM => Ok({
					val: read_le16(bus.oam, relative_addr)?,
					state: Unchanged,
				})
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Ok({
					val: read_le16(bus.gamepak_rom, relative_addr)?,
					state: Unchanged,
				})
				SystemROM => Ok({
					val: read_le16(bus.bios, relative_addr)?,
					state: Unchanged,
				})
				IORegs => {
					intermediate = IoRegs.read16(bus.io_regs, relative_addr)?
					Ok({
						val: intermediate.val,
						state: match intermediate.reg {
							Unchanged => Unchanged
							Updated(x) => Updated({ ..bus, io_regs: x })
						},
					})
				}
				_ => Err(UnsupportedRegion(region))
			}
		}
	}

	write16 : Bus,
	U32,
	U16 -> Try(
		Bus,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			WriteIntoROM(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	write16 = |bus, addr, cxt| {
		chopper = |i| {
			{ lo: i.to_u8_wrap(), hi: i.shr_wrap(8).to_u8_wrap() }
		}
		if addr.mod_by(2) == 1 {
			Err(MisalignedAddress(addr))
		} else {
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			{ lo, hi } = chopper(cxt)
			match region {
				CPUExternalRAM => Ok({
					..bus,
					ewram: (bus.ewram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
				})
				CPUInternalRAM => Ok({
					..bus,
					iwram: (bus.iwram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
				})
				PaletteRAM => Ok({
					..bus,
					paletteram: (bus.paletteram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
				})
				VRAM => {
					dispcnt = IoRegs.read16(bus.io_regs, 0)?.val
					mode = dispcnt.bitwise_and(0b111)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						Ok(bus)
					} else {
						Ok({
							..bus,
							vram: (bus.vram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
						})
					}
				}
				OAM => Ok({
					..bus,
					oam: (bus.oam).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
				})
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Err(WriteIntoROM(addr))
				SystemROM => Ok(bus)
				IORegs => Ok({
					..bus,
					io_regs: IoRegs.write16(bus.io_regs, relative_addr, cxt)?,
				})
				_ => Err(UnsupportedRegion(region))
			}
		}
	}

	read32 : Bus,
	U32 -> Try(
		ReadResult(U32, Bus),
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	read32 = |bus, addr| {
		if addr.mod_by(4) > 0 {
			Err(MisalignedAddress(addr))
		} else {
			read_le32 : List(U8), U32 -> Try(U32, [OutOfBounds])
			read_le32 = |lst, relative_addr| {
				i = lst.get(relative_addr.plus(3).to_u64())?
				j = lst.get(relative_addr.plus(2).to_u64())?
				k = lst.get(relative_addr.plus(1).to_u64())?
				l = lst.get(relative_addr.to_u64())?
				Ok(i.to_u32().shl_wrap(24) + j.to_u32().shl_wrap(16) + k.to_u32().shl_wrap(8) + l.to_u32())
			}
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			match region {
				CPUExternalRAM => Ok({
					val: read_le32(bus.ewram, relative_addr)?,
					state: Unchanged,
				})
				CPUInternalRAM => Ok({
					val: read_le32(bus.iwram, relative_addr)?,
					state: Unchanged,
				})
				PaletteRAM => Ok({
					val: read_le32(bus.paletteram, relative_addr)?,
					state: Unchanged,
				})
				VRAM => {
					dispcnt = IoRegs.read16(bus.io_regs, 0)?.val
					mode = dispcnt.bitwise_and(0b111)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						Ok({ val: 0, state: Unchanged })
					} else {
						Ok({
							val: read_le32(bus.vram, relative_addr)?,
							state: Unchanged,
						})
					}
				}
				OAM => Ok({
					val: read_le32(bus.oam, relative_addr)?,
					state: Unchanged,
				})
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Ok({
					val: read_le32(bus.gamepak_rom, relative_addr)?,
					state: Unchanged,
				})
				SystemROM => Ok({
					val: read_le32(bus.bios, relative_addr)?,
					state: Unchanged,
				})
				IORegs => {
					intermediate = IoRegs.read32(bus.io_regs, relative_addr)?
					Ok({
						val: intermediate.val,
						state: match intermediate.reg {
							Unchanged => Unchanged
							Updated(x) => Updated({ ..bus, io_regs: x })
						},
					})
				}
				_ => Err(UnsupportedRegion(region))
			}
		}
	}

	write32 : Bus,
	U32,
	U32 -> Try(
		Bus,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			WriteIntoROM(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	write32 = |bus, addr, cxt| {
		chopper = |i| {
			{
				semel: i.to_u8_wrap(),
				bis: i.shr_wrap(8).to_u8_wrap(),
				ter: i.shr_wrap(16).to_u8_wrap(),
				quater: i.shr_wrap(24).to_u8_wrap(),
			}
		}
		if addr.mod_by(4) > 0 {
			Err(MisalignedAddress(addr))
		} else {
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			{ semel, bis, ter, quater } = chopper(cxt)
			match region {
				CPUExternalRAM => Ok({
					..bus,
					ewram: (bus.ewram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
				})
				CPUInternalRAM => Ok({
					..bus,
					iwram: (bus.iwram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
				})
				PaletteRAM => Ok({
					..bus,
					paletteram: (bus.paletteram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
				})
				VRAM => {
					dispcnt = IoRegs.read16(bus.io_regs, 0)?.val
					mode = dispcnt.bitwise_and(0b111)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						Ok(bus)
					} else {
						Ok({
							..bus,
							vram: (bus.vram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
						})
					}
				}
				OAM => Ok({
					..bus,
					oam: (bus.oam).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
				})
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Err(WriteIntoROM(addr))
				SystemROM => Ok(bus)
				IORegs => Ok({
					..bus,
					io_regs: IoRegs.write32(bus.io_regs, relative_addr, cxt)?,
				})
				_ => Err(UnsupportedRegion(region))
			}
		}
	}
}
