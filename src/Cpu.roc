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

	run_block : Bus.ReadView, CpuTypes.RunState, CpuTypes.Limits, Bool -> Try(CpuTypes.BlockResult, _)
	run_block = |rv, rs, limits, irq_asserted| {
		# Pass ReadView explicitly to reduce per-instruction ReadView RC overhead.
		loop : Bus.ReadView, ARM7TDMI, CpuTypes.EngineState, BlockPhase, U32 -> Try(CpuTypes.BlockResult, _)
		loop = |current_rv, core, engine, phase, actions_completed| {
			match phase {
				Fetch => {
					match limits.target {
						At(t) if engine.now >= t => {
							return Ok(finish_block(core, engine, actions_completed, Boundary(ReachedTarget)))
						}
						_ => {}
					}
					if actions_completed >= limits.budget {
						return Ok(finish_block(core, engine, actions_completed, Boundary(BudgetExhausted)))
					}
					if (irq_asserted and core.cpsr.bitwise_and(0b1000_0000) == 0)
						or engine.now >= limits.event_at {
						return Ok(finish_block(core, engine, actions_completed, Boundary(NeedsSlow)))
					}
					match take_opcode(current_rv, engine, ARM7TDMI.getPC(core), core.is_thumb(), limits.event_at)? {
						NeedsSlow => Ok(finish_block(core, engine, actions_completed, Boundary(NeedsSlow)))
						Fetched(fetched) => {
							opcode = match fetched.code {
								Unmapped(addr) => return Err(UnmappedInstructionFetch(addr))
								Opcode(op) => op
							}
							if core.is_thumb() {
								loop(
									current_rv,
									core,
									fetched.state,
									Execute(
										ARM7TDMI.execute_thumb_opcode(core, opcode.to_u16_wrap())?,
									),
									actions_completed,
								)
							} else {
								loop(
									current_rv,
									core,
									fetched.state,
									Execute(
										ARM7TDMI.execute_arm_opcode(core, opcode)?,
									),
									actions_completed,
								)
							}
						}
					}
				}
				Execute(state) => {
					if (engine.now >= limits.event_at) return Ok(finish_block(core, engine, actions_completed, Pending(state)))
					match state {
						W(_) => Ok(finish_block(core, engine, actions_completed, Pending(state))) # No optimization for Write continuation yet
						Complete(outcome) => {
							if outcome.remaining_cycles >= limits.event_at - engine.now {
								return Ok(finish_block(core, engine, actions_completed, Pending(state)))
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
										current_rv,
										{ now: marked.now, signal: marked.signal },
										ARM7TDMI.getPC(outcome.core),
										outcome.core.is_thumb(),
										limits.event_at,
									)? {
										# Return the original state so the slow path charges completion cycles only once.
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state)))
										Reloaded(access, pipeline) => {
											now: access.now,
											signal: access.signal,
											pipeline: Ready(pipeline),
										}
									}
								}
							}
							loop(current_rv, outcome.core, after, Fetch, actions_completed + 1)
						}
						R(request) => {
							cycles_needed =
								Bus.access_cycles(current_rv.wait_cnt, request.width, request.addr, request.access_kind)
							if cycles_needed >= limits.event_at - engine.now {
								return Ok(finish_block(core, engine, actions_completed, Pending(state)))
							}

							(raw_val, signal) = match request.width {
								W8 => {
									match Bus.read_view8(current_rv, request.addr)? {
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state)))
										Value(v) => (v.to_u32(), BusSignals.record_read8(engine.signal, request.addr, v))
									}
								}
								W16 => {
									match Bus.read_view16(current_rv, request.addr)? {
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state)))
										Value(v) => (v.to_u32(), BusSignals.record_read16(engine.signal, CpuData, request.addr, v))
									}
								}
								W32 => {
									match Bus.read_view32(current_rv, request.addr)? {
										NeedsSlow => return Ok(finish_block(core, engine, actions_completed, Pending(state)))
										Value(v) => (v, BusSignals.record_read32(engine.signal, CpuData, request.addr, v))
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
							loop(current_rv, core, after_read, Execute(next_execution), actions_completed)
						}
					}
				}
			}
		}
		loop(
			rv,
			rs.hot.core,
			{ now: rs.now, signal: rs.signal, pipeline: rs.hot.pipeline },
			Fetch,
			0,
		)
	}

	take_opcode : Bus.ReadView,
	CpuTypes.EngineState,
	U32,
	Bool,
	U64 -> Try(
		CpuTypes.FetchResult(CpuTypes.EngineState),
		_,
	)
	take_opcode = |rv, fs, pc, is_thumb, event_at| {
		if (fs.now >= event_at) return Ok(NeedsSlow)

		initial_access = { now: fs.now, signal: fs.signal }
		(access, pipeline) = match fs.pipeline {
			Ready(p) => (initial_access, p)
			Empty => match reload_pipeline(rv, initial_access, pc, is_thumb, event_at)? {
				NeedsSlow => return Ok(NeedsSlow)
				Reloaded(next_access, p) => (next_access, p)
			}
		}
		first = pipeline.first
		second = pipeline.second
		(next_addr, next_width) = if (is_thumb) (pc.plus_wrap(4), W16) else (pc.plus_wrap(8), W32)
		(new_state, third) =
			match fetch_opcode(rv, access, next_addr, next_width, pipeline.access_kind, event_at)? {
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

	fetch_opcode : Bus.ReadView,
	CpuTypes.FetchState,
	U32,
	[W16, W32],
	[NonSequential, Sequential],
	U64 -> Try(
		CpuTypes.FetchResult(CpuTypes.FetchState),
		_,
	)
	fetch_opcode = |rv, rs, addr, width, req_kind, event_at| {
		if (rs.now >= event_at) return Ok(NeedsSlow)
		cycles_needed = fetch_cycles(rv, addr, width, req_kind)
		if (cycles_needed >= event_at - rs.now) return Ok(NeedsSlow)

		if addr >= 0x4000 and addr < 0x100_0000 { # Unmapped reigon right after BIOS
			alignment = if (width == W16) 2 else 4
			if (addr.mod_by(alignment) != 0) return Err(MisalignedAddress(addr)) else {}
			new_rs = { ..rs, now: rs.now + cycles_needed }
			Ok(Fetched({ state: new_rs, code: Unmapped(addr) }))
		} else {
			(value, signal) = match width {
				W16 => {
					match Bus.read_view16(rv, addr)? {
						NeedsSlow => return Ok(NeedsSlow)
						Value(v) => (v.to_u32(), BusSignals.record_read16(rs.signal, Fetch, addr, v))
					}
				}
				W32 => {
					match Bus.read_view32(rv, addr)? {
						NeedsSlow => return Ok(NeedsSlow)
						Value(v) => (v, BusSignals.record_read32(rs.signal, Fetch, addr, v))
					}
				}
			}
			Ok(
				Fetched({ state: { ..rs, now: rs.now + cycles_needed, signal }, code: Opcode(value) }),
			)
		}
	}

	reload_pipeline : Bus.ReadView,
	CpuTypes.FetchState,
	U32,
	Bool,
	U64 -> Try(
		[Reloaded(CpuTypes.FetchState, CpuTypes.ReadyPipeline), NeedsSlow],
		_,
	)
	reload_pipeline = |rv, fs, cur_pc, is_thumb, event_at| {
		if (fs.now >= event_at) return Ok(NeedsSlow)
		(width, steps) = if (is_thumb) (W16, 2.U32) else (W32, 4)

		first_cycles = fetch_cycles(rv, cur_pc, width, NonSequential)
		second_cycles = fetch_cycles(rv, cur_pc.plus_wrap(steps), width, Sequential)
		if (first_cycles + second_cycles >= event_at - fs.now) return Ok(NeedsSlow)

		first_opcode =
			match fetch_opcode(
				rv,
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
			match fetch_opcode(rv, first_opcode.state, cur_pc.plus_wrap(steps), width, Sequential, event_at)? {
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

fetch_cycles : Bus.ReadView, U32, [W16, W32], [NonSequential, Sequential] -> U64
fetch_cycles = |rv, addr, width, req_kind| {
	if (addr >= 0x4000 and addr < 0x100_0000) 1 else Bus.access_cycles(rv.wait_cnt, to_bus_width(width), addr, req_kind)
}

finish_block : ARM7TDMI, CpuTypes.EngineState, U32, CpuTypes.BlockExit -> CpuTypes.BlockResult
finish_block = |core, engine, actions_completed, exit_reason| {
	{ # Literally just put pieces back, nothing special
		state: { hot: { core, pipeline: engine.pipeline }, now: engine.now, signal: engine.signal },
		actions_completed,
		exit: exit_reason,
	}
}

mark_fetch_nonsequential : CpuTypes.Pipeline -> CpuTypes.Pipeline
mark_fetch_nonsequential = |pipeline| {
	match pipeline {
		Empty => Empty
		Ready(x) => Ready({ ..x, access_kind: NonSequential })
	}
}
