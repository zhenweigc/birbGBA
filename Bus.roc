import MemoryRegion

Bus :: {
	ewram : List(U8),
}.{
	init : () -> Bus
	init = || {
		{
			ewram: List.repeat(0, 0x40000),
		}
	}

	read8 : Bus, U32 -> Try(U8, [OutOfBounds])
	read8 = |bus, addr| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		match region {
			CPUExternalRAM => (bus.ewram).get(U32.to_u64(relative_addr))
			_ => Err(OutOfBounds)
		}
	}

	write8 : Bus, U32, U8 -> Try(Bus, [OutOfBounds])
	write8 = |bus, addr, cxt| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		match region {
			CPUExternalRAM => Ok({
				..bus,
				ewram: (bus.ewram).set(relative_addr.to_u64(), cxt)?,
			})
			_ => Err(OutOfBounds)
		}
	}
}
