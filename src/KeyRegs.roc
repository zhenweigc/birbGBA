import Bits

KeyRegs :: {
	keyinput : U16,
	keycnt : U16,
}.{
	init : () -> KeyRegs
	init = || {
		keyinput: 0x03FF,
		keycnt: 0,
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
				Ok({ ..rgs, keycnt: val.bitwise_and(0b1100_0011_1111_1111) })
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
