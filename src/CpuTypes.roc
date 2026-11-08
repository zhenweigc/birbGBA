import ARM7TDMI
import BusSignals

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
}

BlockExit : [
	Boundary([ReachedTarget, BudgetExhausted, NeedsSlow]),
	Pending(ARM7TDMI.Execution_state),
]

BlockResult : {
	state : RunState,
	actions_completed : U32,
	exit : BlockExit,
}

CpuTypes :: {}.{}
