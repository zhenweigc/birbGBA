import ARM7TDMI
import BusSignals
import CpuTypes

# The new Cpu server as an executer by mergable opcode blocks
Cpu := {
	hot : CpuTypes.HotState,
	suspended : CpuTypes.Suspended,
}.{
	init : () -> Cpu
	init = || { hot: init_hot(), suspended: None }

	get_core : Cpu -> ARM7TDMI
	get_core = |c| c.hot.core
}

init_hot : () -> CpuTypes.HotState
init_hot = || { core: ARM7TDMI.init(), pipeline: Empty }
