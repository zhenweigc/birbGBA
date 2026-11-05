import SoundState

SoundRegs :: {
	state : Box(SoundState),
}.{
	init : () -> SoundRegs
	init = || { state: Box.box(SoundState.init()) }

	read8 : SoundRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32), OutOfBounds])
	read8 = |rgs, addr| SoundState.read8(Box.unbox(rgs.state), addr)

	read16 : SoundRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32), OutOfBounds])
	read16 = |rgs, addr| SoundState.read16(Box.unbox(rgs.state), addr)

	read32 : SoundRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32), OutOfBounds])
	read32 = |rgs, addr| SoundState.read32(Box.unbox(rgs.state), addr)

	write8 : SoundRegs, U32, U8 -> Try(SoundRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write8 = |rgs, addr, val| {
		state = Box.unbox(rgs.state)
		if (unchanged_write(addr, W8, !SoundState.master_enabled(state))) return Ok(rgs)
		new_state = SoundState.write8(state, addr, val)?
		Ok({ state: Box.box(new_state) })
	}

	write16 : SoundRegs, U32, U16 -> Try(SoundRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write16 = |rgs, addr, val| {
		state = Box.unbox(rgs.state)
		if (unchanged_write(addr, W16, !SoundState.master_enabled(state))) return Ok(rgs)
		new_state = SoundState.write16(state, addr, val)?
		Ok({ state: Box.box(new_state) })
	}

	write32 : SoundRegs, U32, U32 -> Try(SoundRegs, [UnsupportedIORegOffset(U32), OutOfBounds])
	write32 = |rgs, addr, val| {
		state = Box.unbox(rgs.state)
		if (unchanged_write(addr, W32, !SoundState.master_enabled(state))) return Ok(rgs)
		new_state = SoundState.write32(state, addr, val)?
		Ok({ state: Box.box(new_state) })
	}

	on_timer_overflow : SoundRegs, U8 -> Try((SoundRegs, { fifo_a : Bool, fifo_b : Bool }), [OutOfBounds])
	on_timer_overflow = |rgs, overflow_mask| {
		if (overflow_mask.bitwise_and(3) == 0) return Ok((rgs, { fifo_a: False, fifo_b: False }))

		state = Box.unbox(rgs.state)
		if (!SoundState.master_enabled(state)) return Ok((rgs, { fifo_a: False, fifo_b: False }))
		if (!SoundState.fifo_timer_hit(state, overflow_mask)) return Ok((rgs, { fifo_a: False, fifo_b: False }))

		(new_state, requests) = SoundState.on_timer_overflow(state, overflow_mask)?
		Ok(({ state: Box.box(new_state) }, requests))
	}
}

# No point of unbox if the write in section explicitly returns same rgs
unchanged_write : U32, [W8, W16, W32], Bool -> Bool
unchanged_write = |addr, width, master_off| {
	match width {
		W8 => match addr {
			0x66 | 0x67 | 0x6A | 0x6B | 0x6E | 0x6F | 0x76 | 0x77 | 0x7A | 0x7B | 0x7E | 0x7F | 0x85 | 0x86 | 0x87 | 0x8A | 0x8B => True
			x if x >= 0xA8 and x < 0xB0 => True
			x if (x >= 0x60 and x <= 0x81) or (x >= 0xA0 and x < 0xA8) => master_off
			_ => False
		}
		W16 => match addr {
			0x66 | 0x6A | 0x6E | 0x76 | 0x7A | 0x7E | 0x86 | 0x8A | 0xA8 | 0xAA | 0xAC | 0xAE => True
			x if ((x >= 0x60 and x <= 0x80) or (x >= 0xA0 and x < 0xA8)) and x.mod_by(2) == 0 => master_off
			_ => False
		}
		W32 => match addr {
			0xA8 | 0xAC => True
			x if ((x >= 0x60 and x < 0x80) or (x >= 0xA0 and x < 0xA8)) and x.mod_by(4) == 0 => master_off
			_ => False
		}
	}
}
