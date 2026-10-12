import MemoryRegion
import IoRegs

ReadResult(val_type, type) : {
	val : val_type,
	state : [Unchanged, Updated(type)],
}

Bus :: {
	ewram : List(U8),
	iwram : List(U8),
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
