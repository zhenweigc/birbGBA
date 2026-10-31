import Bits

KeyRegs :: { keyinput : U16, keycnt : U16, last_irq_pressed : [None, Some(U16)] }.{
	init : () -> KeyRegs
	init = || {
		keyinput: 0b11_1111_1111,
		keycnt: 0,
		last_irq_pressed: None,
	}

	set_pressed : KeyRegs, U16 -> KeyRegs
	set_pressed = |rgs, pressed| {
		# https://mgba-emu.github.io/gbatek/#gbakeypadinput
		convert_to_keyinput_format = pressed.bitwise_and(0b11_1111_1111).bitwise_xor(0b11_1111_1111)
		{ ..rgs, keyinput: convert_to_keyinput_format }
	}

	can_key_irq : KeyRegs -> Bool
	can_key_irq = |rgs| {
		if Bits.get_ith_bit_u16_certain(rgs.keycnt, 14) {
			selected = Bits.get_seg_of_u16_certain(rgs.keycnt, 0, 10)
			pressed = rgs.keyinput.bitwise_and(0b11_1111_1111).bitwise_xor(0b11_1111_1111)
			matched = selected.bitwise_and(pressed)
			if (Bits.get_ith_bit_u16_certain(rgs.keycnt, 15)) matched == selected else matched != 0
		} else {
			False
		}
	}

	poll_irq : KeyRegs -> (KeyRegs, Bool)
	poll_irq = |rgs| {
		# stolen from mGBA, use a prev state & bool to anti buttom spam
		if Bits.get_ith_bit_u16_certain(rgs.keycnt, 14) {
			if can_key_irq(rgs) {
				pressed = rgs.keyinput.bitwise_and(0b11_1111_1111).bitwise_xor(0b11_1111_1111)
				if Bits.get_ith_bit_u16_certain(rgs.keycnt, 15) {
					(
						{ ..rgs, last_irq_pressed: Some(pressed) },
						rgs.last_irq_pressed != Some(pressed),
					)
				} else {
					({ ..rgs, last_irq_pressed: Some(pressed) }, True)
				}
			} else {
				({ ..rgs, last_irq_pressed: None }, False)
			}
		} else {
			(rgs, False)
		}
	}

	read8 : KeyRegs, U32 -> Try(U8, [UnsupportedIORegOffset(U32)])
	read8 = |rgs, addr| {
		match addr {
			0x130 => Ok(rgs.keyinput.to_u8_wrap())
			0x131 => Ok(rgs.keyinput.shr_wrap(8).to_u8_wrap())
			0x132 => Ok(rgs.keycnt.to_u8_wrap())
			0x133 => Ok(rgs.keycnt.shr_wrap(8).to_u8_wrap())
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read16 : KeyRegs, U32 -> Try(U16, [UnsupportedIORegOffset(U32)])
	read16 = |rgs, addr| {
		match addr {
			0x130 => Ok(rgs.keyinput)
			0x132 => Ok(rgs.keycnt)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	read32 : KeyRegs, U32 -> Try(U32, [UnsupportedIORegOffset(U32)])
	read32 = |rgs, addr| {
		match addr {
			0x130 => {
				low = read16(rgs, addr)?.to_u32()
				hi = read16(rgs, addr.plus_wrap(2))?.to_u32().shl_wrap(16)
				Ok(low + hi)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write8 : KeyRegs, U32, U8 -> Try(KeyRegs, [UnsupportedIORegOffset(U32)])
	write8 = |rgs, addr, val| {
		isHi = addr.mod_by(2) == 1
		match addr {
			0x130 | 0x131 => Ok(rgs)
			0x132 | 0x133 => {
				old_val = rgs.keycnt
				adjusted_val = Bits.replace_byte(old_val, isHi, val)
				write16(rgs, 0x132, adjusted_val)
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write16 : KeyRegs, U32, U16 -> Try(KeyRegs, [UnsupportedIORegOffset(U32)])
	write16 = |rgs, addr, val| {
		match addr {
			0x130 => Ok(rgs)
			0x132 => {
				newcnt = val.bitwise_and(0b1100_0011_1111_1111)
				new_last_irq_pressed = match rgs.last_irq_pressed {
					None => None
					Some(last) => Some(last.bitwise_and(rgs.keycnt.bitwise_or(newcnt.bitwise_not())))
				}
				Ok({ ..rgs, keycnt: newcnt, last_irq_pressed: new_last_irq_pressed })
			}
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}

	write32 : KeyRegs, U32, U32 -> Try(KeyRegs, [UnsupportedIORegOffset(U32)])
	write32 = |rgs, addr, val| {
		hi = val.shr_wrap(16).to_u16_wrap()
		match addr {
			0x130 => write16(write16(rgs, 0x130, 0)?, 0x132, hi)
			_ => Err(UnsupportedIORegOffset(addr))
		}
	}
}
