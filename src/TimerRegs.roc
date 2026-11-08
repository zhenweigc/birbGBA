import Bits

# `at` is an absolute system-cycle timestamp,
# using the same time base as Machine.now.
PendingWrite : [None, Pending({ value : U16, at : U64 })]

TimerSelection : [Timer0, Timer1, Timer2, Timer3]

TimerReg : {
	reload : U16,
	counter : U16,
	control : U16, # Effective control settings; queued changes live in pending_control.
	# Shamelessly stolen from NanoBoy
	pending_reload : PendingWrite,
	pending_control : PendingWrite,
	startup_reload_at : [None, At(U64)],
	next_tick_at : [None, At(U64)], # Next ordinary clock tick; cascade mode has no independent tick appointment.
}

TimerRegs :: {
	timer0 : TimerReg,
	timer1 : TimerReg,
	timer2 : TimerReg,
	timer3 : TimerReg,
	synced_at : U64, # Self-explanatory var, latest system-cycle timestamp fully processed by the timers.
}.{
	init : () -> TimerRegs
	init = || {
		{
			timer0: timer_init(),
			timer1: timer_init(),
			timer2: timer_init(),
			timer3: timer_init(),
			synced_at: 0,
		}
	}

	read8 : TimerRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x100 => Ok(rgs.timer0.counter.to_u8_wrap())
			0x101 => Ok(rgs.timer0.counter.shr_wrap(8).to_u8_wrap())
			0x102 => Ok(rgs.timer0.control.to_u8_wrap())
			0x103 => Ok(rgs.timer0.control.shr_wrap(8).to_u8_wrap())
			0x104 => Ok(rgs.timer1.counter.to_u8_wrap())
			0x105 => Ok(rgs.timer1.counter.shr_wrap(8).to_u8_wrap())
			0x106 => Ok(rgs.timer1.control.to_u8_wrap())
			0x107 => Ok(rgs.timer1.control.shr_wrap(8).to_u8_wrap())
			0x108 => Ok(rgs.timer2.counter.to_u8_wrap())
			0x109 => Ok(rgs.timer2.counter.shr_wrap(8).to_u8_wrap())
			0x10A => Ok(rgs.timer2.control.to_u8_wrap())
			0x10B => Ok(rgs.timer2.control.shr_wrap(8).to_u8_wrap())
			0x10C => Ok(rgs.timer3.counter.to_u8_wrap())
			0x10D => Ok(rgs.timer3.counter.shr_wrap(8).to_u8_wrap())
			0x10E => Ok(rgs.timer3.control.to_u8_wrap())
			0x10F => Ok(rgs.timer3.control.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : TimerRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x100 => Ok(rgs.timer0.counter)
			0x102 => Ok(rgs.timer0.control)
			0x104 => Ok(rgs.timer1.counter)
			0x106 => Ok(rgs.timer1.control)
			0x108 => Ok(rgs.timer2.counter)
			0x10A => Ok(rgs.timer2.control)
			0x10C => Ok(rgs.timer3.counter)
			0x10E => Ok(rgs.timer3.control)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : TimerRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x100 | 0x104 | 0x108 | 0x10C => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : TimerRegs, U32, U8 -> Try(TimerRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x100 | 0x101 => {
				old_val = match rgs.timer0.pending_reload {
					None => rgs.timer0.reload
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x100, adjusted_val)
			}
			0x102 => {
				old_val = match rgs.timer0.pending_control {
					None => rgs.timer0.control
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x102, adjusted_val)
			}
			0x103 => Ok(rgs)
			0x104 | 0x105 => {
				old_val = match rgs.timer1.pending_reload {
					None => rgs.timer1.reload
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x104, adjusted_val)
			}
			0x106 => {
				old_val = match rgs.timer1.pending_control {
					None => rgs.timer1.control
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x106, adjusted_val)
			}
			0x107 => Ok(rgs)
			0x108 | 0x109 => {
				old_val = match rgs.timer2.pending_reload {
					None => rgs.timer2.reload
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x108, adjusted_val)
			}
			0x10A => {
				old_val = match rgs.timer2.pending_control {
					None => rgs.timer2.control
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10A, adjusted_val)
			}
			0x10B => Ok(rgs)
			0x10C | 0x10D => {
				old_val = match rgs.timer3.pending_reload {
					None => rgs.timer3.reload
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10C, adjusted_val)
			}
			0x10E => {
				old_val = match rgs.timer3.pending_control {
					None => rgs.timer3.control
					Pending(x) => x.value
				}
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x10E, adjusted_val)
			}
			0x10F => Ok(rgs)
			offset if offset >= 0x110 and offset <= 0x11F => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : TimerRegs, U32, U16 -> Try(TimerRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x100 => Ok({ ..rgs, timer0: { ..rgs.timer0, pending_reload: Pending({ value: val, at: rgs.synced_at + 1 }) } })
			0x102 => Ok({ ..rgs, timer0: { ..rgs.timer0, pending_control: Pending({ value: val.bitwise_and(0b1100_0111), at: rgs.synced_at + 1 }) } })
			0x104 => Ok({ ..rgs, timer1: { ..rgs.timer1, pending_reload: Pending({ value: val, at: rgs.synced_at + 1 }) } })
			0x106 => Ok({ ..rgs, timer1: { ..rgs.timer1, pending_control: Pending({ value: val.bitwise_and(0b1100_0111), at: rgs.synced_at + 1 }) } })
			0x108 => Ok({ ..rgs, timer2: { ..rgs.timer2, pending_reload: Pending({ value: val, at: rgs.synced_at + 1 }) } })
			0x10A => Ok({ ..rgs, timer2: { ..rgs.timer2, pending_control: Pending({ value: val.bitwise_and(0b1100_0111), at: rgs.synced_at + 1 }) } })
			0x10C => Ok({ ..rgs, timer3: { ..rgs.timer3, pending_reload: Pending({ value: val, at: rgs.synced_at + 1 }) } })
			0x10E => Ok({ ..rgs, timer3: { ..rgs.timer3, pending_control: Pending({ value: val.bitwise_and(0b1100_0111), at: rgs.synced_at + 1 }) } })
			offset if offset >= 0x110 and offset <= 0x11E => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : TimerRegs, U32, U32 -> Try(TimerRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		lo = val.to_u16_wrap()
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x100 => write16(write16(rgs, 0x100, lo)?, 0x102, hi)
			0x104 => write16(write16(rgs, 0x104, lo)?, 0x106, hi)
			0x108 => write16(write16(rgs, 0x108, lo)?, 0x10A, hi)
			0x10C => write16(write16(rgs, 0x10C, lo)?, 0x10E, hi)
			0x110 | 0x114 | 0x118 | 0x11C => Ok(rgs)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	next_event_at : TimerRegs -> [None, At(U64)]
	next_event_at = |rgs| {
		earlier_event(
			earlier_event(
				timer_next_event_at(rgs.timer0),
				timer_next_event_at(rgs.timer1),
			),
			earlier_event(
				timer_next_event_at(rgs.timer2),
				timer_next_event_at(rgs.timer3),
			),
		)
	}

	sync_idle_to : TimerRegs, U64 -> Try(TimerRegs, [WrongEventTime])
	sync_idle_to = |rgs, target| sync_idle_to_known_next(rgs, target, next_event_at(rgs))

	sync_idle_to_known_next : TimerRegs, U64, [None, At(U64)] -> Try(TimerRegs, [WrongEventTime])
	sync_idle_to_known_next = |rgs, target, nxt_action_time| {
		if target < rgs.synced_at {
			Err(WrongEventTime)
		} else {
			match nxt_action_time {
				At(t) if t <= target => Err(WrongEventTime)
				_ => Ok({ ..rgs, synced_at: target })
			}
		}
	}

	# Process all potential update/tick at the given timestamp
	# ticks -> reload writes -> control writes
	process_at : TimerRegs,
	U64 -> Try(
		(TimerRegs, { overflow_mask : U8, irq_mask : U16 }),
		[
			WrongEventTime,
			NoClock,
			StartupReloadNotImplemented,
		],
	)
	process_at = |rgs, at| {
		if at < rgs.synced_at or next_event_at(rgs) != At(at) {
			Err(WrongEventTime)
		} else {
			(r0, masks0) = process_tick_at(rgs, Timer0, at)?
			(r1, masks1) = process_tick_at(r0, Timer1, at)?
			(r2, masks2) = process_tick_at(r1, Timer2, at)?
			(current, masks3) = process_tick_at(r2, Timer3, at)?
			overflow_mask = masks0.overflow_mask.bitwise_or(masks1.overflow_mask).bitwise_or(masks2.overflow_mask).bitwise_or(masks3.overflow_mask)
			irq_mask = masks0.irq_mask.bitwise_or(masks1.irq_mask).bitwise_or(masks2.irq_mask).bitwise_or(masks3.irq_mask)
			t0_reloaded = apply_pending_reload(current.timer0, at)
			t1_reloaded = apply_pending_reload(current.timer1, at)
			t2_reloaded = apply_pending_reload(current.timer2, at)
			t3_reloaded = apply_pending_reload(current.timer3, at)
			t0_final = apply_pending_control(t0_reloaded, at, Timer0)
			t1_final = apply_pending_control(t1_reloaded, at, Timer1)
			t2_final = apply_pending_control(t2_reloaded, at, Timer2)
			t3_final = apply_pending_control(t3_reloaded, at, Timer3)
			Ok((
				{ timer0: t0_final, timer1: t1_final, timer2: t2_final, timer3: t3_final, synced_at: at },
				{ overflow_mask: overflow_mask, irq_mask: irq_mask },
			))
		}
	}

	halt_batch_span : TimerRegs, U64, U32 -> [NoBatch, Batch({ last_at : U64, actions : U32 })]
	halt_batch_span = |rgs, limit, budget| {
		fully_disabled : TimerReg -> Bool
		fully_disabled = |reg| {
			!Bits.get_ith_bit_u16_certain(reg.control, 7)
				and reg.next_tick_at == None and reg.pending_reload == None
				and reg.pending_control == None and reg.startup_reload_at == None
		}
		if (budget < 2) return NoBatch
		if fully_disabled(rgs.timer1)
			and fully_disabled(rgs.timer2) and fully_disabled(rgs.timer3) {
			timer0 = rgs.timer0
			if timer0.pending_reload == None and timer0.pending_control == None and timer0.startup_reload_at == None {
				match clock_period(timer0, Timer0) {
					NoClock => return NoBatch
					Period(p) => {
						match timer0.next_tick_at {
							At(t) if t > rgs.synced_at => {
								# Leave room to schedule the tick following the batch.
								safe_limit = limit.min(U64.highest.minus_wrap(p))
								if (t > safe_limit) return NoBatch
								# Exclude the overflow tick; it must take the normal event path.
								batch_tick_count = (1 + (safe_limit - t) // p)
									.min(65535 - timer0.counter.to_u64())
									.min(budget.to_u64())
								if (batch_tick_count < 2) return NoBatch
								# Each batched ordinary tick replaces one original Halt action.
								return Batch({
									last_at: t + (batch_tick_count - 1).times_wrap(p),
									actions: batch_tick_count.to_u32_wrap(),
								})
							}
							_ => return NoBatch
						}
					}
				}
			}
		}
		NoBatch
	}

	# Try to fast forward timer reg ticks together for better perf
	# The entire point of this function is, fast forward if all enabled timer regs
	# has no overflow, pending write, or startup event.
	try_batch_ticks_to_known_next : TimerRegs, U64, U64 -> [NoBatch, Batched({ timers : TimerRegs, last_at : U64 })]
	try_batch_ticks_to_known_next = |rgs, limit, first_at| {
		batch_one : TimerReg, TimerSelection, U64 -> { counter : U16, next_tick_at : [None, At(U64)], last_at : [None, At(U64)] }
		batch_one = |reg, selection, batch_limit| {
			match reg.next_tick_at {
				None => { counter: reg.counter, next_tick_at: reg.next_tick_at, last_at: None }
				At(t) if t > batch_limit => { counter: reg.counter, next_tick_at: reg.next_tick_at, last_at: None }
				At(t) => {
					match clock_period(reg, selection) {
						NoClock => { counter: reg.counter, next_tick_at: reg.next_tick_at, last_at: None }
						Period(p) => {
							num_of_timer_tick_until_batch_limit = 1 + (batch_limit - t) // p
							# batch_limit is before overflow, so counter + tick count fits in U16.
							new_counter = reg.counter + num_of_timer_tick_until_batch_limit.to_u16_wrap()
							next_tick_time = t + num_of_timer_tick_until_batch_limit * p
							new_tick_at = At(next_tick_time)
							last_at = At(next_tick_time - p)
							{ counter: new_counter, next_tick_at: new_tick_at, last_at: last_at }
						}
					}
				}
			}
		}
		if (first_at <= rgs.synced_at) return NoBatch
		timer0_moment = moment_needs_process(rgs.timer0, Timer0)
		match timer0_moment {
			At(t) if t <= first_at => return NoBatch
			_ => {}
		}
		timer1_moment = moment_needs_process(rgs.timer1, Timer1)
		match timer1_moment {
			At(t) if t <= first_at => return NoBatch
			_ => {}
		}
		timer2_moment = moment_needs_process(rgs.timer2, Timer2)
		match timer2_moment {
			At(t) if t <= first_at => return NoBatch
			_ => {}
		}
		timer3_moment = moment_needs_process(rgs.timer3, Timer3)
		winner = earlier_event(
			earlier_event(timer0_moment, timer1_moment),
			earlier_event(timer2_moment, timer3_moment),
		)
		batch_limit = match winner {
			None => limit
			At(t) => {
				if (t == 0) return NoBatch
				limit.min(t - 1)
			}
		}
		if (first_at > batch_limit) return NoBatch
		r0 = batch_one(rgs.timer0, Timer0, batch_limit)
		r1 = batch_one(rgs.timer1, Timer1, batch_limit)
		r2 = batch_one(rgs.timer2, Timer2, batch_limit)
		r3 = batch_one(rgs.timer3, Timer3, batch_limit)
		last = later_event(
			later_event(r0.last_at, r1.last_at),
			later_event(r2.last_at, r3.last_at),
		)
		last_at = match last {
			At(t) if first_at < t => t
			_ => return NoBatch
		}
		Batched({
			timers: {
				timer0: { ..rgs.timer0, counter: r0.counter, next_tick_at: r0.next_tick_at },
				timer1: { ..rgs.timer1, counter: r1.counter, next_tick_at: r1.next_tick_at },
				timer2: { ..rgs.timer2, counter: r2.counter, next_tick_at: r2.next_tick_at },
				timer3: { ..rgs.timer3, counter: r3.counter, next_tick_at: r3.next_tick_at },
				synced_at: last_at,
			},
			last_at: last_at,
		})
	}

	next_batch_boundary_at : TimerRegs -> [None, At(U64)]
	next_batch_boundary_at = |rgs| {
		earlier_event(
			earlier_event(
				moment_needs_process(rgs.timer0, Timer0),
				moment_needs_process(rgs.timer1, Timer1),
			),
			earlier_event(
				moment_needs_process(rgs.timer2, Timer2),
				moment_needs_process(rgs.timer3, Timer3),
			),
		)
	}
}

timer_init : () -> TimerReg
timer_init = || {
	{
		reload: 0,
		counter: 0,
		control: 0,
		pending_reload: None,
		pending_control: None,
		startup_reload_at: None,
		next_tick_at: None,
	}
}

process_tick_at : TimerRegs,
TimerSelection,
U64 -> Try(
	(TimerRegs, { overflow_mask : U8, irq_mask : U16 }),
	[
		StartupReloadNotImplemented,
		WrongEventTime,
		NoClock,
	],
)
process_tick_at = |rgs, selection, at| {
	reg = pick_reg(rgs, selection)
	if reg.startup_reload_at == At(at) {
		Err(StartupReloadNotImplemented)
	} else {
		match reg.next_tick_at {
			None => Ok((rgs, { overflow_mask: 0, irq_mask: 0 }))
			At(x) if x > at => Ok((rgs, { overflow_mask: 0, irq_mask: 0 }))
			At(x) if x == at => {
				match clock_period(reg, selection) {
					NoClock => Err(NoClock)
					Period(p) => {
						# when at is triggered it should just be Clock mode
						(rgs_after_tick, masks) = tick(rgs, selection, Clock)
						reg_after_tick = pick_reg(rgs_after_tick, selection)
						reg_with_next = { ..reg_after_tick, next_tick_at: At(at + p) }
						current = put_reg(rgs_after_tick, selection, reg_with_next)
						Ok((current, masks))
					}
				}
			}
			_ => Err(WrongEventTime)
		}
	}
}

# Process one supplied counting pulse without advancing system time.
# An overflow reloads the counter and propagates a Cascade pulse to the next timer reg, no wrap around!
tick : TimerRegs, TimerSelection, [Clock, Cascade] -> (TimerRegs, { overflow_mask : U8, irq_mask : U16 })
tick = |rgs, selection, source| {
	reg_to_tick = pick_reg(rgs, selection)
	source_mismatch = match source {
		Clock => selection != Timer0 and Bits.get_ith_bit_u16_certain(reg_to_tick.control, 2)
		Cascade => selection == Timer0 or !Bits.get_ith_bit_u16_certain(reg_to_tick.control, 2)
	}
	if !Bits.get_ith_bit_u16_certain(reg_to_tick.control, 7) {
		(rgs, { overflow_mask: 0, irq_mask: 0 })
	} else if source_mismatch {
		(rgs, { overflow_mask: 0, irq_mask: 0 })
	} else {
		(reg, overflow) = timer_tick(reg_to_tick)
		(updated_timer_rgs, overflow_mask, irq_mask, nxt) = match selection {
			Timer0 => ({ ..rgs, timer0: reg }, 0b1, 0b1000, Timer1)
			Timer1 => ({ ..rgs, timer1: reg }, 0b10, 0b1_0000, Timer2)
			Timer2 => ({ ..rgs, timer2: reg }, 0b100, 0b10_0000, Timer3)
			# Well there is no wrap around for cascade, so treat it as a None
			Timer3 => ({ ..rgs, timer3: reg }, 0b1000, 0b100_0000, Timer0)
		}
		if !overflow {
			(updated_timer_rgs, { overflow_mask: 0, irq_mask: 0 })
		} else {
			interrupt_masking = if (Bits.get_ith_bit_u16_certain(reg.control, 6)) irq_mask else 0
			if nxt == Timer0 {
				(
					updated_timer_rgs,
					{
						overflow_mask: overflow_mask,
						irq_mask: interrupt_masking,
					},
				)
			} else {
				(t, b) = tick(updated_timer_rgs, nxt, Cascade)
				(
					t,
					{
						overflow_mask: b.overflow_mask.bitwise_or(overflow_mask),
						irq_mask: b.irq_mask.bitwise_or(interrupt_masking),
					},
				)
			}
		}
	}
}

timer_tick : TimerReg -> (TimerReg, Bool)
timer_tick = |reg| {
	old_val = reg.counter
	if old_val < 0xFFFF {
		({ ..reg, counter: old_val + 1 }, False)
	} else {
		# Incrementing a counter at 0xFFFF causes overflow.
		({ ..reg, counter: reg.reload }, True)
	}
}

apply_pending_reload : TimerReg, U64 -> TimerReg
apply_pending_reload = |reg, now| {
	match reg.pending_reload {
		None => reg
		Pending(x) => {
			if now < x.at {
				reg # Bro is too early
			} else {
				{ ..reg, reload: x.value, pending_reload: None }
			}
		}
	}
}

apply_pending_control : TimerReg, U64, TimerSelection -> TimerReg
apply_pending_control = |reg, now, selection| {
	match reg.pending_control {
		None => reg
		Pending(x) => {
			if now < x.at {
				reg
			} else {
				old_enabled = Bits.get_ith_bit_u16_certain(reg.control, 7)
				new_enabled = Bits.get_ith_bit_u16_certain(x.value, 7)
				if !new_enabled {
					{
						..reg,
						control: x.value,
						pending_control: None,
						next_tick_at: None,
						startup_reload_at: None,
					}
				} else if old_enabled {
					intermediate_reg = { ..reg, control: x.value, pending_control: None }
					period = clock_period(intermediate_reg, selection)
					match period {
						Period(p) => {
							..intermediate_reg,
							next_tick_at: At(x.at + (p - x.at.mod_by(p))),
						}
						NoClock => { ..intermediate_reg, next_tick_at: None } # Already enabled here, so NoClock -> cascade.
					}
				} else {
					intermediate_reg = {
						..reg,
						control: x.value,
						pending_control: None,
					}
					match clock_period(intermediate_reg, selection) {
						NoClock => { ..intermediate_reg, counter: reg.reload, next_tick_at: None }
						Period(p) => {
							remainder = x.at.mod_by(p)
							next_multiple = x.at + (p - remainder)
							# https://codeberg.org/nba-emu/NanoBoyAdvance/issues/331
							# TLDR, When a timer is re-enabled with counter == 0xFFFF, it may overflow
							# before the startup reload takes effect, requesting an IRQ if enabled.
							if remainder == 0 and reg.counter == 0xFFFF {
								{
									..intermediate_reg,
									next_tick_at: At(next_multiple),
									startup_reload_at: None,
								}
							} else {
								{
									..intermediate_reg,
									next_tick_at: At(next_multiple + 1),
									counter: reg.reload,
								}
							}
						}
					}
				}
			}
		}
	}
}

pick_reg : TimerRegs, TimerSelection -> TimerReg
pick_reg = |rgs, selection| {
	match selection {
		Timer0 => rgs.timer0
		Timer1 => rgs.timer1
		Timer2 => rgs.timer2
		Timer3 => rgs.timer3
	}
}

put_reg : TimerRegs, TimerSelection, TimerReg -> TimerRegs
put_reg = |rgs, selection, reg| {
	match selection {
		Timer0 => { ..rgs, timer0: reg }
		Timer1 => { ..rgs, timer1: reg }
		Timer2 => { ..rgs, timer2: reg }
		Timer3 => { ..rgs, timer3: reg }
	}
}

clock_period : TimerReg, TimerSelection -> [NoClock, Period(U64)]
clock_period = |reg, selection| {
	if !Bits.get_ith_bit_u16_certain(reg.control, 7) {
		NoClock
	} else if selection != Timer0 and Bits.get_ith_bit_u16_certain(reg.control, 2) {
		NoClock
	} else {
		match reg.control.bitwise_and(0b11) {
			0 => Period(1)
			0b1 => Period(64)
			0b10 => Period(256)
			_ => Period(1024)
		}
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

later_event : [None, At(U64)], [None, At(U64)] -> [None, At(U64)]
later_event = |t1, t2| {
	match (t1, t2) {
		(None, None) => None
		(None, At(t)) | (At(t), None) => At(t)
		(At(x), At(y)) => At(x.max(y))
	}
}

timer_next_event_at : TimerReg -> [None, At(U64)]
timer_next_event_at = |reg| {
	earlier_event(
		earlier_event(
			match reg.pending_control {
				Pending(x) => At(x.at)
				None => None
			},
			match reg.pending_reload {
				Pending(x) => At(x.at)
				None => None
			},
		),
		earlier_event(reg.startup_reload_at, reg.next_tick_at),
	)
}

moment_needs_process : TimerReg, TimerSelection -> [None, At(U64)]
moment_needs_process = |reg, selection| {
	tick_boundary = match reg.next_tick_at {
		None => None
		At(t) => match clock_period(reg, selection) {
			NoClock => At(t)
			Period(p) => {
				# Overflow occurs on tick (65536 - counter)
				delta = U64.minus_wrap(65535, reg.counter.to_u64()).times_wrap(p)
				if (delta > U64.highest - t) At(t) else At(t + delta)
			}
		}
	}
	reload_at = match reg.pending_reload {
		None => None
		Pending(x) => At(x.at)
	}
	control_at = match reg.pending_control {
		None => None
		Pending(x) => At(x.at)
	}
	earlier_event(
		earlier_event(tick_boundary, reg.startup_reload_at),
		earlier_event(reload_at, control_at),
	)
}
