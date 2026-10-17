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
	next_lcd_at : U64,
}.{
	init : List(U8), List(U8) -> Try(Machine, _)
	init = |bios, rom| {
		Ok({
			bus: Bus.init(bios, rom)?,
			cpu: Cpu.init(),
			power_state: Running,
			now: 0,
			next_lcd_at: 1232,
		})
	}

	# Pretty much a visual debugging function, maybe can be used for screenshot support
	get_video_snapshot : Machine -> Try({ dispcnt : U16, vram : List(U8) }, _)
	get_video_snapshot = |m| {
		Ok({ dispcnt: DisplayRegs.read16(m.bus.io_regs.display, 0)?, vram: m.bus.vram })
	}

	step_forward : Machine -> Try(Machine, _)
	step_forward = |m| {
		if m.power_state == Running {
			# A IRQ will cause cpu to shift mode and update regs
			ready = if SystemRegs.interrupt_req_fired(m.bus.io_regs.system) {
				{ ..m, cpu: Cpu.handle_irq(m.cpu)? }
			} else {
				m
			}
			cur_pc = (ready.cpu).getPC()
			{ execution_state, bus_update } = if (ready.cpu).is_thumb() {
				intermediate = Bus.read16(ready.bus, cur_pc)?
				instruction = intermediate.val
				state = Cpu.execute_thumb_opcode(ready.cpu, instruction)?
				{ execution_state: state, bus_update: intermediate.state }
			} else {
				intermediate = Bus.read32(ready.bus, cur_pc)?
				instruction = intermediate.val
				state = Cpu.execute_arm_opcode(ready.cpu, instruction)?
				{ execution_state: state, bus_update: intermediate.state }
			}
			match bus_update {
				Unchanged => walk_execution_state(ready, execution_state)
				Updated(new_bus) => walk_execution_state({ ..ready, bus: new_bus }, execution_state)
			}
		} else if m.power_state == Halted {
			if SystemRegs.enable_pending(m.bus.io_regs.system) != 0 {
				step_forward({ ..m, power_state: Running })
			} else {
				# A normal run flow will use run_with_budget() and will not crash into this Err
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

	process_next_event : Machine -> Try((Machine, U8), _)
	process_next_event = |m| {
		if m.power_state == Stopped {
			Ok((m, 0))
		} else {
			timer_at = TimerRegs.next_event_at(m.bus.io_regs.timers)
			at = match timer_at {
				None => m.next_lcd_at
				At(t) => t.min(m.next_lcd_at)
			}
			if at < m.now {
				Err(WrongEventTime)
			} else {
				var $cur_machine = m
				var $overflow_mask = 0
				# Timer processing
				($cur_machine, $overflow_mask) = if timer_at == At(at) {
					process_timer_at($cur_machine, at)?
				} else {
					(
						{
							..m,
							bus: {
								..m.bus,
								io_regs: {
									..m.bus.io_regs,
									timers: TimerRegs.sync_idle_to($cur_machine.bus.io_regs.timers, at)?,
								},
							},
						},
						0,
					)
				}
				# LCD processing
				if $cur_machine.next_lcd_at == at {
					after_lcd = advance_lcd_scanline($cur_machine)
					$cur_machine = { ..after_lcd, next_lcd_at: at + 1232 }
				} else {} # No need to touch lcd as its not triggered yet.
				# So the new at will either be the (now previous) next_lcd_at update timestamp
				# or the next timer reg event time, or both, since it is determined by a min
				Ok(({ ..$cur_machine, now: at }, $overflow_mask))
			}
		}
	}

	run_with_budget : Machine, U32 -> Try(Machine, _)
	run_with_budget = |m, num_of_actions| {
		if num_of_actions == 0 {
			Ok(m)
		} else {
			match m.power_state {
				Running => run_with_budget(step_forward(m)?, num_of_actions - 1)
				Halted if SystemRegs.enable_pending(m.bus.io_regs.system) != 0 => run_with_budget(step_forward(m)?, num_of_actions - 1)
				Halted => {
					(new_m, _) = process_next_event(m)?
					run_with_budget(new_m, num_of_actions - 1)
				}
				Stopped => Ok(m)
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

# overflow val is returned for better debugging purpose
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
