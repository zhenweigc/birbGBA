import BusTypes

BusSignals :: {
	fetch : U64,
	access : U64,
	fetch_width : [None, W16, W32],
	access_kind : AccessKind,
	bios_latch : [None, BIOS(U32)],
}.{
	AccessKind : [
		None,
		Fetch,
		CpuData(BusTypes.Direction, BusTypes.Width),
		Dma(U8, BusTypes.Direction, BusTypes.HalfOrWord),
	]

	init : () -> BusSignals
	init = || { fetch: 0, access: 0, fetch_width: None, access_kind: None, bios_latch: None }

	get_bios_latch : BusSignals -> [None, BIOS(U32)]
	get_bios_latch = |bus| bus.bios_latch

	set_bios_latch : BusSignals, U32 -> BusSignals
	set_bios_latch = |old, word| { ..old, bios_latch: BIOS(word) }

	record_read8 : BusSignals, U32, U8 -> BusSignals
	record_read8 = |old, addr, val| {
		{ ..old, access: pair(addr, val.to_u32()), access_kind: CpuData(Read, W8) }
	}

	record_write8 : BusSignals, U32, U8 -> BusSignals
	record_write8 = |old, addr, val| {
		{ ..old, access: pair(addr, val.to_u32()), access_kind: CpuData(Write, W8) }
	}

	record_read16 : BusSignals, [Fetch, CpuData, Dma(U8)], U32, U16 -> BusSignals
	record_read16 = |old, purpose, addr, val| {
		kind = match purpose {
			Fetch => return {
				..old,
				fetch: pair(addr, val.to_u32()),
				fetch_width: W16,
				access_kind: Fetch,
			}
			CpuData => CpuData(Read, W16)
			Dma(selection) => Dma(selection, Read, W16)
		}
		{ ..old, access: pair(addr, val.to_u32()), access_kind: kind }
	}

	record_write16 : BusSignals, [CpuData, Dma(U8)], U32, U16 -> BusSignals
	record_write16 = |old, purpose, addr, val| {
		{
			..old,
			access: pair(addr, val.to_u32()),
			access_kind: match purpose {
				CpuData => CpuData(Write, W16)
				Dma(selection) => Dma(selection, Write, W16)
			},
		}
	}

	record_read32 : BusSignals, [Fetch, CpuData, Dma(U8)], U32, U32 -> BusSignals
	record_read32 = |old, purpose, addr, val| {
		kind = match purpose {
			Fetch => return {
				..old,
				fetch: pair(addr, val),
				fetch_width: W32,
				access_kind: Fetch,
			}
			CpuData => CpuData(Read, W32)
			Dma(x) => Dma(x, Read, W32)
		}
		{ ..old, access: pair(addr, val), access_kind: kind }
	}

	record_write32 : BusSignals, [CpuData, Dma(U8)], U32, U32 -> BusSignals
	record_write32 = |old, purpose, addr, val| {
		{
			..old,
			access: pair(addr, val),
			access_kind: match purpose {
				CpuData => CpuData(Write, W32)
				Dma(selection) => Dma(selection, Write, W32)
			},
		}
	}
}

pair : U32, U32 -> U64 # Hi-> Addr, Lo -> Val
pair = |addr, val| addr.to_u64().shl_wrap(32).bitwise_or(val.to_u64())
