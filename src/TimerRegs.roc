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
	sync_idle_to = |rgs, target| {
		if target < rgs.synced_at {
			Err(WrongEventTime)
		} else {
			nxt_action_time = next_event_at(rgs)
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
		# Mutable vars in FP? Stone toss this guy!
		var $current = rgs
		var $overflow_mask = 0
		var $irq_mask = 0
		if at < rgs.synced_at or next_event_at(rgs) != At(at) {
			Err(WrongEventTime)
		} else {
			for selection in [Timer0, Timer1, Timer2, Timer3] {
				reg = pick_reg($current, selection)
				if reg.startup_reload_at == At(at) {
					return Err(StartupReloadNotImplemented)
				} else {
					match reg.next_tick_at {
						None => {} # guess what ROC does not have continue yet.
						At(x) if x > at => {}
						At(x) if x == at => {
							match clock_period(reg, selection) {
								NoClock => return Err(NoClock)
								Period(p) => {
									# when at is triggered it should just be Clock mode
									(rgs_after_tick, masks) = tick($current, selection, Clock)
									reg_after_tick = pick_reg(rgs_after_tick, selection)
									reg_with_next = { ..reg_after_tick, next_tick_at: At(at + p) }
									$current = put_reg(rgs_after_tick, selection, reg_with_next)
									$overflow_mask = $overflow_mask.bitwise_or(masks.overflow_mask)
									$irq_mask = $irq_mask.bitwise_or(masks.irq_mask)
								}
							}
						}
						_ => return Err(WrongEventTime)
					}
				}
			}
			for selection in [Timer0, Timer1, Timer2, Timer3] {
				reg = pick_reg($current, selection)
				updated_reg = apply_pending_reload(reg, at)
				$current = put_reg($current, selection, updated_reg)
			}
			for selection in [Timer0, Timer1, Timer2, Timer3] {
				reg = pick_reg($current, selection)
				updated_reg = apply_pending_control(reg, at, selection)?
				$current = put_reg($current, selection, updated_reg)
			}
			Ok((
				{ ..$current, synced_at: at },
				{ overflow_mask: $overflow_mask, irq_mask: $irq_mask },
			))
		}
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

apply_pending_control : TimerReg, U64, TimerSelection -> Try(TimerReg, [NoClock])
apply_pending_control = |reg, now, selection| {
	match reg.pending_control {
		None => Ok(reg)
		Pending(x) => {
			if now < x.at {
				Ok(reg)
			} else {
				old_enabled = Bits.get_ith_bit_u16_certain(reg.control, 7)
				new_enabled = Bits.get_ith_bit_u16_certain(x.value, 7)
				if !new_enabled {
					Ok({
						..reg,
						control: x.value,
						pending_control: None,
						next_tick_at: None,
						startup_reload_at: None,
					})
				} else if old_enabled {
					intermediate_reg = { ..reg, control: x.value, pending_control: None }
					period = clock_period(intermediate_reg, selection)
					match period {
						Period(p) => Ok({
							..intermediate_reg,
							next_tick_at: At(x.at + (p - x.at.mod_by(p))),
						})
						NoClock => Ok({ ..intermediate_reg, next_tick_at: None }) # Already enabled here, so NoClock -> cascade.
					}
				} else {
					intermediate_reg = {
						..reg,
						control: x.value,
						pending_control: None,
					}
					match clock_period(intermediate_reg, selection) {
						NoClock => Ok({ ..intermediate_reg, counter: reg.reload, next_tick_at: None })
						Period(p) => {
							remainder = x.at.mod_by(p)
							next_multiple = x.at + (p - remainder)
							# https://codeberg.org/nba-emu/NanoBoyAdvance/issues/331
							# TLDR, When a timer is re-enabled with counter == 0xFFFF, it may overflow
							# before the startup reload takes effect, requesting an IRQ if enabled.
							if remainder == 0 and reg.counter == 0xFFFF {
								Ok({
									..intermediate_reg,
									next_tick_at: At(next_multiple),
									startup_reload_at: None,
								})
							} else {
								Ok({
									..intermediate_reg,
									next_tick_at: At(next_multiple + 1),
									counter: reg.reload,
								})
							}
						}
					}
				}
			}
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

earlier_event : [None, At(U64)], [None, At(U64)] -> [None, At(U64)]
earlier_event = |t1, t2| {
	match (t1, t2) {
		(None, None) => None
		(None, At(t)) | (At(t), None) => At(t)
		(At(x), At(y)) => At(x.min(y))
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
