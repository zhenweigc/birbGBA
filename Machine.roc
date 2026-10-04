import Bus
import Cpu
import MemoryRegion

Machine :: {
	bus : Bus,
	cpu : Cpu,
}.{
	init : List(U8), List(U8) -> Try(Machine, _)
	init = |bios, rom| {
		Ok({
			bus: Bus.init(bios, rom)?,
			cpu: Cpu.init(),
		})
	}

	step_forward : Machine -> Try(Machine, _)
	step_forward = |m| {
		if (m.cpu).is_thumb() {
			cur_pc = (m.cpu).getPC()
			instruction = Bus.read16(m.bus, cur_pc)?
			state = Cpu.execute_thumb_opcode(m.cpu, instruction)?
			walk_execution_state(m, state)
		} else {
			cur_pc = (m.cpu).getPC()
			instruction = Bus.read32(m.bus, cur_pc)?
			state = Cpu.execute_arm_opcode(m.cpu, instruction)?
			walk_execution_state(m, state)
		}
	}

	get_cpu : Machine -> Cpu
	get_cpu = |m| {
		m.cpu
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
