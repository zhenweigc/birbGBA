import Bus
import Cpu
import MemoryRegion

ReadResult(val_type, type) : {
	val : val_type,
	state : [Unchanged, Updated(type)],
}

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
			intermediate = Bus.read16(m.bus, cur_pc)?
			instruction = intermediate.val
			state = Cpu.execute_thumb_opcode(m.cpu, instruction)?
			new_bus = match intermediate.state {
				Unchanged => m.bus
				Updated(x) => x
			}
			walk_execution_state({ ..m, bus: new_bus }, state)
		} else {
			cur_pc = (m.cpu).getPC()
			intermediate = Bus.read32(m.bus, cur_pc)?
			instruction = intermediate.val
			state = Cpu.execute_arm_opcode(m.cpu, instruction)?
			new_bus = match intermediate.state {
				Unchanged => m.bus
				Updated(x) => x
			}
			walk_execution_state({ ..m, bus: new_bus }, state)
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
			intermediate = match box.width {
				W8 => {
					inner = m.bus.read8(box.addr)?
					{
						val: inner.val.to_u32(),
						state: inner.state,
					}
				}
				W16 => {
					inner = m.bus.read16(box.addr)?
					{
						val: inner.val.to_u32(),
						state: inner.state,
					}
				}
				W32 => m.bus.read32(box.addr)?
			}
			raw_val = intermediate.val
			new_bus = match intermediate.state {
				Unchanged => m.bus
				Updated(x) => x
			}
			cpu_continue = Cpu.resume_read(
				box.cpu,
				raw_val,
				box.continuation,
			)?
			walk_execution_state({ ..m, bus: new_bus }, cpu_continue)
		}
		W(box) => {
			post_write_bus = match box.width {
				W8 => m.bus.write8(box.addr, box.val.to_u8_wrap())?
				W16 => m.bus.write16(box.addr, box.val.to_u16_wrap())?
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
