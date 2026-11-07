import ARM7TDMI
import BusSignals

FetchedCode : [Opcode(U32), Unmapped(U32)] # The 2nd option is really a placeholder for open bus

Pipeline : [
	Empty,
	Ready(
		{
			first : FetchedCode,
			second : FetchedCode,
			access_kind : ARM7TDMI.ReqKind,
		},
	),
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

BlockResult : {
	state : RunState,
	actions_completed : U32,
	exit : [
		Boundary([ReachedTarget, BudgetExhausted, NeedsSlow]),
		Pending(ARM7TDMI.Execution_state),
	],
}

CpuTypes :: {}.{}
