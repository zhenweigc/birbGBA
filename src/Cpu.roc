import Bits
import ARM7TDMI
import Bus
import BusSignals
import BusTypes
import MemoryRegion
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
			open_bus: if ARM7TDMI.is_thumb(core) {
				thumb_open_bus_candidate(ARM7TDMI.getPC(core), pipe)
			}
			else {
				arm_open_bus_candidate(pipe)
			},
			bios_latch: BusSignals.get_bios_latch(signal),
			bios_readable: ARM7TDMI.getPC(core) < 0x4000,
		}
	}

	advance_prefetch_fill : U64, U64 -> [Pending(U64), Filled(U64)]
	advance_prefetch_fill = |cycles_left, idle_cycles| {
		if (idle_cycles < cycles_left) return Pending(cycles_left - idle_cycles)
		Filled(idle_cycles - cycles_left)
	}

	# fill_addr should be halfword aligned
	# ROM address the prefetch flow is about to read
	start_prefetch_fill : U16, U32 -> CpuTypes.PrefetchInFlight
	start_prefetch_fill = |waitcnt, fill_addr| {
		if (fill_addr.mod_by(2) != 0 or fill_addr < 0x8000000 or fill_addr >= 0xE000000) return Idle
		if (!Bits.get_ith_bit_u16_certain(waitcnt, 14)) return Idle
		Filling({ addr: fill_addr, cycles_left: Bus.access_cycles(waitcnt, W16, fill_addr, Sequential) })
	}

	# Cpu got the opcode from a new or already in-flight Game Pak read
	# Start prefetching right after that opcode
	start_prefetch_stream_after_rom_fetch : U16, U32, BusTypes.HalfOrWord -> CpuTypes.GamePakPrefetch
	start_prefetch_stream_after_rom_fetch = |waitcnt, fetched_addr, width| {
		nxt_addr = if (width == W16) fetched_addr + 2 else fetched_addr + 4
		match start_prefetch_fill(waitcnt, nxt_addr) {
			Idle => Nothing
			Filling({ addr, cycles_left }) => # nxt_addr == addr here
				Stream({ head_addr: addr, ready_count: 0, in_flight: Filling({ addr, cycles_left }) })
		}
	}

	advance_prefetch_stream : CpuTypes.GamePakPrefetch, U16, U64 -> CpuTypes.GamePakPrefetch
	advance_prefetch_stream = |pref, waitcnt, idle_cycles| {
		if (idle_cycles == 0) return pref
		match pref {
			Nothing => Nothing
			Stream({ head_addr, ready_count, in_flight }) => {
				fill_to_advance = match in_flight {
					Idle if ready_count == 8 => return pref
					# Stolen from NAB, ready_count++ even though no new halfword was read
					# Why? TBF no clue
					Idle if !Bits.get_ith_bit_u16_certain(waitcnt, 14) =>
						return Stream({ head_addr, ready_count: ready_count + 1, in_flight })
					Idle => start_prefetch_fill(waitcnt, head_addr + 2 * ready_count.to_u32())
					Filling(_) => in_flight
				}
				match fill_to_advance {
					Idle => pref
					Filling({ addr, cycles_left }) => {
						match advance_prefetch_fill(cycles_left, idle_cycles) {
							Pending(left) => Stream({
								head_addr,
								ready_count,
								in_flight: Filling({ addr, cycles_left: left }),
							})
							Filled(remaining) => {
								if (ready_count == 7) return Stream({ head_addr, ready_count: 8, in_flight: Idle })
								# Early rtn as the next recursive call with leftover cycles might add another count
								# as it will hit Idle branch
								if (!Bits.get_ith_bit_u16_certain(waitcnt, 14))
									return Stream({ head_addr, ready_count: ready_count + 1, in_flight: Idle })
								advance_prefetch_stream(
									Stream({
										head_addr,
										ready_count: ready_count + 1,
										in_flight: start_prefetch_fill(waitcnt, addr + 2),
									}),
									waitcnt,
									remaining,
								)
							}
						}
					}
				}
			}
		}
	}

	# Do not confuse with CPU pipeline
	# This is Cpu consuming a prefetched halfword by Bus of Game Pak ROM
	take_prefetched_opcode_halfword : CpuTypes.GamePakPrefetch, U32 -> [Ready(CpuTypes.GamePakPrefetch), WaitForFill(U64), Nothing]
	take_prefetched_opcode_halfword = |pref, addr_requested| {
		match pref {
			Nothing => Nothing
			Stream({ head_addr, ready_count, in_flight }) => {
				if ready_count > 0 and addr_requested == head_addr {
					return Ready(Stream({ head_addr: head_addr + 2, ready_count: ready_count - 1, in_flight }))
				}
				match in_flight {
					Filling({ addr, cycles_left }) if addr == addr_requested => WaitForFill(cycles_left)
					_ => Nothing # != flush the prefetch pool
				}
			}
		}
	}

	plan_fetch16_fields : CpuTypes.PrefetchFields,
	U16,
	U32,
	ARM7TDMI.ReqKind -> {
		cycles : U64,
		next_prefetch : CpuTypes.PrefetchFields,
	}
	# So the Cpu decided to read addr_requested, fair
	# How many cycles needed? What happen to the FIFO of GamePak prefetcher?
	plan_fetch16_fields = |f, waitcnt, addr_requested, req_kind| {
		pref = prefetch_from_fields(f)
		match take_prefetched_opcode_halfword(pref, addr_requested) {
			Ready(next) =>
				{
					cycles: 1,
					next_prefetch: advance_prefetch_stream(next, waitcnt, 1)
						|> prefetch_to_fields(f.force_next_rom_fetch_nonseq),
				}
			WaitForFill(n) => {
				cycles: n,
				next_prefetch: start_prefetch_stream_after_rom_fetch(waitcnt, addr_requested, W16)
					|> prefetch_to_fields(f.force_next_rom_fetch_nonseq),
			}
			Nothing => {
				# Stolen from NBA, somehow if old prefetch has one cycle til finish
				# And Cpu wants a different address, termination action will take one cycle
				# Does not apply to prefetch with more cycles til finish
				abort_cycles = match pref {
					Stream({ in_flight: Filling({ cycles_left: 1, .. }), .. }) => 1
					_ => 0.U64
				}
				kind_for_miss =
					if (f.force_next_rom_fetch_nonseq) NonSequential else req_kind
				{
					cycles: fetch_cycles(waitcnt, addr_requested, W16, kind_for_miss) + abort_cycles,
					next_prefetch: start_prefetch_stream_after_rom_fetch(waitcnt, addr_requested, W16)
						|> prefetch_to_fields(False),
				}
			}
		}
	}

	plan_fetch32_fields : CpuTypes.PrefetchFields,
	U16,
	U32,
	ARM7TDMI.ReqKind -> {
		cycles : U64,
		next_prefetch : CpuTypes.PrefetchFields,
	}
	plan_fetch32_fields = |f, waitcnt, addr_requested, req_kind| {
		pref = prefetch_from_fields(f)
		lo = take_prefetched_opcode_halfword(pref, addr_requested)
		hi = match lo {
			Ready(after_lo) =>
				take_prefetched_opcode_halfword(after_lo, addr_requested + 2)
			Nothing | WaitForFill(_) => Nothing
		}
		match (lo, hi) {
			(Ready(_), Ready(after_both)) =>
				{
					cycles: 1,
					next_prefetch: advance_prefetch_stream(after_both, waitcnt, 1)
						|> prefetch_to_fields(f.force_next_rom_fetch_nonseq),
				}
			(Ready(_), WaitForFill(n)) =>
				{
					cycles: n,
					next_prefetch: start_prefetch_stream_after_rom_fetch(waitcnt, addr_requested, W32)
						|> prefetch_to_fields(f.force_next_rom_fetch_nonseq),
				}
			(Ready(_), Nothing) =>
				{
					cycles: fetch_cycles(waitcnt, addr_requested + 2, W16, Sequential),
					next_prefetch: start_prefetch_stream_after_rom_fetch(waitcnt, addr_requested, W32)
						|> prefetch_to_fields(f.force_next_rom_fetch_nonseq),
				}
			(WaitForFill(n), _) =>
				{ # Technically the 2nd half can only be Nothing, anything else means there are batshit crazy bugs
					cycles: fetch_cycles(waitcnt, addr_requested + 2, W16, Sequential) + n,
					next_prefetch: start_prefetch_stream_after_rom_fetch(waitcnt, addr_requested, W32)
						|> prefetch_to_fields(f.force_next_rom_fetch_nonseq),
				}
			(Nothing, _) => {
				abort_cycles = match pref {
					Stream({ in_flight: Filling({ cycles_left: 1, .. }), .. }) => 1
					_ => 0.U64
				}
				kind_for_miss =
					if (f.force_next_rom_fetch_nonseq) NonSequential else req_kind
				{
					cycles: fetch_cycles(waitcnt, addr_requested, W32, kind_for_miss) + abort_cycles,
					next_prefetch: start_prefetch_stream_after_rom_fetch(waitcnt, addr_requested, W32)
						|> prefetch_to_fields(False),
				}
			}
		}
	}

	advance_prefetch_fields : CpuTypes.PrefetchFields, U16, U64 -> CpuTypes.PrefetchFields
	advance_prefetch_fields = |f, waitcnt, cycles| {
		prefetch_from_fields(f)
			|> advance_prefetch_stream(waitcnt, cycles)
			|> prefetch_to_fields(f.force_next_rom_fetch_nonseq)
	}

	plan_cpu_data_access_fields : CpuTypes.PrefetchFields,
	U16,
	U32,
	U32,
	U64 -> {
		cycles : U64,
		next_prefetch : CpuTypes.PrefetchFields,
	}
	plan_cpu_data_access_fields = |f, waitcnt, pc, addr, base_cycles| {
		region = addr.shr_wrap(24)

		if region >= 0x8 and region <= 0xF { # GamePAK?
			executing_from_rom = pc >= 0x8000000 and pc < 0xE000000
			penalty = if executing_from_rom and f.head_addr != 0 and f.fill_left == 1 {
				1.U64
			} else {
				0.U64
			}
			return {
				cycles: base_cycles + penalty,
				next_prefetch: { ..f, head_addr: 0, ready_count: 0, fill_left: 0 },
			}
		}

		{
			cycles: base_cycles,
			# Work RAM, I/O, and video memory -> Game Pak bus free
			next_prefetch: if (region >= 2 and region <= 7) advance_prefetch_fields(f, waitcnt, base_cycles) else f,
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
					if (engine.now >= event_at)
						return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
					match state {
						W(request) => {
							# Only supports RAM reigon fast write
							if (!Bus.supports_view_write(request.addr))
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							cycles_needed =
								Bus.access_cycles(current_mv.wait_cnt, request.width, request.addr, request.access_kind)
							if (cycles_needed >= event_at - engine.now)
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))

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
								gamepak_prefetch: advance_prefetch_fields(
									engine.gamepak_prefetch,
									current_mv.wait_cnt,
									cycles_needed,
								),
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
								{
									..completed,
									pipeline: mark_fetch_nonsequential(completed.pipeline),
									gamepak_prefetch: advance_prefetch_fields(
										completed.gamepak_prefetch,
										current_mv.wait_cnt,
										outcome.remaining_cycles,
									),
								}
							} else {
								completed
							}
							after = match outcome.pc_status {
								PCSequential => marked
								PCWritten => {
									match reload_pipeline(
										current_mv,
										{ now: marked.now, signal: marked.signal, gamepak_prefetch: marked.gamepak_prefetch },
										ARM7TDMI.getPC(outcome.core),
										outcome.core.is_thumb(),
										event_at,
									)? {
										# Return the original state so the slow path charges completion cycles only once.
										NeedsSlow =>
											return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
										Reloaded(access, pipeline) => {
											now: access.now,
											signal: access.signal,
											pipeline: Ready(pipeline),
											gamepak_prefetch: access.gamepak_prefetch,
										}
									}
								}
							}
							loop(current_mv, outcome.core, after, Fetch, actions_completed + 1, event_at, dma_scheduled_at)
						}
						R(request) => {
							base_cycles = Bus.access_cycles(current_mv.wait_cnt, request.width, request.addr, request.access_kind)
							plan = plan_cpu_data_access_fields(
								engine.gamepak_prefetch,
								current_mv.wait_cnt,
								ARM7TDMI.getPC(core),
								request.addr,
								base_cycles,
							)
							if plan.cycles >= event_at - engine.now {
								return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
							}

							cxt = data_read_context(request.core, engine.pipeline, engine.signal)
							(raw_val, signal) = match request.width {
								W8 => {
									match Bus.read_view8(current_mv, request.addr, cxt)? {
										NeedsSlow =>
											return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
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
										NeedsSlow =>
											return Ok(finish_block(core, engine, actions_completed, Pending(state), current_mv, dma_scheduled_at))
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
								now: engine.now + plan.cycles,
								signal,
								pipeline: mark_fetch_nonsequential(engine.pipeline),
								gamepak_prefetch: plan.next_prefetch,
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
			{ now: rs.now, signal: rs.signal, pipeline: rs.hot.pipeline, gamepak_prefetch: rs.hot.gamepak_prefetch },
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

		initial_access =
			{ now: fs.now, signal: fs.signal, gamepak_prefetch: fs.gamepak_prefetch }
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
					gamepak_prefetch: new_state.gamepak_prefetch,
				},
				code: first,
			}),
		)
	}

	fetch_opcode : Bus.MemoryView,
	CpuTypes.FetchState,
	U32,
	BusTypes.HalfOrWord,
	[NonSequential, Sequential],
	U64 -> Try(
		CpuTypes.FetchResult(CpuTypes.FetchState),
		_,
	)
	fetch_opcode = |mv, rs, addr, width, req_kind, event_at| {
		if (rs.now >= event_at) return Ok(NeedsSlow)

		plan = if addr >= 0x8000000 and addr < 0xE000000 {
			match width {
				W16 => plan_fetch16_fields(rs.gamepak_prefetch, mv.wait_cnt, addr, req_kind)
				W32 => plan_fetch32_fields(rs.gamepak_prefetch, mv.wait_cnt, addr, req_kind)
			}
		} else {
			{ cycles: fetch_cycles(mv.wait_cnt, addr, width, req_kind), next_prefetch: rs.gamepak_prefetch }
		}
		cycles_needed = plan.cycles
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
				Fetched({
					state: {
						..rs,
						now: rs.now + cycles_needed,
						signal,
						gamepak_prefetch: plan.next_prefetch,
					},
					code: Opcode(value),
				}),
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

		first_opcode =
			match fetch_opcode(
				mv,
				{ now: fs.now, signal: fs.signal, gamepak_prefetch: fs.gamepak_prefetch },
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
init_hot = || {
	{
		core: ARM7TDMI.init(),
		pipeline: Empty,
		gamepak_prefetch: {
			head_addr: 0,
			ready_count: 0,
			fill_left: 0,
			force_next_rom_fetch_nonseq: False,
		},
	}
}

fetch_cycles : U16, U32, BusTypes.HalfOrWord, [NonSequential, Sequential] -> U64
fetch_cycles = |wait_cnt, addr, width, req_kind| {
	if (addr >= 0x4000 and addr < 0x100_0000) 1 else Bus.access_cycles(wait_cnt, BusTypes.to_bus_width(width), addr, req_kind)
}

finish_block : ARM7TDMI, CpuTypes.EngineState, U32, CpuTypes.BlockExit, Bus.MemoryView, [None, At(U64)] -> CpuTypes.BlockResult
finish_block = |core, engine, actions_completed, exit_reason, mv, dma_schedule_at| {
	{ # Literally just put pieces back, nothing special
		state: {
			hot: {
				core,
				pipeline: engine.pipeline,
				gamepak_prefetch: engine.gamepak_prefetch,
			},
			now: engine.now,
			signal: engine.signal,
		},
		actions_completed,
		exit: exit_reason,
		memory: mv,
		dma_schedule_at: dma_schedule_at,
	}
}

arm_open_bus_candidate : CpuTypes.Pipeline -> [None, Value(U32)]
arm_open_bus_candidate = |pipe| {
	match pipe {
		Ready({ second: Opcode(word), .. }) => Value(word)
		_ => None
	}
}

# https://problemkaputt.de/gbatek-gba-unpredictable-things.htm
thumb_open_bus_candidate : U32, CpuTypes.Pipeline -> [None, Value(U32)]
thumb_open_bus_candidate = |pc, pipe| {
	match pipe {
		Ready({ first, second: Opcode(word2), .. }) => {
			match MemoryRegion.memory_map_decode(pc.plus_wrap(4)).region {
				CPUExternalRAM | PaletteRAM | VRAM | GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 =>
					Value(word2.shl_wrap(16) + word2.bitwise_and(0xFFFF))
				CPUInternalRAM => match first {
					Opcode(word1) => if pc.bitwise_and(0b11) == 0 {
						Value(word1.shl_wrap(16) + word2)
					} else {
						Value(word2.shl_wrap(16) + word1)
					}
					_ => None
				}
				SystemROM | OAM => match first {
					Opcode(word1) if pc.bitwise_and(0b10) != 0 =>
						Value(word2.shl_wrap(16) + word1)
					_ => None # Higher halfword needs PC+6, well I do not have it here.
				}
				_ => None
			}
		}
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

# Ah yes, here we go again or else frame rate goes to hell
prefetch_to_fields : CpuTypes.GamePakPrefetch, Bool -> CpuTypes.PrefetchFields
prefetch_to_fields = |pref, force_next_rom_fetch_nonseq| match pref {
	Nothing => { head_addr: 0, ready_count: 0, fill_left: 0, force_next_rom_fetch_nonseq }
	Stream({ head_addr, ready_count, in_flight }) => {
		fill_left = match in_flight {
			Idle => 0
			Filling(f) => f.cycles_left.to_u8_wrap()
		}
		{ head_addr, ready_count, fill_left, force_next_rom_fetch_nonseq }
	}
}

prefetch_from_fields : CpuTypes.PrefetchFields -> CpuTypes.GamePakPrefetch
prefetch_from_fields = |f| {
	if (f.head_addr == 0) return Nothing

	in_flight = if f.fill_left == 0 {
		Idle
	} else {
		Filling({
			addr: f.head_addr + 2 * f.ready_count.to_u32(),
			cycles_left: f.fill_left.to_u64(),
		})
	}
	Stream({ head_addr: f.head_addr, ready_count: f.ready_count, in_flight })
}
