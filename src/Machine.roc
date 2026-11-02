import Bits
import Bus
import Cpu
import Ppu
import SystemRegs
import DisplayRegs
import TimerRegs
import DmaRegs
import SoundRegs
import IoRegs
import KeyRegs

FetchedCode : [Opcode(U32), Unmapped(U32)] # The 2nd option is really a placeholder for open bus

Machine :: {
	bus : Bus,
	cpu : Cpu,
	ppu : Ppu,
	# Need to put unfinished Cpu IO status here when DMA hold the Bus
	suspended_cpu : [None, Resume(Box(Cpu.Execution_state))],
	power_state : [Running, Halted, Stopped],
	# DMA Channels with lower priority are paused until channels with higher priority have completed.
	dma_owner : [None, Channel(U8)],
	now : U64,
	next_lcd_at : U64,
	next_lcd_event : [EnterHBlank, NextScanline, VideoDMARequest],
	video_dma_running : Bool,
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
			ppu: Ppu.init(),
			suspended_cpu: None,
			power_state: Running,
			dma_owner: None,
			now: 0,
			next_lcd_at: 1007,
			next_lcd_event: EnterHBlank,
			video_dma_running: False,
			pipeline: Empty,
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

	step_forward : Machine -> Try(Machine, _)
	step_forward = |before_dma| {
		m = match deal_with_dma(before_dma)? {
			DMAHandled(done) => return Ok(done)
			NoDMA(available) => available
		}
		if m.power_state == Running {
			match m.suspended_cpu {
				None => {}
				Resume(e_state) => {
					early_ret_m = { ..m, suspended_cpu: None }
					return walk_execution_state(early_ret_m, Box.unbox(e_state))
				}
			}
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
			process_event_at(m, at, timer_at)
		}
	}

	run_with_budget : Machine, U32 -> Try(Machine, _)
	run_with_budget = |m, num_of_actions| {
		if num_of_actions == 0 or m.power_state == Stopped {
			Ok(m)
		} else {
			run_with_budget(run_one_action(m)?, num_of_actions - 1)
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
				# Well yes we can literally use recursion here
				# But it seems like to downgrade the performance
				# So this func will call a (almost identical) recursive version
				advance_events_to(m, target)
			} else {
				Ok({
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
		} else {
			run_until(run_one_action(m)?, target, num_of_actions - 1)
		}
	}
}

# Have to cut of the OG big recursive func into several pieces
# Just for better perf and less memcpy
walk_execution_state : Machine, Cpu.Execution_state -> Try(Machine, _)
walk_execution_state = |m, state| {
	match state {
		Complete(done) => complete_execution(m, done)
		_ => walk_memory_execution_state(m, state)
	}
}

walk_memory_execution_state : Machine, Cpu.Execution_state -> Try(Machine, _)
walk_memory_execution_state = |before_dma, state| {
	# Here comes DMA IO 'interruption',
	# It can occupy the bus in the middle of IO under some scenarios
	can_yield : Cpu.Execution_state -> Bool
	can_yield = |e_state| {
		match e_state {
			R(_) => True # Well IO hasnt start so yes
			W(box) => match box.continuation {
				StoreAndFinish(_) => True
				WriteMultiple(_) => True
				SetRegAndFinish(_) => False # SWP/SWPB, should be atomic
			}
			Complete(_) => False
		}
	}
	m = if can_yield(state) {
		match deal_with_dma(before_dma)? {
			NoDMA(same) => same
			DMAHandled(done) => {
				resume_state = match state {
					R(box) => R({ ..box, access_kind: NonSequential })
					W(box) => W({ ..box, access_kind: NonSequential })
					# No way we reach this after can_yield()?
					Complete(_) => return Err(WTFisThis)
				}
				# Well DMA rush out first, so we gotta early return
				return Ok({ ..done, suspended_cpu: Resume(Box.box(resume_state)) })
			}
		}
	} else {
		before_dma
	}
	match state {
		Complete(done) => complete_execution(m, done)
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
				Updated(x) => Box.unbox(x)
			}
			cpu_continue = Cpu.resume_read(
				box.cpu,
				raw_val,
				box.continuation,
			)?
			walk_memory_execution_state(mark_fetch_nonsequential({ ..io_delay_applied_machine, bus: new_bus }), cpu_continue)
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
			scheduled_dma_rgs = DmaRegs.schedule_pending(post_write_bus.io_regs.dmas, io_delay_applied_machine.now)
			final_bus = { ..post_write_bus, io_regs: { ..post_write_bus.io_regs, dmas: scheduled_dma_rgs } }
			cpu_continue = Cpu.resume_write(
				box.cpu,
				box.continuation,
			)?
			walk_memory_execution_state(mark_fetch_nonsequential({ ..io_delay_applied_machine, bus: final_bus }), cpu_continue)
		}
	}
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

to_bus_width : [W16, W32] -> [W8, W16, W32] # All these just to calm down the compiler
to_bus_width = |w| if (w == W16) W16 else W32

timed_read : Machine, [W16, W32], U32, [NonSequential, Sequential] -> Try((Machine, U32), _)
timed_read = |m, width, addr, req_kind| {
	bus_width = to_bus_width(width)
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
		Updated(x) => Box.unbox(x) # Again, side effect of reading
	}
	Ok(({ ..advanced, bus: new_bus }, intermediate.val))
}

dma_read : Machine, [W16, W32], U32, [NonSequential, Sequential] -> Try((Machine, U32), _)
dma_read = |m, width, addr, req_kind| {
	aligned_addr = if (width == W16) addr.bitwise_and(0xFFFFFFFE) else addr.bitwise_and(0xFFFFFFFC)
	timed_read(m, width, aligned_addr, req_kind) # Machine + read val
}

timed_write : Machine, [W16, W32], U32, U32, [NonSequential, Sequential] -> Try(Machine, _)
timed_write = |m, width, addr, val, req_kind| {
	bus_width = to_bus_width(width)
	cycles_needed = Bus.base_access_cycles(m.bus, bus_width, addr, req_kind)?
	advanced = Machine.advance_to(m, m.now + cycles_needed)?
	new_bus = match width {
		W16 => Bus.write16(advanced.bus, addr, val.to_u16_wrap())?
		W32 => Bus.write32(advanced.bus, addr, val)?
	}
	new_dma_rgs = DmaRegs.schedule_pending(new_bus.io_regs.dmas, advanced.now)
	Ok({ ..advanced, bus: { ..new_bus, io_regs: { ..new_bus.io_regs, dmas: new_dma_rgs } } })
}

dma_write : Machine, [W16, W32], U32, U32, [NonSequential, Sequential] -> Try(Machine, _)
dma_write = |m, width, addr, val, req_kind| {
	aligned_addr = if (width == W16) addr.bitwise_and(0xFFFFFFFE) else addr.bitwise_and(0xFFFFFFFC)
	timed_write(m, width, aligned_addr, val, req_kind)
}

dma_transfer_selected : Machine, U8, DmaRegs.Reg, [W16, W32], [NonSequential, Sequential], [NonSequential, Sequential] -> Try(Machine, _)
dma_transfer_selected = |m, selection, reg, width, req_read_kind, req_write_kind| {
	DmaRegs.validate_transfer(reg, selection, Starting)?
	(after_read_m, val) = if reg.source_addr < 0x2000000 {
		# Trying to read BIOS/Unused zone? Kind UB
		# Luckily NBA tells us how to handle it.
		advanced = Machine.advance_to(m, m.now + 1)?
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
		(intermediate_m, before_latch_val) = dma_read(m, width, reg.source_addr, req_read_kind)?
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
	after_write_m = dma_write(after_read_m, width, reg.dest_addr, val, req_write_kind)?
	(new_dma_rgs, irq_mask) = DmaRegs.complete_unit(after_write_m.bus.io_regs.dmas, selection)?
	new_sys_rgs = SystemRegs.hardware_request_interrupts(after_write_m.bus.io_regs.system, irq_mask)
	Ok({
		..after_write_m,
		dma_owner: Channel(selection),
		bus: {
			..after_write_m.bus,
			io_regs: {
				..after_write_m.bus.io_regs,
				dmas: new_dma_rgs,
				system: new_sys_rgs,
			},
		},
	})
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

deal_with_dma : Machine -> Try([NoDMA(Machine), DMAHandled(Machine)], _)
deal_with_dma = |m| {
	release_dma : Machine -> Try(Machine, _)
	release_dma = |m_in| Ok(mark_fetch_nonsequential({ ..Machine.advance_to(m_in, m_in.now + 1)?, dma_owner: None }))
	if m.power_state == Stopped {
		Ok(NoDMA(m))
	} else {
		match DmaRegs.get_reg_ready_to_io(m.bus.io_regs.dmas, m.now) {
			None => {
				match m.dma_owner {
					None => Ok(NoDMA(m))
					Channel(_) => {
						# No ready to IO DMA yet channel is filled -> Should be freed
						Ok(DMAHandled(release_dma(m)?))
					}
				}
			}
			Transfer(selection, reg, _) => {
				DmaRegs.validate_transfer(reg, selection, Starting)?
				advanced = if (m.dma_owner == None) Machine.advance_to(m, m.now + 1)? else m
				match DmaRegs.get_reg_ready_to_io(advanced.bus.io_regs.dmas, advanced.now) {
					Transfer(next_selection, next_reg, next_width) => {
						access_kind = if (m.dma_owner == Channel(next_selection)) Sequential else NonSequential
						Ok(DMAHandled(dma_transfer_selected(advanced, next_selection, next_reg, next_width, access_kind, access_kind)?))
					}
					None => {
						# Well this can occur now, like this:
						# DMA3 pending -> vcount advance, DMA3 disabled because vcount == 162
						# selection is None now, ooof
						Ok(DMAHandled(release_dma(advanced)?))
					}
				}
			}
		}
	}
}

# Turns out ARM 7 of GBA is a 3 level pipeline
fetch_opcode : Machine, U32, [W16, W32], [NonSequential, Sequential] -> Try((Machine, FetchedCode), _)
fetch_opcode = |m, addr, width, req_kind| {
	if addr >= 0x4000 and addr < 0x100_0000 { # Unmapped reigon right after BIOS
		alignment = if (width == W16) 2 else 4
		if (addr.mod_by(alignment) != 0) return Err(MisalignedAddress(addr)) else {}
		advanced = Machine.advance_to(m, m.now + 1)?
		Ok((advanced, Unmapped(addr)))
	} else {
		(resultant_machine, returned_code) = timed_read(m, width, addr, req_kind)?
		# Machine + opcode
		Ok((resultant_machine, Opcode(returned_code)))
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
take_opcode = |before| {
	# Eliminate a un-necessary recursion as reload_pipeline() always gives Ready(_)
	m = match before.pipeline {
		Empty => reload_pipeline(before)?
		Ready(_) => before
	}
	match m.pipeline {
		Empty => Err(WTFisThis)
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

advance_events_to : Machine, U64 -> Try(Machine, _)
advance_events_to = |m, target| {
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
			(new_machine, _) = process_event_at(m, at, timer_at)?
			advance_events_to(new_machine, target)
		} else {
			Ok({
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
	}
}

complete_execution : Machine, Cpu.Execution_outcome -> Try(Machine, _)
complete_execution = |m, done| {
	# You might think this is retarded branching, but eh, this does save us from some useless memcpy :)
	cycle_consumed_machine = if (done.remaining_cycles == 0) m else Machine.advance_to(m, m.now + done.remaining_cycles)?
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
				if (KeyRegs.can_key_irq(new_ioregs.keys)
					and Bits.get_ith_bit_u16_certain(SystemRegs.get_interrupt_enables(new_ioregs.system), 12)) Running else Stopped
			}
		},
	})
}

run_one_action : Machine -> Try(Machine, _)
run_one_action = |m| {
	match m.power_state {
		Running => Machine.step_forward(m)
		Halted if SystemRegs.enable_pending(m.bus.io_regs.system) != 0 => Machine.step_forward(m)
		Halted => {
			after_dma = match deal_with_dma(m)? {
				DMAHandled(done) => return Ok(done)
				NoDMA(available) => available
			}
			next_lcd_time = after_dma.next_lcd_at
			next_timer_time = TimerRegs.next_event_at(after_dma.bus.io_regs.timers)
			next_dma_time = DmaRegs.next_ready_at(after_dma.bus.io_regs.dmas)
			closest_next = match (next_timer_time, next_dma_time) {
				(None, None) => next_lcd_time
				(At(t), None) | (None, At(t)) => next_lcd_time.min(t)
				(At(x), At(y)) => next_lcd_time.min(x).min(y)
			}
			new_m = Machine.advance_to(after_dma, closest_next)?
			Ok(new_m)
		}
		Stopped => Ok(m)
	}
}
