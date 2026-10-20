import Bits
import Bus
import Cpu
import SystemRegs
import DisplayRegs
import TimerRegs

FetchedCode : [Opcode(U32), Unmapped(U32)] # The 2nd option is really a placeholder for open bus

Machine :: {
	bus : Bus,
	cpu : Cpu,
	power_state : [Running, Halted, Stopped],
	now : U64,
	next_lcd_at : U64,
	next_lcd_event : [EnterHBlank, NextScanline],
	pipeline : [
		Empty,
		Ready(
			{
				first : FetchedCode,
				second : FetchedCode,
				access_kind : [NonSequential, Sequential],
			},
		),
	],
}.{
	init : List(U8), List(U8) -> Try(Machine, _)
	init = |bios, rom| {
		Ok({
			bus: Bus.init(bios, rom)?,
			cpu: Cpu.init(),
			power_state: Running,
			now: 0,
			next_lcd_at: 1007,
			next_lcd_event: EnterHBlank,
			pipeline: Empty,
		})
	}

	# Pretty much a visual debugging function, maybe can be used for screenshot support
	get_video_snapshot : Machine -> Try({ dispcnt : U16, vram : List(U8) }, _)
	get_video_snapshot = |m| {
		Ok({ dispcnt: DisplayRegs.read16(m.bus.io_regs.display, 0)?, vram: m.bus.vram })
	}

	get_time : Machine -> U64 # slop method
	get_time = |m| m.now

	step_forward : Machine -> Try(Machine, _)
	step_forward = |m| {
		if m.power_state == Running {
			ready = accept_pending_irq(m)?
			(fetched, code) = take_opcode(ready)?
			instruction = match code {
				Opcode(op) => op
				Unmapped(addr) => return Err(UnmappedInstructionFetch(addr))
			}
			execution_state = if fetched.cpu.is_thumb() {
				Cpu.execute_thumb_opcode(fetched.cpu, instruction.to_u16_wrap())?
			} else {
				Cpu.execute_arm_opcode(fetched.cpu, instruction)?
			}
			walk_execution_state(fetched, execution_state)
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
					after_lcd = process_lcd_event($cur_machine, at)
					$cur_machine = after_lcd
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

	advance_to : Machine, U64 -> Try(Machine, _)
	advance_to = |m, target| {
		if m.power_state == Stopped {
			Ok(m)
		} else if target < m.now {
			Err(WrongEventTime)
		} else {
			timer_at = TimerRegs.next_event_at(m.bus.io_regs.timers)
			at = match timer_at {
				None => m.next_lcd_at
				At(t) => t.min(m.next_lcd_at)
			}
			if at <= target {
				(new_machine, _) = process_next_event(m)?
				advance_to(new_machine, target)
			} else {
				Ok({
					..m,
					bus: {
						..m.bus,
						io_regs: {
							..m.bus.io_regs,
							timers: TimerRegs.sync_idle_to(m.bus.io_regs.timers, target)?,
						},
					},
					now: target,
				})
			}
		}
	}
}

walk_execution_state : Machine, Cpu.Execution_state -> Try(Machine, _)
walk_execution_state = |m, state| {
	match state {
		Complete(done) => {
			cycle_consumed_machine = Machine.advance_to(m, m.now + done.remaining_cycles)?
			c = done.cpu
			completed = if done.remaining_cycles > 0 {
				mark_fetch_nonsequential({ ..cycle_consumed_machine, cpu: done.cpu })
			} else {
				{ ..cycle_consumed_machine, cpu: done.cpu }
			}
			pipeline_side_effect_considered = match done.pc_status {
				PCSequential => completed
				PCWritten => reload_pipeline(completed)?
			}
			# Luckily, for halt command which happens in the middle of a batch write in,
			# we do not need to interrupt the opcode and immediately enter Cpu Pause mode.
			(new_system, req) = SystemRegs.process_haltcnt(pipeline_side_effect_considered.bus.io_regs.system)
			new_ioregs = { ..pipeline_side_effect_considered.bus.io_regs, system: new_system }
			new_bus = { ..pipeline_side_effect_considered.bus, io_regs: new_ioregs }
			Ok({
				..pipeline_side_effect_considered,
				cpu: c,
				bus: new_bus,
				power_state: match req {
					NoReq => pipeline_side_effect_considered.power_state
					Request(x) => if x.bitwise_and(0b1000_0000) == 0 {
						Halted
					} else {
						Stopped
					}
				},
			})
		}
		R(box) => {
			cycles = Bus.base_access_cycles(m.bus, box.width, box.addr, box.access_kind)?
			io_delay_applied_machine = Machine.advance_to(m, m.now + cycles)?
			intermediate = match box.width {
				W8 => {
					inner = io_delay_applied_machine.bus.read8(box.addr)?
					{ val: inner.val.to_u32(), state: inner.state }
				}
				W16 => {
					inner = io_delay_applied_machine.bus.read16(box.addr)?
					{ val: inner.val.to_u32(), state: inner.state }
				}
				W32 => io_delay_applied_machine.bus.read32(box.addr)?
			}
			raw_val = intermediate.val
			new_bus = match intermediate.state {
				Unchanged => io_delay_applied_machine.bus
				Updated(x) => x
			}
			cpu_continue = Cpu.resume_read(
				box.cpu,
				raw_val,
				box.continuation,
			)?
			walk_execution_state(mark_fetch_nonsequential({ ..io_delay_applied_machine, bus: new_bus }), cpu_continue)
		}
		W(box) => {
			cur_addr = Cpu.getPC(m.cpu)
			req_bios = Bus.requires_bios(box.width, box.addr)
			cycles = Bus.base_access_cycles(m.bus, box.width, box.addr, box.access_kind)?
			io_delay_applied_machine = Machine.advance_to(m, m.now + cycles)?
			post_write_bus = match box.width {
				W8 => {
					if req_bios and cur_addr > 0x3FFF {
						io_delay_applied_machine.bus
					} else {
						io_delay_applied_machine.bus.write8(box.addr, box.val.to_u8_wrap())?
					}
				}
				W16 => {
					if req_bios and cur_addr > 0x3FFF {
						io_delay_applied_machine.bus
					} else {
						io_delay_applied_machine.bus.write16(box.addr, box.val.to_u16_wrap())?
					}
				}
				W32 => {
					if req_bios and cur_addr > 0x3FFF {
						io_delay_applied_machine.bus
					} else {
						io_delay_applied_machine.bus.write32(box.addr, box.val)?
					}
				}
			}
			cpu_continue = Cpu.resume_write(
				box.cpu,
				box.continuation,
			)?
			walk_execution_state(mark_fetch_nonsequential({ ..io_delay_applied_machine, bus: post_write_bus }), cpu_continue)
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

process_lcd_event : Machine, U64 -> Machine
process_lcd_event = |m, at| {
	if m.power_state == Stopped {
		m
	} else {
		# Hblank will be set every 1007, then for every 1232 it will jump to the next scanline
		match m.next_lcd_event {
			EnterHBlank => {
				(dp_rgs, mask) = DisplayRegs.enter_hblank(m.bus.io_regs.display)
				sys_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, mask)
				io_rgs = { ..m.bus.io_regs, display: dp_rgs, system: sys_rgs }
				new_bus = { ..m.bus, io_regs: io_rgs }
				{ ..m, bus: new_bus, next_lcd_event: NextScanline, next_lcd_at: at + 225 }
			}
			NextScanline => {
				(dp_rgs, mask) = DisplayRegs.advance_scanline(m.bus.io_regs.display)
				sys_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, mask)
				io_rgs = { ..m.bus.io_regs, display: dp_rgs, system: sys_rgs }
				new_bus = { ..m.bus, io_regs: io_rgs }
				{ ..m, bus: new_bus, next_lcd_event: EnterHBlank, next_lcd_at: at + 1007 }
			}
		}
	}
}

# Turns out ARM 7 of GBA is a 3 level pipeline
fetch_opcode : Machine, U32, [W16, W32], [NonSequential, Sequential] -> Try((Machine, FetchedCode), _)
fetch_opcode = |m, addr, width, req_kind| {
	bus_width : [W8, W16, W32] # All these just to calm down the compiler
	bus_width = match width {
		W16 => W16
		W32 => W32
	}
	if addr >= 0x4000 and addr < 0x100_0000 { # Unmapped reigon right after BIOS
		alignment = if (width == W16) 2 else 4
		if (addr.mod_by(alignment) != 0) return Err(MisalignedAddress(addr)) else {}
		advanced = Machine.advance_to(m, m.now + 1)?
		Ok((advanced, Unmapped(addr)))
	} else {
		cycles_needed = Bus.base_access_cycles(m.bus, bus_width, addr, req_kind)?
		advanced = Machine.advance_to(m, m.now + cycles_needed)?
		intermediate = match width {
			W16 => {
				inner = Bus.read16(advanced.bus, addr)?
				{ val: inner.val.to_u32(), state: inner.state }
			}
			W32 => Bus.read32(advanced.bus, addr)?
		}
		new_bus = match intermediate.state {
			Unchanged => advanced.bus
			Updated(x) => x # Again, sideeffect of reading
		}
		# Machine + opcode
		Ok(({ ..advanced, bus: new_bus }, Opcode(intermediate.val)))
	}
}

# Technically these funcs should be in Cpu
# As they are all Cpu pipelines....
reload_pipeline : Machine -> Try(Machine, _)
reload_pipeline = |m| {
	cur_pc = Cpu.getPC(m.cpu)
	(width, steps) = if (m.cpu.is_thumb()) (W16, 2.U32) else (W32, 4)
	(m_1stop_done, first) = fetch_opcode(m, cur_pc, width, NonSequential)?
	(m_2ndop_done, second) = fetch_opcode(m_1stop_done, cur_pc.plus_wrap(steps), width, Sequential)?
	Ok({
		..m_2ndop_done,
		pipeline: Ready({ first: first, second: second, access_kind: Sequential }),
	})
}

# Returns the opcode pointed by current PC &
# a new machine with the pipeline field refreshed
# CPU and its PC are unchanged
take_opcode : Machine -> Try((Machine, FetchedCode), _)
take_opcode = |m| {
	match m.pipeline {
		Empty => take_opcode(reload_pipeline(m)?)
		Ready(x) => {
			first = x.first
			second = x.second
			(next_addr, width) = if m.cpu.is_thumb() {
				(Cpu.getPC(m.cpu).plus_wrap(4), W16)
			} else {
				(Cpu.getPC(m.cpu).plus_wrap(8), W32)
			}
			(advanced, third) = fetch_opcode(m, next_addr, width, x.access_kind)?
			Ok((
				{
					..advanced,
					pipeline: Ready({
						first: second,
						second: third,
						access_kind: Sequential,
					}),
				},
				first,
			))
		}
	}
}

mark_fetch_nonsequential : Machine -> Machine
mark_fetch_nonsequential = |m| {
	match m.pipeline {
		Empty => m
		Ready(x) => {
			..m,
			pipeline: Ready({ ..x, access_kind: NonSequential }),
		}
	}
}

accept_pending_irq : Machine -> Try(Machine, _)
accept_pending_irq = |m| {
	# A IRQ will cause cpu to shift mode and update regs
	if SystemRegs.interrupt_req_fired(m.bus.io_regs.system)
		and !Bits.get_ith_bit_u32_certain(m.cpu.cpsr, 7) { # Cpu can block IRQ
		(advanced, _) = take_opcode(m)?
		irq_cpu = Cpu.handle_irq(advanced.cpu)?
		reload_pipeline({ ..advanced, cpu: irq_cpu })
	} else {
		Ok(m)
	}
}
