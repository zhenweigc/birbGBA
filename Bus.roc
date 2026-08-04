import MemoryRegion

Bus :: {
	ewram : List(U8),
	iwram : List(U8),
	gamepak_rom : List(U8),
}.{
	init : List(U8) -> Try(Bus, [ROMSizeTooLarge])
	init = |rom| {
		if rom.len() > 0x02000000 {
			Err(ROMSizeTooLarge)
		} else {
			Ok({
				ewram: List.repeat(0, 0x40000),
				iwram: List.repeat(0, 0x8000),
				gamepak_rom: rom,
			})
		}
	}

	read8 : Bus, U32 -> Try(U8, [OutOfBounds, UnsupportedRegion(MemoryRegion)])
	read8 = |bus, addr| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		match region {
			CPUExternalRAM => (bus.ewram).get(U32.to_u64(relative_addr))
			CPUInternalRAM => (bus.iwram).get(U32.to_u64(relative_addr))
			GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => (bus.gamepak_rom).get(U32.to_u64(relative_addr))
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
			_ => Err(UnsupportedRegion(region))
		}
	}

	read16 : Bus,
	U32 -> Try(
		U16,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
		],
	)
	read16 = |bus, addr| {
		if addr.mod_by(2) == 1 {
			Err(MisalignedAddress(addr))
		} else {
			combiner = |i, j| {
				U8.to_u16(i).shl_wrap(8) + U8.to_u16(j)
			}
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			match region {
				CPUExternalRAM => Ok(combiner((bus.ewram).get(U32.to_u64(relative_addr.plus(1)))?, (bus.ewram).get(U32.to_u64(relative_addr))?))
				CPUInternalRAM => Ok(combiner((bus.iwram).get(U32.to_u64(relative_addr.plus(1)))?, (bus.iwram).get(U32.to_u64(relative_addr))?))
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Ok(combiner((bus.gamepak_rom).get(U32.to_u64(relative_addr.plus(1)))?, (bus.gamepak_rom).get(U32.to_u64(relative_addr))?))
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
				_ => Err(UnsupportedRegion(region))
			}
		}
	}

	read32 : Bus,
	U32 -> Try(
		U32,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
		],
	)
	read32 = |bus, addr| {
		if addr.mod_by(4) > 0 {
			Err(MisalignedAddress(addr))
		} else {
			combiner = |i, j, k, l| {
				U8.to_u32(i).shl_wrap(24) + U8.to_u32(j).shl_wrap(16) + U8.to_u32(k).shl_wrap(8) + U8.to_u32(l)
			}
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			match region {
				CPUExternalRAM => Ok(combiner((bus.ewram).get(U32.to_u64(relative_addr.plus(3)))?, (bus.ewram).get(U32.to_u64(relative_addr.plus(2)))?, (bus.ewram).get(U32.to_u64(relative_addr.plus(1)))?, (bus.ewram).get(U32.to_u64(relative_addr))?))
				CPUInternalRAM => Ok(combiner((bus.iwram).get(U32.to_u64(relative_addr.plus(3)))?, (bus.iwram).get(U32.to_u64(relative_addr.plus(2)))?, (bus.iwram).get(U32.to_u64(relative_addr.plus(1)))?, (bus.iwram).get(U32.to_u64(relative_addr))?))
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Ok(combiner((bus.gamepak_rom).get(U32.to_u64(relative_addr.plus(3)))?, (bus.gamepak_rom).get(U32.to_u64(relative_addr.plus(2)))?, (bus.gamepak_rom).get(U32.to_u64(relative_addr.plus(1)))?, (bus.gamepak_rom).get(U32.to_u64(relative_addr))?))
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
				_ => Err(UnsupportedRegion(region))
			}
		}
	}
}
