import Bits
import Bus
import BusSignals
import BusTypes
import Cpu
import CpuTypes
import ARM7TDMI
import Ppu
import SystemRegs
import DisplayRegs
import TimerRegs
import DmaRegs
import SoundRegs
import IoRegs
import KeyRegs
import Save
import SRAM
import EEPROM

Machine :: {
	bus : Bus,
	cpu : Cpu,
	ppu : Ppu,
	# Need to put unfinished Cpu IO status here when DMA hold the Bus
	power_state : [Running, Halted, Stopped],
	# DMA Channels with lower priority are paused until channels with higher priority have completed.
	dma_owner : [None, Channel(U8)],
	dma_used_gamepak : Bool,
	now : U64,
	next_lcd_at : U64,
	next_lcd_event : [EnterHBlank, NextScanline, VideoDMARequest],
	video_dma_running : Bool,
}.{
	init : List(U8), List(U8), Save -> Try(Machine, _)
	init = |bios, rom, save| {
		Ok({
			bus: Bus.init(bios, rom, save)?,
			cpu: Cpu.init(),
			ppu: Ppu.init(),
			power_state: Running,
			dma_owner: None,
			dma_used_gamepak: False,
			now: 0,
			next_lcd_at: 1007,
			next_lcd_event: EnterHBlank,
			video_dma_running: False,
		})
	}

	get_framebuffer : Machine -> List(U16)
	get_framebuffer = |m| Ppu.get_framebuffer(m.ppu)

	# Pretty much a visual debugging function, maybe can be used for screenshot support
	get_video_snapshot : Machine -> Try({ dispcnt : U16, vram : List(U8) }, _)
	get_video_snapshot = |m| {
		Ok({ dispcnt: DisplayRegs.read16(m.bus.io_regs.display, 0)?, vram: m.bus.vram })
	}

	get_time : Machine -> U64 # slop method
	get_time = |m| m.now

	get_cpu : Machine -> Cpu
	get_cpu = |m| m.cpu

	get_save : Machine -> Save
	get_save = |m| m.bus.save

	mark_saved : Machine, { time : U64, ecc : List(U8) } -> Machine
	mark_saved = |m, info| { ..m, bus: Bus.set_sram_info(m.bus, info) }

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
			process_event_at(m, at, timer_at)
		}
	}

	set_pressed : Machine, U16 -> Machine
	set_pressed = |m, pressed| {
		if m.power_state == Stopped {
			new_keys = KeyRegs.set_pressed(m.bus.io_regs.keys, pressed)
			if KeyRegs.can_key_irq(new_keys)
				and Bits.get_ith_bit_u16_certain(SystemRegs.get_interrupt_enables(m.bus.io_regs.system), 12) {
				{ ..m, bus: { ..m.bus, io_regs: { ..m.bus.io_regs, keys: new_keys } }, power_state: Running }
			} else {
				{ ..m, bus: { ..m.bus, io_regs: { ..m.bus.io_regs, keys: new_keys } } }
			}
		} else {
			updated = IoRegs.set_pressed(m.bus.io_regs, pressed)
			{ ..m, bus: { ..m.bus, io_regs: updated } }
		}
	}

	run_until : Machine,
	U64,
	U32 -> Try(
		{
			machine : Machine,
			reason : [ReachedTarget, BudgetExhausted, Stopped],
		},
		_,
	)
	run_until = |m, target, num_of_actions| {
		if m.now >= target {
			Ok({ machine: m, reason: ReachedTarget })
		} else if m.power_state == Stopped {
			Ok({ machine: m, reason: Stopped })
		} else if num_of_actions == 0 {
			Ok({ machine: m, reason: BudgetExhausted })
		} else if m.power_state == Halted {
			run_halted_until(m, target, num_of_actions)
		} else {
			res = run_cpu_chunk(m, At(target), num_of_actions)?
			run_until(
				res.machine,
				target,
				# Hmmm, no need to worry about hitting under zero due to all checks inside func
				num_of_actions.minus_wrap(res.actions_completed),
			)
		}
	}

	run_with_budget : Machine, U32 -> Try(Machine, _)
	run_with_budget = |m, num_of_actions| {
		if (num_of_actions == 0 or m.power_state == Stopped) return Ok(m)
		res = run_cpu_chunk(m, None, num_of_actions)?
		run_with_budget(res.machine, num_of_actions.minus_wrap(res.actions_completed))
	}

	step_forward : Machine -> Try(Machine, _)
	step_forward = |before_dma| {
		m = if no_dma(before_dma) {
			before_dma
		} else {
			return deal_with_dma(before_dma)
		}
		if m.power_state == Running {
			match m.cpu.suspended {
				None => {}
				Resume(e_state) => {
					early_ret_m = { ..m, cpu: { ..m.cpu, suspended: None } }
					return walk_execution_state(early_ret_m, Box.unbox(e_state))
				}
			}
			# accept pending irq?
			ready = if SystemRegs.interrupt_req_fired(m.bus.io_regs.system)
				and !Bits.get_ith_bit_u32_certain(m.cpu.hot.core.cpsr, 7) { # Cpu can block IRQ
				(advanced, _) = take_opcode(m)?
				irq_core = ARM7TDMI.handle_irq(advanced.cpu.hot.core)
				reload_pipeline({ ..advanced, cpu: { ..advanced.cpu, hot: { ..advanced.cpu.hot, core: irq_core } } })?
			} else {
				m
			}
			(fetched, code) = take_opcode(ready)?
			instruction = match code {
				Opcode(op) => op
				Unmapped(addr) => return Err(UnmappedInstructionFetch(addr))
			}
			execution_state = if fetched.cpu.hot.core.is_thumb() {
				ARM7TDMI.execute_thumb_opcode(fetched.cpu.hot.core, instruction.to_u16_wrap())?
			} else {
				ARM7TDMI.execute_arm_opcode(fetched.cpu.hot.core, instruction)?
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
			Err(CpuStopped)
		}
	}

	advance_to : Machine, U64 -> Try(Machine, _)
	advance_to = |m, target| advance_to_with(m, target, |advanced| Ok(advanced))

}

run_halted_until : Machine,
U64,
U32 -> Try(
	{
		machine : Machine,
		reason : [ReachedTarget, BudgetExhausted, Stopped],
	},
	_,
)
run_halted_until = |m, target, num_of_actions| {
	if (m.power_state != Halted or m.now >= target or num_of_actions == 0) return Machine.run_until(m, target, num_of_actions)
	if num_of_actions < 2 or m.dma_owner != None or SystemRegs.enable_pending(m.bus.io_regs.system) != 0 {
		return run_halted_until(run_one_action(m)?, target, num_of_actions - 1)
	}
	first = match TimerRegs.next_event_at(m.bus.io_regs.timers) {
		None => return run_halted_until(run_one_action(m)?, target, num_of_actions - 1)
		At(t) => t
	}
	if (first <= m.now or first >= m.next_lcd_at or first > target or first > U64.highest - 2) return run_halted_until(run_one_action(m)?, target, num_of_actions - 1)
	# Ordinary ticks schedule pending DMA at the FIRST tick.
	# Query that deadline here; advance_to performs the actual update.
	scheduled = DmaRegs.schedule_pending(m.bus.io_regs.dmas, first)
	lcd_limit = target.min(m.next_lcd_at - 1)
	limit = match DmaRegs.next_ready_at(scheduled) {
		# No DMA -> Just focus on lcd
		None => lcd_limit
		# DMA is a thing but later than timer events
		At(dma_at) if dma_at > first => lcd_limit.min(dma_at - 1)
		_ => return run_halted_until(run_one_action(m)?, target, num_of_actions - 1)
	}
	match TimerRegs.halt_batch_span(m.bus.io_regs.timers, limit, num_of_actions) {
		NoBatch => run_halted_until(run_one_action(m)?, target, num_of_actions - 1)
		Batch(span) => {
			advanced = Machine.advance_to(m, span.last_at)?
			run_halted_until(advanced, target, num_of_actions - span.actions)
		}
	}
}

run_one_action : Machine -> Try(Machine, _)
run_one_action = |m| {
	match m.power_state {
		Running => Machine.step_forward(m)
		Halted if SystemRegs.enable_pending(m.bus.io_regs.system) != 0 => Machine.step_forward(m)
		Halted => {
			after_dma = if (no_dma(m)) m else return deal_with_dma(m)
			closest_next = next_cpu_event_at(after_dma)
			Machine.advance_to(after_dma, closest_next)
		}
		Stopped => Ok(m)
	}
}

commit_cpu_state : Machine, CpuTypes.RunState -> Try(Machine, _)
commit_cpu_state = |m, rs| {
	advance_to_with(
		m,
		rs.now,
		|advanced| {
			Ok({
				..advanced,
				cpu: { ..advanced.cpu, hot: rs.hot },
				bus: { ..advanced.bus, signal: rs.signal },
			})
		},
	)
}

run_cpu_chunk : Machine, [None, At(U64)], U32 -> Try({ machine : Machine, actions_completed : U32 }, _)
run_cpu_chunk = |m, target_time, action_budget| {
	closest_next = next_cpu_block_event_at(m)
	# Boxing make comp a torture
	if (
		m.power_state != Running or !no_dma(m) or closest_next <= m.now or closest_next.minus_wrap(m.now) == 1
			or match m.cpu.suspended {
				None => False
				Resume(_) => True
			}
	) return Ok({ machine: run_one_action(m)?, actions_completed: 1 })
	state = { hot: m.cpu.hot, now: m.now, signal: m.bus.signal }
	limits = {
		event_at: closest_next,
		target: target_time,
		budget: action_budget,
		schedule_dma: DmaRegs.has_unscheduled(m.bus.io_regs.dmas),
	}
	irq_asserted = SystemRegs.interrupt_req_fired(m.bus.io_regs.system)
	(cold_bus, memory_view) = Bus.take_memory_view(m.bus)
	cold_machine = { ..m, bus: cold_bus }
	finish_cpu_chunk(cold_machine, Cpu.run_block(memory_view, state, limits, irq_asserted))
}

finish_cpu_chunk : Machine, Try(CpuTypes.BlockResult, _) -> Try({ machine : Machine, actions_completed : U32 }, _)
finish_cpu_chunk = |cold_machine, brs| {
	match brs {
		Err(e) => Err(e)
		Ok(block_res) => commit_cpu_chunk(cold_machine, block_res)
	}
}

commit_cpu_chunk : Machine, CpuTypes.BlockResult -> Try({ machine : Machine, actions_completed : U32 }, _)
commit_cpu_chunk = |cold_machine, block_res| {
	reheated_bus = Bus.restore_memory_view((cold_machine.bus, block_res.memory))
	events_updated_bus = match block_res.dma_schedule_at {
		None => reheated_bus
		At(write_at) => {
			timer_nxt_event = TimerRegs.next_event_at(reheated_bus.io_regs.timers)
			schedule_at = match timer_nxt_event {
				None => write_at
				At(timer_at) => write_at.min(timer_at)
			}
			{
				..reheated_bus,
				io_regs: {
					..reheated_bus.io_regs,
					dmas: DmaRegs.schedule_pending(reheated_bus.io_regs.dmas, schedule_at),
				},
			}
		}
	}
	commited = commit_cpu_state({ ..cold_machine, bus: events_updated_bus }, block_res.state)?
	match block_res.exit {
		Boundary(ReachedTarget) | Boundary(BudgetExhausted) =>
			Ok({ machine: commited, actions_completed: block_res.actions_completed })
		Boundary(NeedsSlow) => Ok({
			machine: run_one_action(commited)?,
			actions_completed: block_res.actions_completed.plus_wrap(1),
		})
		Pending(exec) => Ok({
			machine: walk_execution_state(commited, exec)?,
			actions_completed: block_res.actions_completed.plus_wrap(1),
		})
	}
}

# Have to cut of the OG big recursive func into several pieces
# Just for better perf and less memcpy
walk_execution_state : Machine, ARM7TDMI.Execution_state -> Try(Machine, _)
walk_execution_state = |m, state| {
	match state {
		Complete(outcome) => complete_execution(m, outcome)
		_ => walk_memory_execution_state(m, state)
	}
}

walk_memory_execution_state : Machine, ARM7TDMI.Execution_state -> Try(Machine, _)
walk_memory_execution_state = |before_dma, state| {
	# Here comes DMA IO 'interruption',
	# It can occupy the bus in the middle of IO under some scenarios
	can_yield : ARM7TDMI.Execution_state -> Bool
	can_yield = |e_state| {
		match e_state {
			R(_) => True # Well IO hasnt start so yes
			W({ continuation: StoreAndFinish(_), .. }) => True
			W({ continuation: WriteMultiple(_), .. }) => True
			W({ continuation: SetRegAndFinish(_), .. }) => False # SWP/SWPB, should be atomic
			Complete(_) => False
		}
	}
	m = if can_yield(state) {
		if no_dma(before_dma) {
			before_dma
		} else {
			after_dma = deal_with_dma(before_dma)?
			resume_state = match state {
				R(request) => R({ ..request, access_kind: NonSequential })
				W(request) => W({ ..request, access_kind: NonSequential })
				# No way we reach this after can_yield()?
				Complete(_) => return Err(WTFisThis)
			}
			# Well DMA rush out first, so we gotta early return
			return Ok({
				..after_dma,
				cpu: { ..after_dma.cpu, suspended: Resume(Box.box(resume_state)) },
			})
		}
	} else {
		before_dma
	}
	match state {
		Complete(outcome) => complete_execution(m, outcome)
		R(request) => {
			cycles = Bus.base_access_cycles(m.bus, request.width, request.addr, request.access_kind)
			plan = Cpu.plan_cpu_data_access_fields(
				m.cpu.hot.gamepak_prefetch,
				SystemRegs.get_waitcnt(m.bus.io_regs.system),
				ARM7TDMI.getPC(m.cpu.hot.core),
				request.addr,
				cycles,
			)
			io_delay_applied_machine = Machine.advance_to(m, m.now + plan.cycles)?
			cxt = Cpu.data_read_context(
				request.core,
				io_delay_applied_machine.cpu.hot.pipeline,
				io_delay_applied_machine.bus.signal,
			)
			intermediate = match request.width {
				W8 => {
					inner = io_delay_applied_machine.bus.read8(request.addr, cxt)?
					{ val: inner.val.to_u32(), state: inner.state, signal: inner.signal }
				}
				W16 => {
					inner = io_delay_applied_machine.bus.read16(request.addr, CpuData, cxt)?
					{ val: inner.val.to_u32(), state: inner.state, signal: inner.signal }
				}
				W32 => io_delay_applied_machine.bus.read32(request.addr, CpuData, cxt)?
			}
			raw_val = intermediate.val
			new_bus = match intermediate.state {
				Unchanged => { ..io_delay_applied_machine.bus, signal: intermediate.signal }
				Updated(x) => { ..Box.unbox(x), signal: intermediate.signal }
			}
			next_execution = ARM7TDMI.resume_read(
				request.core,
				raw_val,
				request.continuation,
			)?

			# The plan uses the FIFO state from the start of the read
			# As reads succeeds, put planned FIFO state to the machine returned by advance_to
			cpu_after_wait = io_delay_applied_machine.cpu
			next_cpu = { ..cpu_after_wait, hot: { ..cpu_after_wait.hot, gamepak_prefetch: plan.next_prefetch } }
			walk_memory_execution_state(
				mark_fetch_nonsequential({ ..io_delay_applied_machine, bus: new_bus, cpu: next_cpu }),
				next_execution,
			)
		}
		W(request) => {
			cur_addr = ARM7TDMI.getPC(m.cpu.hot.core)
			req_bios = Bus.requires_bios(request.width, request.addr)
			cycles = Bus.base_access_cycles(m.bus, request.width, request.addr, request.access_kind)
			plan = Cpu.plan_cpu_data_access_fields(
				m.cpu.hot.gamepak_prefetch,
				SystemRegs.get_waitcnt(m.bus.io_regs.system),
				ARM7TDMI.getPC(m.cpu.hot.core),
				request.addr,
				cycles,
			)
			io_delay_applied_machine = Machine.advance_to(m, m.now + plan.cycles)?

			before_waitcnt = SystemRegs.get_waitcnt(io_delay_applied_machine.bus.io_regs.system)
			post_write_bus = if req_bios and cur_addr > 0x3FFF {
				io_delay_applied_machine.bus
			} else {
				match request.width {
					W8 => io_delay_applied_machine.bus.write8(request.addr, request.val.to_u8_wrap())?
					W16 => io_delay_applied_machine.bus.write16(request.addr, request.addr_low, request.val.to_u16_wrap(), CpuData)?
					W32 => io_delay_applied_machine.bus.write32(request.addr, request.addr_low, request.val, CpuData)?
				}
			}
			scheduled_dma_rgs = DmaRegs.schedule_pending(post_write_bus.io_regs.dmas, io_delay_applied_machine.now)
			final_bus = { ..post_write_bus, io_regs: { ..post_write_bus.io_regs, dmas: scheduled_dma_rgs } }
			next_execution = ARM7TDMI.resume_write(
				request.core,
				request.continuation,
			)?

			cpu_after_wait = io_delay_applied_machine.cpu
			next_prefetch = note_prefetch_turned_off(
				plan.next_prefetch,
				before_waitcnt,
				SystemRegs.get_waitcnt(final_bus.io_regs.system),
			)
			next_cpu = { ..cpu_after_wait, hot: { ..cpu_after_wait.hot, gamepak_prefetch: next_prefetch } }
			walk_memory_execution_state(
				mark_fetch_nonsequential({ ..io_delay_applied_machine, bus: final_bus, cpu: next_cpu }),
				next_execution,
			)
		}
	}
}

# So, DMA owning the bus and CPU computation can go on at the same time
# end_at fixed as time spent in DMA also counts toward those cycles
# Cannot believe I missed this
advance_cpu_internal_until : Machine, U64 -> Try(Machine, _)
advance_cpu_internal_until = |m, end_at| {
	if (m.now >= end_at or m.power_state == Stopped) return Ok(m)
	if (!no_dma(m)) return advance_cpu_internal_until(deal_with_dma(m)?, end_at)
	next_at = next_cpu_event_at(m)
	if (end_at <= next_at) return advance_dma_cart_idle(m, end_at - m.now)
	advance_cpu_internal_until(advance_dma_cart_idle(m, next_at - m.now)?, end_at)
}

complete_execution : Machine, ARM7TDMI.Execution_outcome -> Try(Machine, _)
complete_execution = |m, outcome| {
	cycle_consumed_machine =
		if (outcome.remaining_cycles == 0) m else advance_cpu_internal_until(m, m.now + outcome.remaining_cycles)?
	completed = if outcome.remaining_cycles > 0 {
		mark_fetch_nonsequential({
			..cycle_consumed_machine,
			cpu: {
				..cycle_consumed_machine.cpu,
				hot: {
					..cycle_consumed_machine.cpu.hot,
					core: outcome.core,
				},
			},
		})
	} else {
		{
			..cycle_consumed_machine,
			cpu: {
				..cycle_consumed_machine.cpu,
				hot: { ..cycle_consumed_machine.cpu.hot, core: outcome.core },
			},
		}
	}
	pipeline_side_effect_considered = match outcome.pc_status {
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
		bus: new_bus,
		power_state: match req {
			NoReq => pipeline_side_effect_considered.power_state
			Request(x) => if x.bitwise_and(0b1000_0000) == 0 {
				Halted
			} else {
				if (KeyRegs.can_key_irq(new_ioregs.keys)
					and Bits.get_ith_bit_u16_certain(SystemRegs.get_interrupt_enables(new_ioregs.system), 12)) Running else Stopped
			}
		},
	})
}

process_event_at : Machine, U64, [None, At(U64)] -> Try((Machine, U8), _)
process_event_at = |m, at, timer_at| {
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
							timers: TimerRegs.sync_idle_to_known_next(
								$cur_machine.bus.io_regs.timers,
								at,
								timer_at,
							)?,
						},
					},
				},
				0,
			)
		}
		# LCD processing
		if $cur_machine.next_lcd_at == at {
			after_lcd = process_lcd_event($cur_machine, at)?
			$cur_machine = after_lcd
		} else {} # No need to touch lcd as its not triggered yet.
		# So the new at will either be the (now previous) next_lcd_at update timestamp
		# or the next timer reg event time, or both, since it is determined by a min
		Ok(({ ..$cur_machine, now: at }, $overflow_mask))
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
				(new_sound_rgs, fifo_requests) = SoundRegs.on_timer_overflow(m.bus.io_regs.sound, masks.overflow_mask)?
				new_system_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, masks.irq_mask)
				new_dmas = DmaRegs.schedule_pending(DmaRegs.trigger_fifo(m.bus.io_regs.dmas, fifo_requests), at)
				Ok((
					{
						..m,
						bus: {
							..m.bus,
							io_regs: { ..m.bus.io_regs, timers: new_timers_rgs, system: new_system_rgs, sound: new_sound_rgs, dmas: new_dmas },
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

process_lcd_event : Machine, U64 -> Try(Machine, _)
process_lcd_event = |m, at| {
	if m.power_state == Stopped {
		Ok(m)
	} else {
		# Hblank will be set every 1007, then for every 1232 it will jump to the next scanline
		match m.next_lcd_event {
			EnterHBlank => {
				(dp_rgs, mask) = DisplayRegs.enter_hblank(m.bus.io_regs.display)
				new_vcount = DisplayRegs.get_vcount(dp_rgs)
				(new_dmas, new_ppu) = if new_vcount < 160 {
					affine_bg2 = DisplayRegs.get_bg2_affine(m.bus.io_regs.display)
					ref_bg2 = DisplayRegs.get_bg2_internal_reference(m.bus.io_regs.display)
					affine_bg3 = DisplayRegs.get_bg3_affine(m.bus.io_regs.display)
					ref_bg3 = DisplayRegs.get_bg3_internal_reference(m.bus.io_regs.display)
					(
						DmaRegs.schedule_pending(DmaRegs.trigger_blank(m.bus.io_regs.dmas, HBlank), at),
						Ppu.render_scanline(
							m.ppu,
							DisplayRegs.read16(m.bus.io_regs.display, 0)?,
							m.bus.vram,
							m.bus.paletteram,
							new_vcount.to_u64(),
							DisplayRegs.get_text_bgs(m.bus.io_regs.display),
							{ pa: affine_bg2.pa, pb: affine_bg2.pb, pc: affine_bg2.pc, pd: affine_bg2.pd, x: ref_bg2.x, y: ref_bg2.y },
							{ pa: affine_bg3.pa, pb: affine_bg3.pb, pc: affine_bg3.pc, pd: affine_bg3.pd, x: ref_bg3.x, y: ref_bg3.y },
							m.bus.oam,
							DisplayRegs.get_windows(m.bus.io_regs.display),
							DisplayRegs.get_mosaic(m.bus.io_regs.display),
							DisplayRegs.get_color_effects(m.bus.io_regs.display),
						)?,
					)
				} else {
					(m.bus.io_regs.dmas, m.ppu)
				}
				sys_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, mask)
				io_rgs = { ..m.bus.io_regs, display: dp_rgs, system: sys_rgs, dmas: new_dmas }
				new_bus = { ..m.bus, io_regs: io_rgs }
				Ok({ ..m, ppu: new_ppu, bus: new_bus, next_lcd_event: NextScanline, next_lcd_at: at + 225 })
			}
			NextScanline => {
				(dp_rgs, mask) = DisplayRegs.advance_scanline(m.bus.io_regs.display)
				new_vcount = DisplayRegs.get_vcount(dp_rgs)
				new_vid_dma_running = if (new_vcount == 163) DmaRegs.has_video_dma(m.bus.io_regs.dmas) else m.video_dma_running
				new_dmas = if new_vcount == 160 {
					DmaRegs.schedule_pending(DmaRegs.trigger_blank(m.bus.io_regs.dmas, VBlank), at)
				} else if new_vcount == 162 and new_vid_dma_running {
					DmaRegs.stop_video_dma(m.bus.io_regs.dmas)
				} else {
					m.bus.io_regs.dmas
				}
				sys_rgs = SystemRegs.hardware_request_interrupts(m.bus.io_regs.system, mask)
				io_rgs = { ..m.bus.io_regs, display: dp_rgs, system: sys_rgs, dmas: new_dmas }
				new_bus = { ..m.bus, io_regs: io_rgs }
				video_dma_next = new_vid_dma_running and new_vcount < 162 and new_vcount > 1
				Ok({
					..m,
					bus: new_bus,
					next_lcd_event: if (video_dma_next) VideoDMARequest else EnterHBlank,
					next_lcd_at: if (video_dma_next) at + 3 else at + 1007,
					video_dma_running: new_vid_dma_running,
				})
			}
			VideoDMARequest => {
				new_dmas = DmaRegs.schedule_pending(DmaRegs.trigger_video(m.bus.io_regs.dmas), at)
				io_rgs = { ..m.bus.io_regs, dmas: new_dmas }
				new_bus = { ..m.bus, io_regs: io_rgs }
				# Hblank is next
				Ok({ ..m, bus: new_bus, next_lcd_event: EnterHBlank, next_lcd_at: at + 1004 })
			}
		}
	}
}

next_cpu_event_at : Machine -> U64
next_cpu_event_at = |m| {
	next_lcd_time = m.next_lcd_at
	next_timer_time = TimerRegs.next_event_at(m.bus.io_regs.timers)
	next_dma_time = DmaRegs.next_ready_at(m.bus.io_regs.dmas)
	match (next_timer_time, next_dma_time) {
		(None, None) => next_lcd_time
		(At(t), None) | (None, At(t)) => next_lcd_time.min(t)
		(At(x), At(y)) => next_lcd_time.min(x).min(y)
	}
}

next_cpu_block_event_at : Machine -> U64
next_cpu_block_event_at = |m| {
	nxt_cpu_event_time = next_cpu_event_at(m)
	if (nxt_cpu_event_time <= m.now) return nxt_cpu_event_time
	fallback_at = TimerRegs.next_event_at(m.bus.io_regs.timers)
	next_dma_time = match fallback_at {
		None => DmaRegs.next_ready_at(m.bus.io_regs.dmas)
		At(t) => {
			if (t > U64.highest - 2) return nxt_cpu_event_time
			DmaRegs.next_ready_at(DmaRegs.schedule_pending(m.bus.io_regs.dmas, t))
		}
	}
	match earlier_event(next_dma_time, TimerRegs.next_batch_boundary_at(m.bus.io_regs.timers)) {
		At(t) => m.next_lcd_at.min(t)
		None => m.next_lcd_at
	}
}

earlier_event : [None, At(U64)], [None, At(U64)] -> [None, At(U64)]
earlier_event = |t1, t2| {
	match (t1, t2) {
		(None, None) => None
		(None, At(t)) | (At(t), None) => At(t)
		(At(x), At(y)) => At(x.min(y))
	}
}

timed_read : Machine, BusTypes.HalfOrWord, U32, [NonSequential, Sequential], Bus.ReadPurpose -> Try((Machine, U32), _)
timed_read = |m, width, addr, req_kind, purpose| {
	# Should be handled by walk_memory_execution_state() rather than here.
	if (purpose == CpuData) return Err(MissingCpuReadContext)
	bus_width = BusTypes.to_bus_width(width)
	cart_fetch = purpose == Fetch and addr >= 0x8000000 and addr < 0xE000000
	plan = if cart_fetch {
		waitcnt = SystemRegs.get_waitcnt(m.bus.io_regs.system)
		match width {
			W16 => Cpu.plan_fetch16_fields(m.cpu.hot.gamepak_prefetch, waitcnt, addr, req_kind)
			W32 => Cpu.plan_fetch32_fields(m.cpu.hot.gamepak_prefetch, waitcnt, addr, req_kind)
		}
	} else {
		base = Bus.base_access_cycles(m.bus, bus_width, addr, req_kind)
		f = m.cpu.hot.gamepak_prefetch
		match purpose {
			# DMA addr -> Bus conflict with prefetch?
			# Cpu PC -> if stops rn does it have extra cycle cost? @NBA
			Dma(_) => Cpu.plan_cpu_data_access_fields(
				f,
				SystemRegs.get_waitcnt(m.bus.io_regs.system),
				ARM7TDMI.getPC(m.cpu.hot.core),
				addr,
				base,
			)
			_ => { cycles: base, next_prefetch: f }
		}
	}
	advance_to_with(
		m,
		m.now + plan.cycles,
		|advanced| {
			latch = BusSignals.get_bios_latch(advanced.bus.signal)
			cxt = {
				open_bus: match purpose {
					Dma(_) => Value(DmaRegs.get_open_bus_latch(advanced.bus.io_regs.dmas))
					_ => None # Normal CpuData read never pass through this func
				},
				bios_latch: latch,
				bios_readable: purpose == Fetch and addr < 0x4000,
			}
			cpu = { ..advanced.cpu, hot: { ..advanced.cpu.hot, gamepak_prefetch: plan.next_prefetch } }
			intermediate = match width {
				W16 => {
					inner = Bus.read16(advanced.bus, addr, purpose, cxt)?
					{ val: inner.val.to_u32(), state: inner.state, signal: inner.signal }
				}
				W32 => Bus.read32(advanced.bus, addr, purpose, cxt)?
			}
			match intermediate.state {
				Unchanged => Ok((
					{ ..advanced, cpu, bus: { ..advanced.bus, signal: intermediate.signal } },
					intermediate.val,
				))
				Updated(x) => Ok((
					{ ..advanced, cpu, bus: { ..Box.unbox(x), signal: intermediate.signal } },
					intermediate.val,
				)) # Again, side effect of reading
			}
		},
	)
}

# During these DMA cycles:
# 1. Dma is working without touching GAMEPAK
# 2. Prefetcher of PAK can fill its FIFO during those same cycles
advance_dma_cart_idle : Machine, U64 -> Try(Machine, _)
advance_dma_cart_idle = |m, cycles| {
	advanced_pref =
		Cpu.advance_prefetch_fields(m.cpu.hot.gamepak_prefetch, SystemRegs.get_waitcnt(m.bus.io_regs.system), cycles)
	advanced = Machine.advance_to(m, m.now + cycles)?
	hot = { ..advanced.cpu.hot, gamepak_prefetch: advanced_pref }
	Ok({ ..advanced, cpu: { ..advanced.cpu, hot } })
}

dma_read : Machine, BusTypes.HalfOrWord, U32, [NonSequential, Sequential], Bus.ReadPurpose -> Try((Machine, U32), _)
dma_read = |m, width, addr, req_kind, purpose| {
	aligned_addr = if (width == W16) addr.bitwise_and(0xFFFFFFFE) else addr.bitwise_and(0xFFFFFFFC)
	timed_read(m, width, aligned_addr, req_kind, purpose) # Machine + read val
}

timed_write : Machine, BusTypes.HalfOrWord, U32, U32, [NonSequential, Sequential], Bus.WritePurpose -> Try(Machine, _)
timed_write = |m, width, addr, val, req_kind, purpose| {
	bus_width = BusTypes.to_bus_width(width)
	cycles_needed = Bus.base_access_cycles(m.bus, bus_width, addr, req_kind)
	advanced = Machine.advance_to(m, m.now + cycles_needed)?
	new_bus = match width {
		W16 => Bus.write16(advanced.bus, addr, 0, val.to_u16_wrap(), purpose)?
		W32 => Bus.write32(advanced.bus, addr, 0, val, purpose)?
	}
	new_dma_rgs = DmaRegs.schedule_pending(new_bus.io_regs.dmas, advanced.now)
	Ok({ ..advanced, bus: { ..new_bus, io_regs: { ..new_bus.io_regs, dmas: new_dma_rgs } } })
}

# Write one DMA unit and complete it using the post-write register state, saves RC and memcpy :)
finish_dma_write : Machine, BusTypes.HalfOrWord, U32, U32, [NonSequential, Sequential], U8 -> Try(Machine, _)
finish_dma_write = |m, width, addr, val, req_kind, selection| {
	aligned_addr = if (width == W16) addr.bitwise_and(0xFFFFFFFE) else addr.bitwise_and(0xFFFFFFFC)
	bus_width = BusTypes.to_bus_width(width)
	cycles_needed = Bus.base_access_cycles(m.bus, bus_width, aligned_addr, req_kind)
	f = m.cpu.hot.gamepak_prefetch
	waitcnt = SystemRegs.get_waitcnt(m.bus.io_regs.system)
	# Source read done, plan the write using the FIFO state it left behind
	# addr < 0x2000000 -> game pak free
	plan = if aligned_addr < 0x2000000 {
		{ cycles: cycles_needed, next_prefetch: Cpu.advance_prefetch_fields(f, waitcnt, cycles_needed) }
	} else {
		Cpu.plan_cpu_data_access_fields(f, waitcnt, ARM7TDMI.getPC(m.cpu.hot.core), aligned_addr, cycles_needed)
	}
	advance_to_with(
		m,
		m.now + plan.cycles,
		|advanced| {
			before_waitcnt = SystemRegs.get_waitcnt(advanced.bus.io_regs.system)
			new_bus = match width {
				W16 => Bus.write16(advanced.bus, aligned_addr, 0, val.to_u16_wrap(), Dma(selection))?
				W32 => Bus.write32(advanced.bus, aligned_addr, 0, val, Dma(selection))?
			}
			scheduled_dma_rgs = DmaRegs.schedule_pending(new_bus.io_regs.dmas, advanced.now)
			(new_dma_rgs, irq_mask) = DmaRegs.complete_unit(scheduled_dma_rgs, selection)?
			new_sys_rgs = SystemRegs.hardware_request_interrupts(new_bus.io_regs.system, irq_mask)

			next_prefetch = note_prefetch_turned_off(
				plan.next_prefetch,
				before_waitcnt,
				SystemRegs.get_waitcnt(new_sys_rgs),
			)
			Ok({
				..advanced,
				dma_owner: Channel(selection),
				bus: {
					..new_bus,
					io_regs: {
						..new_bus.io_regs,
						dmas: new_dma_rgs,
						system: new_sys_rgs,
					},
				},
				cpu: { ..advanced.cpu, hot: { ..advanced.cpu.hot, gamepak_prefetch: next_prefetch } },
			})
		},
	)
}

dma_transfer_selected : Machine, U8, DmaRegs.Reg, BusTypes.HalfOrWord, [NonSequential, Sequential], [NonSequential, Sequential] -> Try(Machine, _)
dma_transfer_selected = |m, selection, reg, width, req_read_kind, req_write_kind| {
	DmaRegs.validate_transfer(reg, selection, Starting)?
	(after_read_m, val) = if reg.source_addr < 0x2000000 {
		# Trying to read BIOS/Unused zone? Kind UB
		# Luckily NBA tells us how to handle it.
		advanced = advance_dma_cart_idle(m, 1)?
		latch_val = if width == W32 {
			reg.data_latch
		} else {
			# Yes, bit1. Since if we use bit0 -> aligned by 8bit not 16
			if reg.dest_addr.bitwise_and(0b10) == 0 {
				Bits.get_seg_of_u32_certain(reg.data_latch, 0, 16)
			} else {
				Bits.get_seg_of_u32_certain(reg.data_latch, 16, 16)
			}
		}
		(advanced, latch_val)
	} else {
		(intermediate_m, before_latch_val) = dma_read(m, width, reg.source_addr, req_read_kind, Dma(selection))?
		val_with_width_considered = if (width == W32) before_latch_val else (before_latch_val.shl_wrap(16) + before_latch_val)
		(
			{
				..intermediate_m,
				bus: {
					..intermediate_m.bus,
					io_regs: {
						..intermediate_m.bus.io_regs,
						dmas: DmaRegs.set_data_latch(
							intermediate_m.bus.io_regs.dmas,
							selection,
							val_with_width_considered,
						)?,
					},
				},
			},
			val_with_width_considered,
		)
	}
	finish_dma_write(
		if reg.first_unit and width == W16 {
			{ ..after_read_m, bus: Bus.hint_eeprom_size(after_read_m.bus, reg.dest_addr, reg.remaining) }
		} else {
			after_read_m
		},
		width,
		reg.dest_addr,
		val,
		req_write_kind,
		selection,
	)
}

dma_transfer_unit : Machine, [NonSequential, Sequential], [NonSequential, Sequential] -> Try(Machine, _)
dma_transfer_unit = |m, req_read_kind, req_write_kind| {
	if m.power_state == Stopped {
		Ok(m)
	} else {
		match DmaRegs.get_reg_ready_to_io(m.bus.io_regs.dmas, m.now) {
			None => Ok(m) # Congrats, you got nothing to do as of now
			Transfer(selection, reg, width) => dma_transfer_selected(
				m,
				selection,
				reg,
				width,
				req_read_kind,
				req_write_kind,
			)
		}
	}
}

# ⠀⣞⢽⢪⢣⢣⢣⢫⡺⡵⣝⡮⣗⢷⢽⢽⢽⣮⡷⡽⣜⣜⢮⢺⣜⢷⢽⢝⡽⣝
# ⠸⡸⠜⠕⠕⠁⢁⢇⢏⢽⢺⣪⡳⡝⣎⣏⢯⢞⡿⣟⣷⣳⢯⡷⣽⢽⢯⣳⣫⠇
#  ⢀⢀⢄⢬⢪⡪⡎⣆⡈⠚⠜⠕⠇⠗⠝⢕⢯⢫⣞⣯⣿⣻⡽⣏⢗⣗⠏
# ⠪⡪⡪⣪⢪⢺⢸⢢⢓⢆⢤⢀⠀⠀⠀⠀⠈⢊⢞⡾⣿⡯⣏⢮⠷⠁
#  ⠀⠈⠊⠆⡃⠕⢕⢇⢇⢇⢇⢇⢏⢎⢎⢆⢄⠀⢑⣽⣿⢝⠲⠉
#  ⠀⠀⠀⠀ ⡿⠂⠠⠀⡇⢇⠕⢈⣀⠀⠁⠡⠣⡣⡫⣂⣿⠯⢪⠰⠂
#  ⠀⠀⠀ ⡦⡙⡂⢀⢤⢣⠣⡈⣾⡃⠠⠄⠀⡄⢱⣌⣶⢏⢊⠂
#  ⠀⠀⠀ ⢝⡲⣜⡮⡏⢎⢌⢂⠙⠢⠐⢀⢘⢵⣽⣿⡿⠁⠁
#  ⠀⠀⠀⠀⠨⣺⡺⡕⡕⡱⡑⡆⡕⡅⡕⡜⡼⢽⡻⠏
#       ⣼⣳⣫⣾⣵⣗⡵⡱⡡⢣⢑⢕⢜⢕⡝
#      ⣴⣿⣾⣿⣿⣿⡿⡽⡑⢌⠪⡢⡣⣣⡟
#      ⡟⡾⣿⢿⢿⢵⣽⣾⣼⣘⢸⢸⣞⡟
#       ⠁⠇⠡⠩⡫⢿⣝⡻⡮⣒⢽⠋⠀⠀⠀⠀
no_dma : Machine -> Bool
no_dma = |m| (m.power_state == Stopped or
	(!DmaRegs.has_ready(m.bus.io_regs.dmas, m.now)
		and m.dma_owner == None))

deal_with_dma : Machine -> Try(Machine, _)
deal_with_dma = |m| {
	release_dma : Machine -> Try(Machine, _)
	release_dma = |m_in| Ok(mark_fetch_nonsequential({ ..advance_dma_cart_idle(m_in, 1)?, dma_owner: None }))
	match DmaRegs.get_reg_ready_to_io(m.bus.io_regs.dmas, m.now) {
		None => {
			match m.dma_owner {
				None => Err(CallNoDMAFirstPlease) # Technically should not be triggered after no_dma
				Channel(_) => {
					# No ready to IO DMA yet channel is filled -> Should be freed
					release_dma(m)
				}
			}
		}
		Transfer(selection, reg, _) => {
			prior = m.dma_owner
			DmaRegs.validate_transfer(reg, selection, Starting)?
			advanced = if (prior == None) advance_dma_cart_idle(m, 1)? else m
			match DmaRegs.get_reg_ready_to_io(advanced.bus.io_regs.dmas, advanced.now) {
				Transfer(next_selection, next_reg, next_width) => {
					access_kind = if (prior == Channel(next_selection)) Sequential else NonSequential
					src_on_gamepak = next_reg.source_addr >= 0x8000000
					dest_on_gamepak = next_reg.dest_addr >= 0x8000000
					# Stolen from NBA, only the first Game Pak access in an uninterrupted DMA run requests N
					# Source reads first, so Game Pak -> Pak is N, S
					did_access_rom = access_kind == Sequential and !next_reg.first_unit and advanced.dma_used_gamepak
					read_kind =
						if (!did_access_rom and src_on_gamepak) NonSequential else Sequential
					write_kind =
						if (!did_access_rom and !src_on_gamepak and dest_on_gamepak) NonSequential else Sequential
					ready = { ..advanced, dma_used_gamepak: did_access_rom or src_on_gamepak or dest_on_gamepak }
					dma_transfer_selected(ready, next_selection, next_reg, next_width, read_kind, write_kind)
				}
				None => {
					# Well this can occur now, like this:
					# DMA3 pending -> vcount advance, DMA3 disabled because vcount == 162
					# selection is None now, ooof
					release_dma(advanced)
				}
			}
		}
	}
}

# Turns out ARM 7 of GBA is a 3 level pipeline
fetch_opcode : Machine, U32, BusTypes.HalfOrWord, [NonSequential, Sequential] -> Try((Machine, CpuTypes.FetchedCode), _)
fetch_opcode = |m, addr, width, req_kind| {
	if addr >= 0x4000 and addr < 0x100_0000 { # Unmapped reigon right after BIOS
		alignment = if (width == W16) 2 else 4
		if (addr.mod_by(alignment) != 0) return Err(MisalignedAddress(addr)) else {}
		advanced = Machine.advance_to(m, m.now + 1)?
		Ok((advanced, Unmapped(addr)))
	} else {
		(resultant_machine, returned_code) = timed_read(m, width, addr, req_kind, Fetch)?
		# Machine + opcode
		Ok((resultant_machine, Opcode(returned_code)))
	}
}

# Technically these funcs should be in Cpu
# As they are all Cpu pipelines....
reload_pipeline : Machine -> Try(Machine, _)
reload_pipeline = |m| {
	cur_pc = ARM7TDMI.getPC(m.cpu.hot.core)
	(width, steps) = if (m.cpu.hot.core.is_thumb()) (W16, 2.U32) else (W32, 4)
	(m_1stop_done, first) = fetch_opcode(m, cur_pc, width, NonSequential)?
	(m_2ndop_done, second) = fetch_opcode(m_1stop_done, cur_pc.plus_wrap(steps), width, Sequential)?
	Ok({
		..m_2ndop_done,
		cpu: {
			..m_2ndop_done.cpu,
			hot: {
				..m_2ndop_done.cpu.hot,
				pipeline: Ready({ first: first, second: second, access_kind: Sequential }),
			},
		},
	})
}

# Returns the opcode pointed by current PC &
# a new machine with the pipeline field refreshed
# CPU and its PC are unchanged
take_opcode : Machine -> Try((Machine, CpuTypes.FetchedCode), _)
take_opcode = |m| {
	take_ready_opcode : Machine,
	{
		first : CpuTypes.FetchedCode,
		second : CpuTypes.FetchedCode,
		access_kind : [NonSequential, Sequential],
	} -> Try((Machine, CpuTypes.FetchedCode), _)
	take_ready_opcode = |give_machine, x| {
		first = x.first
		second = x.second
		(next_addr, width) = if give_machine.cpu.hot.core.is_thumb() {
			(ARM7TDMI.getPC(give_machine.cpu.hot.core).plus_wrap(4), W16)
		} else {
			(ARM7TDMI.getPC(give_machine.cpu.hot.core).plus_wrap(8), W32)
		}
		(advanced, third) = fetch_opcode(give_machine, next_addr, width, x.access_kind)?
		Ok((
			{
				..advanced,
				cpu: {
					..advanced.cpu,
					hot: {
						..advanced.cpu.hot,
						pipeline: Ready({
							first: second,
							second: third,
							access_kind: Sequential,
						}),
					},
				},
			},
			first,
		))
	}
	match m.cpu.hot.pipeline {
		Empty => {
			loaded = reload_pipeline(m)?
			match loaded.cpu.hot.pipeline {
				Empty => Err(WTFisThis)
				Ready(x) => take_ready_opcode(loaded, x)
			}
		}
		Ready(x) => take_ready_opcode(m, x)
	}
}

mark_fetch_nonsequential : Machine -> Machine
mark_fetch_nonsequential = |m| {
	match m.cpu.hot.pipeline {
		Empty => m
		Ready(x) => {
			..m,
			cpu: {
				..m.cpu,
				hot: {
					..m.cpu.hot,
					pipeline: Ready({ ..x, access_kind: NonSequential }),
				},
			},
		}
	}
}

advance_to_with : Machine, U64, (Machine -> Try(out, _)) -> Try(out, _)
advance_to_with = |m, target, finish_func| {
	# The finish_func is also a compiler targeted optimization, if you pass in the finish function
	# into it, and then just post-process the intermediate result,
	# so the caller can consume the advanced machine directly

	# Well, under the newest nightly 11-11, returning to the good old one func recursion is better now
	# Man WIP langs...
	process_event_or_batch : Machine, U64, U64, [None, At(U64)] -> Try((Machine, U8), _)
	process_event_or_batch = |given_m, given_target, given_at, given_timer_at| {
		if given_at > given_m.now and given_at < given_m.next_lcd_at {
			limit = given_target.min(given_m.next_lcd_at - 1)
			if given_at < limit {
				match TimerRegs.try_batch_ticks_to_known_next(given_m.bus.io_regs.timers, limit, given_at) {
					NoBatch => {}
					Batched(x) => {
						io_rgs = {
							..given_m.bus.io_regs,
							timers: x.timers,
							# non-overflow ticks CAN schedule pending DMA.
							dmas: DmaRegs.schedule_pending(given_m.bus.io_regs.dmas, given_at),
						}
						return Ok((
							{ ..given_m, bus: { ..given_m.bus, io_regs: io_rgs }, now: x.last_at },
							0.U8, # 0 here is useless
						))
					}
				}
			}
		}
		process_event_at(given_m, given_at, given_timer_at)
	}
	if (m.power_state == Stopped) return finish_func(m)
	if (target < m.now) return Err(WrongEventTime)
	timer_at = TimerRegs.next_event_at(m.bus.io_regs.timers)
	at = match timer_at {
		None => m.next_lcd_at
		At(t) => t.min(m.next_lcd_at)
	}
	if at <= target {
		(processed, _) = process_event_or_batch(m, target, at, timer_at)?
		return advance_to_with(processed, target, finish_func)
	}
	finish_func({
		..m,
		bus: {
			..m.bus,
			io_regs: {
				..m.bus.io_regs,
				timers: TimerRegs.sync_idle_to_known_next(
					m.bus.io_regs.timers,
					target,
					timer_at,
				)?,
			},
		},
		now: target,
	})
}

note_prefetch_turned_off : CpuTypes.PrefetchFields, U16, U16 -> CpuTypes.PrefetchFields
note_prefetch_turned_off = |cur_f, before, after| {
	if before.bitwise_and(0x4000) != 0 and after.bitwise_and(0x4000) == 0 {
		{ ..cur_f, force_next_rom_fetch_nonseq: True }
	} else {
		cur_f
	}
}
