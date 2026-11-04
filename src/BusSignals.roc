BusSignals :: {
	last_fetch : [
		None,
		Fetched(
			{
				addr : U32,
				width : [W16, W32],
				val : U32,
			},
		),
	],
	last_access : [
		None,
		Accessed(
			{
				usage : [Fetch, CpuData, Dma(U8)],
				direction : [Read, Write],
				addr : U32,
				width : [W8, W16, W32],
				val : U32,
			},
		),
	],
}.{
	init : () -> BusSignals
	init = || {
		{ last_fetch: None, last_access: None }
	}

	record_read8 : BusSignals, U32, U8 -> BusSignals
	record_read8 = |old, addr, val| {
		latest_access = Accessed({
			usage: CpuData,
			direction: Read,
			addr: addr,
			width: W8,
			val: val.to_u32(),
		})
		{ ..old, last_access: latest_access }
	}

	record_write8 : BusSignals, U32, U8 -> BusSignals
	record_write8 = |old, addr, val| {
		latest_access = Accessed({
			usage: CpuData,
			direction: Write,
			addr: addr,
			width: W8,
			val: val.to_u32(),
		})
		{ ..old, last_access: latest_access }
	}

	record_read16 : BusSignals, [Fetch, CpuData, Dma(U8)], U32, U16 -> BusSignals
	record_read16 = |old, purpose, addr, val| {
		latest_access = Accessed({
			usage: purpose,
			direction: Read,
			addr: addr,
			width: W16,
			val: val.to_u32(),
		})
		if purpose == Fetch {
			{
				last_fetch: Fetched({
					addr: addr,
					width: W16,
					val: val.to_u32(),
				}),
				last_access: latest_access,
			}
		} else {
			{ ..old, last_access: latest_access }
		}
	}

	record_write16 : BusSignals, [CpuData, Dma(U8)], U32, U16 -> BusSignals
	record_write16 = |old, purpose, addr, val| {
		latest_access = Accessed({
			usage: usage_mapper(purpose),
			direction: Write,
			addr: addr,
			width: W16,
			val: val.to_u32(),
		})
		{ ..old, last_access: latest_access }
	}

	record_read32 : BusSignals, [Fetch, CpuData, Dma(U8)], U32, U32 -> BusSignals
	record_read32 = |old, purpose, addr, val| {
		latest_access = Accessed({
			usage: purpose,
			direction: Read,
			addr: addr,
			width: W32,
			val: val,
		})
		if purpose == Fetch {
			{
				last_fetch: Fetched({
					addr: addr,
					width: W32,
					val: val,
				}),
				last_access: latest_access,
			}
		} else {
			{ ..old, last_access: latest_access }
		}
	}

	record_write32 : BusSignals, [CpuData, Dma(U8)], U32, U32 -> BusSignals
	record_write32 = |old, purpose, addr, val| {
		latest_access = Accessed({
			usage: usage_mapper(purpose),
			direction: Write,
			addr: addr,
			width: W32,
			val: val,
		})
		{ ..old, last_access: latest_access }
	}
}

usage_mapper : [CpuData, Dma(U8)] -> [CpuData, Dma(U8), Fetch]
usage_mapper = |i| i
