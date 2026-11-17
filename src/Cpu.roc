import ARM7TDMI
import Bus
import BusSignals
import CpuTypes

BlockPhase : [Fetch, Execute(ARM7TDMI.Execution_state)]

# Cpu execution engine for mergable opcode blocks
Cpu := {
	hot : CpuTypes.HotState,
	suspended : CpuTypes.Suspended,
}.{
	init : () -> Cpu
	init = || { hot: init_hot(), suspended: None }

	get_core : Cpu -> ARM7TDMI
	get_core = |c| c.hot.core

	data_read_context : ARM7TDMI, CpuTypes.Pipeline, BusSignals -> Bus.ReadContext
	data_read_context = |core, pipe, signal| {
		{
			open_bus: if (ARM7TDMI.is_thumb(core)) None else arm_prefetch_word(pipe),
			bios_latch: BusSignals.get_bios_latch(signal),
			bios_readable: ARM7TDMI.getPC(core) < 0x4000,
		}
	}

	run_block : Bus.MemoryView, CpuTypes.RunState, CpuTypes.Limits, Bool -> Try(CpuTypes.BlockResult, _)
	run_block = |mv, rs, limits, irq_asserted| {
		# Pass MemoryView explicitly to reduce per-instruction MemoryView RC overhead.
		loop : Bus.MemoryView, ARM7TDMI, CpuTypes.EngineState, BlockPhase, U32, U64, [None, At(U64)] -> Try(CpuTypes.BlockResult, _)
		loop = |
			current_mv,
			core,
			engine,
			phase,
			actions_completed,
			event_at,
			dma_scheduled_at,
		| {
			match phase {
				Fetch => {
					match limits.target {
						At(t) if engine.now >= t =>
							return Ok(finish_block(core, engine, actions_completed, Boundary(ReachedTarget), current_mv, dma_scheduled_at))
						_ => {}
					}
					if (actions_completed >= limits.budget)
						return Ok(finish_block(core, engine, actions_completed, Boundary(BudgetExhausted), current_mv, dma_scheduled_at))
					if ((irq_asserted and core.cpsr.bitwise_and(0b1000_0000) == 0)
						or engine.now >= event_at)
						return Ok(finish_block(core, engine, actions_completed, Boundary(NeedsSlow), current_mv, dma_scheduled_at))

					match take_opcode(current_mv, engine, ARM7TDMI.getPC(core), core.is_thumb(), event_at)? {
						NeedsSlow => Ok(finish_block(core, engine, actions_completed, Boundary(NeedsSlow), current_mv, dma_scheduled_at))
						Fetched({ code: Unmapped(addr), .. }) => Err(UnmappedInstructionFetch(addr))
						Fetched({ code: Opcode(opcode), state: fetched_state }) => {
							# seems retarded branching? saves extra copying in generated code.
							if core.is_thumb() {
								loop(
									current_mv,
									core,
									fetched_state,
									Execute(
										ARM7TDMI.execute_thumb_opcode(core, opcode.to_u16_wrap())?,
									),
									actions_completed,
									event_at,
									dma_scheduled_at,
								)
							} else {
								loop(
									current_mv,
									core,
									fetched_state,
									Execute(
										ARM7TDMI.execute_arm_opcode(core, opcode)?,
									),
									actions_completed,
									event_at,
									dma_scheduled_at,
								)
							}
						}
					}
				}
				Execute(state) => {
					if (engine.now >= event_at) return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
					match state {
						W(request) => {
							# Only supports RAM reigon fast write
							if (!Bus.supports_view_write(request.addr)) return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							cycles_needed =
								Bus.access_cycles(current_mv.wait_cnt, request.width, request.addr, request.access_kind)
							if cycles_needed >= event_at - engine.now {
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							}

							first_dma_write = limits.schedule_dma and dma_scheduled_at == None
							write_at = engine.now + cycles_needed
							if (first_dma_write and write_at > U64.highest - 2)
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							# the write_view_ram method uses much smaller param and returns a List rathe than full mv
							# And yes, it does save memcpy amount comparing to passing full MV.
							new_mv = if request.addr.shr_wrap(24) == 2 {
								{
									..current_mv,
									ewram: Bus.write_view_ram(current_mv.ewram, request.width, request.addr, request.val)?,
								}
							} else {
								{
									..current_mv,
									iwram: Bus.write_view_ram(current_mv.iwram, request.width, request.addr, request.val)?,
								}
							}
							new_signal = match request.width {
								W8 => BusSignals.record_write8(engine.signal, request.addr, request.val.to_u8_wrap())
								W16 => BusSignals.record_write16(engine.signal, CpuData, request.addr, request.val.to_u16_wrap())
								W32 => BusSignals.record_write32(engine.signal, CpuData, request.addr, request.val)
							}
							after_write = {
								now: write_at,
								signal: new_signal,
								pipeline: mark_fetch_nonsequential(engine.pipeline),
							}
							next_execution =
								ARM7TDMI.resume_write(request.core, request.continuation)?
							loop(
								new_mv,
								core,
								after_write,
								Execute(next_execution),
								actions_completed,
								if (first_dma_write) event_at.min(write_at + 2) else event_at,
								if (first_dma_write) At(write_at) else dma_scheduled_at,
							)
						}
						Complete(outcome) => {
							if outcome.remaining_cycles >= event_at - engine.now {
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							}

							completed = { ..engine, now: engine.now + outcome.remaining_cycles }
							marked = if outcome.remaining_cycles > 0 {
								{ ..completed, pipeline: mark_fetch_nonsequential(completed.pipeline) }
							} else {
								completed
							}
							after = match outcome.pc_status {
								PCSequential => marked
								PCWritten => {
									match reload_pipeline(
										current_mv,
										{ now: marked.now, signal: marked.signal },
										ARM7TDMI.getPC(outcome.core),
										outcome.core.is_thumb(),
										event_at,
									)? {
										# Return the original state so the slow path charges completion cycles only once.
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
										Reloaded(access, pipeline) => {
											now: access.now,
											signal: access.signal,
											pipeline: Ready(pipeline),
										}
									}
								}
							}
							loop(current_mv, outcome.core, after, Fetch, actions_completed + 1, event_at, dma_scheduled_at)
						}
						R(request) => {
							cycles_needed =
								Bus.access_cycles(current_mv.wait_cnt, request.width, request.addr, request.access_kind)
							if cycles_needed >= event_at - engine.now {
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							}
							cxt = data_read_context(request.core, engine.pipeline, engine.signal)
							(raw_val, signal) = match request.width {
								W8 => {
									match Bus.read_view8(current_mv, request.addr, cxt)? {
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
										Value(result) => {
											after_b_latch = match result.bios_latch_update {
												Unchanged => engine.signal
												Updated(word) => BusSignals.set_bios_latch(engine.signal, word)
											}
											after_access = BusSignals.record_read8(
												after_b_latch,
												request.addr,
												result.val,
											)
											(result.val.to_u32(), after_access)
										}
									}
								}
								W16 => {
									match Bus.read_view16(current_mv, request.addr, cxt)? {
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
										Value(result) => {
											after_b_latch = match result.bios_latch_update {
												Unchanged => engine.signal
												Updated(word) => BusSignals.set_bios_latch(engine.signal, word)
											}
											after_access = BusSignals.record_read16(
												after_b_latch,
												CpuData,
												request.addr,
												result.val,
											)
											(result.val.to_u32(), after_access)
										}
									}
								}
								W32 => {
									match Bus.read_view32(current_mv, request.addr, cxt)? {
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
										Value(result) => {
											after_b_latch = match result.bios_latch_update {
												Unchanged => engine.signal
												Updated(word) => BusSignals.set_bios_latch(engine.signal, word)
											}
											after_access = BusSignals.record_read32(
												after_b_latch,
												CpuData,
												request.addr,
												result.val,
											)
											(result.val, after_access)
										}
									}
								}
							}
							after_read = {
								..engine,
								now: engine.now + cycles_needed,
								signal,
								pipeline: mark_fetch_nonsequential(engine.pipeline),
							}
							next_execution =
								ARM7TDMI.resume_read(request.core, raw_val, request.continuation)?
							loop(
								current_mv,
								core,
								after_read,
								Execute(next_execution),
								actions_completed,
								event_at,
								dma_scheduled_at,
							)
						}
					}
				}
			}
		}
		loop(
			mv,
			rs.hot.core,
			{ now: rs.now, signal: rs.signal, pipeline: rs.hot.pipeline },
			Fetch,
			0,
			limits.event_at,
			None,
		)
	}

	take_opcode : Bus.MemoryView,
	CpuTypes.EngineState,
	U32,
	Bool,
	U64 -> Try(
		CpuTypes.FetchResult(CpuTypes.EngineState),
		_,
	)
	take_opcode = |mv, fs, pc, is_thumb, event_at| {
		if (fs.now >= event_at) return Ok(NeedsSlow)

		initial_access = { now: fs.now, signal: fs.signal }
		(access, pipeline) = match fs.pipeline {
			Ready(p) => (initial_access, p)
			Empty => match reload_pipeline(mv, initial_access, pc, is_thumb, event_at)? {
				NeedsSlow => return Ok(NeedsSlow)
				Reloaded(next_access, p) => (next_access, p)
			}
		}
		first = pipeline.first
		second = pipeline.second
		(next_addr, next_width) = if (is_thumb) (pc.plus_wrap(4), W16) else (pc.plus_wrap(8), W32)
		(new_state, third) =
			match fetch_opcode(mv, access, next_addr, next_width, pipeline.access_kind, event_at)? {
				NeedsSlow => return Ok(NeedsSlow)
				Fetched(y) => (y.state, y.code)
			}
		Ok(
			Fetched({
				state: {
					now: new_state.now,
					signal: new_state.signal,
					pipeline: Ready({ first: second, second: third, access_kind: Sequential }),
				},
				code: first,
			}),
		)
	}

	fetch_opcode : Bus.MemoryView,
	CpuTypes.FetchState,
	U32,
	[W16, W32],
	[NonSequential, Sequential],
	U64 -> Try(
		CpuTypes.FetchResult(CpuTypes.FetchState),
		_,
	)
	fetch_opcode = |mv, rs, addr, width, req_kind, event_at| {
		if (rs.now >= event_at) return Ok(NeedsSlow)
		cycles_needed = fetch_cycles(mv.wait_cnt, addr, width, req_kind)
		if (cycles_needed >= event_at - rs.now) return Ok(NeedsSlow)

		if addr >= 0x4000 and addr < 0x100_0000 { # Unmapped reigon right after BIOS
			alignment = if (width == W16) 2 else 4
			if (addr.mod_by(alignment) != 0) return Err(MisalignedAddress(addr))
			new_rs = { ..rs, now: rs.now + cycles_needed }
			Ok(Fetched({ state: new_rs, code: Unmapped(addr) }))
		} else {
			cxt = {
				open_bus: None, # Not entirely done yet, so still None
				bios_latch: BusSignals.get_bios_latch(rs.signal),
				bios_readable: addr < 0x4000,
			}
			(value, signal) = match width {
				W16 => {
					match Bus.read_view16(mv, addr, cxt)? {
						NeedsSlow => return Ok(NeedsSlow)
						Value(result) => {
							after_b_latch = match result.bios_latch_update {
								Unchanged => rs.signal
								Updated(word) => BusSignals.set_bios_latch(rs.signal, word)
							}
							after_access = BusSignals.record_read16(
								after_b_latch,
								Fetch,
								addr,
								result.val,
							)
							(result.val.to_u32(), after_access)
						}
					}
				}
				W32 => {
					match Bus.read_view32(mv, addr, cxt)? {
						NeedsSlow => return Ok(NeedsSlow)
						Value(result) => {
							after_b_latch = match result.bios_latch_update {
								Unchanged => rs.signal
								Updated(word) => BusSignals.set_bios_latch(rs.signal, word)
							}
							after_access = BusSignals.record_read32(
								after_b_latch,
								Fetch,
								addr,
								result.val,
							)
							(result.val, after_access)
						}
					}
				}
			}
			Ok(
				Fetched({ state: { ..rs, now: rs.now + cycles_needed, signal }, code: Opcode(value) }),
			)
		}
	}

	reload_pipeline : Bus.MemoryView,
	CpuTypes.FetchState,
	U32,
	Bool,
	U64 -> Try(
		[Reloaded(CpuTypes.FetchState, CpuTypes.ReadyPipeline), NeedsSlow],
		_,
	)
	reload_pipeline = |mv, fs, cur_pc, is_thumb, event_at| {
		if (fs.now >= event_at) return Ok(NeedsSlow)
		(width, steps) = if (is_thumb) (W16, 2.U32) else (W32, 4)

		first_cycles = fetch_cycles(mv.wait_cnt, cur_pc, width, NonSequential)
		second_cycles = fetch_cycles(mv.wait_cnt, cur_pc.plus_wrap(steps), width, Sequential)
		if (first_cycles + second_cycles >= event_at - fs.now) return Ok(NeedsSlow)

		first_opcode =
			match fetch_opcode(
				mv,
				{ now: fs.now, signal: fs.signal },
				cur_pc,
				width,
				NonSequential,
				event_at,
			)? {
				NeedsSlow => return Ok(NeedsSlow)
				Fetched(result) => result
			}
		second_opcode =
			match fetch_opcode(mv, first_opcode.state, cur_pc.plus_wrap(steps), width, Sequential, event_at)? {
				NeedsSlow => return Ok(NeedsSlow)
				Fetched(result) => result
			}
		Ok(
			Reloaded(
				second_opcode.state,
				{ first: first_opcode.code, second: second_opcode.code, access_kind: Sequential },
			),
		)
	}
}

init_hot : () -> CpuTypes.HotState
init_hot = || { core: ARM7TDMI.init(), pipeline: Empty }

to_bus_width : [W16, W32] -> [W8, W16, W32]
to_bus_width = |w| w

fetch_cycles : U16, U32, [W16, W32], [NonSequential, Sequential] -> U64
fetch_cycles = |wait_cnt, addr, width, req_kind| {
	if (addr >= 0x4000 and addr < 0x100_0000) 1 else Bus.access_cycles(wait_cnt, to_bus_width(width), addr, req_kind)
}

finish_block : ARM7TDMI, CpuTypes.EngineState, U32, CpuTypes.BlockExit, Bus.MemoryView, [None, At(U64)] -> CpuTypes.BlockResult
finish_block = |core, engine, actions_completed, exit_reason, mv, dma_schedule_at| {
	{ # Literally just put pieces back, nothing special
		state: { hot: { core, pipeline: engine.pipeline }, now: engine.now, signal: engine.signal },
		actions_completed,
		exit: exit_reason,
		memory: mv,
		dma_schedule_at: dma_schedule_at,
	}
}

arm_prefetch_word : CpuTypes.Pipeline -> [None, Value(U32)]
arm_prefetch_word = |pipe| {
	match pipe {
		Ready({ second: Opcode(word), .. }) => Value(word)
		_ => None
	}
}

mark_fetch_nonsequential : CpuTypes.Pipeline -> CpuTypes.Pipeline
mark_fetch_nonsequential = |pipeline| {
	match pipeline {
		Empty => Empty
		Ready(x) => Ready({ ..x, access_kind: NonSequential })
	}
}
