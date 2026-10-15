import Bus
import Cpu
import SystemRegs
import DisplayRegs
import TimerRegs

Machine :: {
	bus : Bus,
	cpu : Cpu,
	power_state : [Running, Halted, Stopped],
	now : U64,
}.{
	init : List(U8), List(U8) -> Try(Machine, _)
	init = |bios, rom| {
		Ok({
			bus: Bus.init(bios, rom)?,
			cpu: Cpu.init(),
			power_state: Running,
			now: 0,
		})
	}

	step_forward : Machine -> Try(Machine, _)
	step_forward = |m| {
		if m.power_state == Running {
			cur_pc = (m.cpu).getPC()
			{ execution_state, bus_update } = if (m.cpu).is_thumb() {
				intermediate = Bus.read16(m.bus, cur_pc)?
				instruction = intermediate.val
				state = Cpu.execute_thumb_opcode(m.cpu, instruction)?
				{ execution_state: state, bus_update: intermediate.state }
			} else {
				intermediate = Bus.read32(m.bus, cur_pc)?
				instruction = intermediate.val
				state = Cpu.execute_arm_opcode(m.cpu, instruction)?
				{ execution_state: state, bus_update: intermediate.state }
			}
			match bus_update {
				Unchanged => walk_execution_state(m, execution_state)
				Updated(new_bus) => walk_execution_state({ ..m, bus: new_bus }, execution_state)
			}
		} else if m.power_state == Halted {
			if SystemRegs.enable_pending(m.bus.io_regs.system) != 0 {
				step_forward({ ..m, power_state: Running })
			} else {
				Err(CpuHalted)
			}
		} else {
			Err(TempStopNotImplemented)
		}
	}

	get_cpu : Machine -> Cpu
	get_cpu = |m| {
		m.cpu
	}

	advance_lcd_scanline : Machine -> Machine
	advance_lcd_scanline = |m| {
		if m.power_state == Stopped {
			m
		} else {
			(dp_rgs, mask) = DisplayRegs.advance_scanline(m.bus.io_regs.display)
			sys_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, mask)
			io_rgs = { ..m.bus.io_regs, display: dp_rgs, system: sys_rgs }
			new_bus = { ..m.bus, io_regs: io_rgs }
			{ ..m, bus: new_bus }
		}
	}

	# The returned overflow is for better debugging purpose
	tick_timer : Machine, [Timer0, Timer1, Timer2, Timer3] -> (Machine, U8)
	tick_timer = |m, selected_timer| {
		match m.power_state {
			Stopped => (m, 0)
			_ => {
				(new_timer_rgs, masks) = TimerRegs.tick(m.bus.io_regs.timers, selected_timer, Clock)
				new_sys_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, masks.irq_mask)
				(
					{
						..m,
						bus: {
							..m.bus,
							io_regs: {
								..m.bus.io_regs,
								system: new_sys_rgs,
								timers: new_timer_rgs,
							},
						},
					},
					masks.overflow_mask,
				)
			}
		}
	}

	process_timer_at : Machine, U64 -> Try((Machine, U8), _)
	process_timer_at = |m, at| {
		match m.power_state {
			Stopped => Ok((m, 0))
			_ => {
				if at >= m.now {
					(new_timers_rgs, masks) = TimerRegs.process_at(m.bus.io_regs.timers, at)?
					new_system_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, masks.irq_mask)
					Ok((
						{
							..m,
							bus: {
								..m.bus,
								io_regs: {
									..m.bus.io_regs,
									timers: new_timers_rgs,
									system: new_system_rgs,
								},
							},
							now: at,
						},
						masks.overflow_mask,
					))
				} else {
					Err(WrongEventTime)
				}
			}
		}
	}
}

walk_execution_state : Machine, Cpu.Execution_state -> Try(Machine, _)
walk_execution_state = |m, state| {
	match state {
		Complete(c) => {
			# Luckily, for halt command which happens in the middle of a batch write in,
			# we do not need to interrupt the opcode and immediately enter Cpu Pause mode.
			(new_system, req) = SystemRegs.process_haltcnt(m.bus.io_regs.system)
			new_ioregs = { ..m.bus.io_regs, system: new_system }
			new_bus = { ..m.bus, io_regs: new_ioregs }
			Ok({
				..m,
				cpu: c,
				bus: new_bus,
				power_state: match req {
					NoReq => m.power_state
					Request(x) => if x.bitwise_and(0b1000_0000) == 0 {
						Halted
					} else {
						Stopped
					}
				},
			})
		}
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
			cur_addr = Cpu.getPC(m.cpu)
			req_bios = Bus.requires_bios(box.width, box.addr)
			post_write_bus = match box.width {
				W8 => {
					if req_bios and cur_addr > 0x3FFF {
						m.bus
					} else {
						m.bus.write8(box.addr, box.val.to_u8_wrap())?
					}
				}
				W16 => {
					if req_bios and cur_addr > 0x3FFF {
						m.bus
					} else {
						m.bus.write16(box.addr, box.val.to_u16_wrap())?
					}
				}
				W32 => {
					if req_bios and cur_addr > 0x3FFF {
						m.bus
					} else {
						m.bus.write32(box.addr, box.val)?
					}
				}
			}
			cpu_continue = Cpu.resume_write(
				box.cpu,
				box.continuation,
			)?
			walk_execution_state({ ..m, bus: post_write_bus }, cpu_continue)
		}
	}
}
