import ARM7TDMI
import BusSignals
import Bus

CpuTypes :: {}.{
	FetchedCode : [Opcode(U32), Unmapped(U32)] # The 2nd option is really a placeholder for open bus

	# GamePak read, Idle -> no read in flight rn
	PrefetchInFlight : [Idle, Filling({ addr : U32, cycles_left : U64 })]

	# https://problemkaputt.de/gbatek-gba-gamepak-prefetch.htm
	# Thank god at most 8 halfwords can be prefetched
	GamePakPrefetch : [
		Nothing,
		Stream({ head_addr : U32, ready_count : U8, in_flight : PrefetchInFlight }),
	]

	PrefetchFields : {
		head_addr : U32, # == 0 -> Nothing, as 0 not in game PAK addr
		ready_count : U8,
		fill_left : U8, # 0 -> Idle
		force_next_rom_fetch_nonseq : Bool,
	}

	ReadyPipeline : {
		first : FetchedCode,
		second : FetchedCode,
		access_kind : ARM7TDMI.ReqKind,
	}

	Pipeline : [Empty, Ready(ReadyPipeline)]

	FetchState : { now : U64, signal : BusSignals, gamepak_prefetch : PrefetchFields }

	EngineState : {
		now : U64,
		signal : BusSignals,
		pipeline : Pipeline,
		gamepak_prefetch : PrefetchFields,
	}

	FetchResult(state_type) : [
		NeedsSlow,
		Fetched({ state : state_type, code : FetchedCode }),
	]

	HotState : { core : ARM7TDMI, pipeline : Pipeline, gamepak_prefetch : PrefetchFields }

	Suspended : [None, Resume(Box(ARM7TDMI.Execution_state))]

	RunState : {
		hot : HotState,
		now : U64,
		signal : BusSignals,
	}

	Limits : {
		event_at : U64,
		target : [None, At(U64)],
		budget : U32,
		schedule_dma : Bool,
	}

	BlockExit : [
		Boundary([ReachedTarget, BudgetExhausted, NeedsSlow]),
		Pending(ARM7TDMI.Execution_state),
	]

	BlockResult : {
		state : RunState,
		actions_completed : U32,
		exit : BlockExit,
		memory : Bus.MemoryView,
		# First fast RAM write's completion time if DMA scheduling is needed
		# schedule_pending will add 2 to mimic the DMA delay
		# Machine uses min(write_at, next_timer_at) when a timer event exists
		dma_schedule_at : [None, At(U64)],
	}
}
