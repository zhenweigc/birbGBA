import Bus
import Cpu
import MemoryRegion

Machine :: {
	bus : Bus,
	cpu : Cpu,
}.{
	step_forward : Machine -> Try(Machine, _)
	step_forward = |m| {
		if (m.cpu).is_thumb() {
			Err(Temp_Thumb_not_implemented)
		} else {
			cur_pc = (m.cpu).getPC()
			instruction = Bus.read32(m.bus, cur_pc)?
			state = Cpu.execute_arm_opcode(m.cpu, instruction)?
			walk_execution_state(m, state)
		}
	}
}

walk_execution_state : Machine, Cpu.Execution_state -> Try(Machine, _)
walk_execution_state = |m, state| {
	match state {
		Complete(c) => Ok({ ..m, cpu: c })
		R(box) => {
			raw_val = match box.width {
				W8 => U8.to_u32(m.bus.read8(box.addr)?)
				W16 => U16.to_u32(m.bus.read16(box.addr)?)
				W32 => m.bus.read32(box.addr)?
			}
			cpu_continue = Cpu.resume_read(
				box.cpu,
				raw_val,
				box.continuation,
			)?
			walk_execution_state(m, cpu_continue)
		}
		W(box) => {
			post_write_bus = match box.width {
				W8 => m.bus.write8(box.addr, U32.to_u8_wrap(box.val))?
				W16 => m.bus.write16(box.addr, U32.to_u16_wrap(box.val))?
				W32 => m.bus.write32(box.addr, box.val)?
			}
			cpu_continue = Cpu.resume_write(
				box.cpu,
				box.continuation,
			)?
			walk_execution_state({ ..m, bus: post_write_bus }, cpu_continue)
		}
	}
}
