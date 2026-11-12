import ARM7TDMI
import BusSignals
import Bus

FetchedCode : [Opcode(U32), Unmapped(U32)] # The 2nd option is really a placeholder for open bus

ReadyPipeline : {
	first : FetchedCode,
	second : FetchedCode,
	access_kind : ARM7TDMI.ReqKind,
}

Pipeline : [Empty, Ready(ReadyPipeline)]

FetchState : { now : U64, signal : BusSignals }

EngineState : {
	now : U64,
	signal : BusSignals,
	pipeline : Pipeline,
}

FetchResult(state_type) : [
	NeedsSlow,
	Fetched({ state : state_type, code : FetchedCode }),
]

HotState : { core : ARM7TDMI, pipeline : Pipeline }

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

CpuTypes :: {}.{}
