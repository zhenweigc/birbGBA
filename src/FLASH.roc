import Bits

FLASH :: {
	bytes : List(U8),
	saved : [None, Some({ time : U64, ecc : List(U8) })],
	bank : [Bank0, Bank1],
	read_mode : [ArrayData, ChipId],
	phase : [
		# https://mgba-emu.github.io/gbatek/#gba-cart-backup-flash-rom
		Idle,
		AwaitUnlock55,
		AwaitCommand,
		AwaitProgramByte,
		AwaitBankNumber,
		AwaitEraseUnlockAA,
		AwaitEraseUnlock55,
		AwaitEraseCommand,
	],
	chip : [SST, Macronix64, Macronix128, Panasonic, Atmel, Sanyo],
}.{
	Size : [KiB64, KiB128]

	init : FLASH.Size -> FLASH
	init = |size| {
		{
			bytes: List.repeat(0xFF, if (size == KiB64) 0x10000 else 0x20000),
			saved: None,
			bank: Bank0,
			read_mode: ArrayData,
			phase: Idle,
			chip: if (size == KiB64) SST else Macronix128,
		}
	}

	get_bytes : FLASH -> List(U8)
	get_bytes = |f| f.bytes

	get_saved : FLASH -> [None, Some({ time : U64, ecc : List(U8) })]
	get_saved = |f| f.saved

	set_saved : FLASH, [None, Some({ time : U64, ecc : List(U8) })] -> FLASH
	set_saved = |f, given| { ..f, saved: given }

	read8 : FLASH, U32 -> Try(U8, [OutOfBounds])
	read8 = |f, offset| {
		lo = offset.bitwise_and(0xFFFF).to_u64()
		if f.read_mode == ArrayData or lo > 1 {
			(f.bytes).get((if (f.bank == Bank0) 0 else 0x10000) + lo)
		} else {
			(manufacturer, device_type) = match f.chip {
				SST => (0xBF, 0xD4)
				Macronix64 => (0xC2, 0x1C)
				Macronix128 => (0xC2, 0x9)
				Panasonic => (0x32, 0x1B)
				Atmel => (0x1F, 0x3D)
				Sanyo => (0x62, 0x13)
			}
			Ok(if (lo == 0) manufacturer else device_type)
		}
	}

	write8 : FLASH, U32, U8 -> Try(FLASH, [OutOfBounds])
	write8 = |f, offset, val| {
		lo = offset.bitwise_and(0xFFFF).to_u64()
		bank_offset = if (f.bank == Bank0) 0.U64 else 0x10000
		match f.phase {
			Idle => if (val == 0xAA and lo == 0x5555) Ok({ ..f, phase: AwaitUnlock55 }) else Ok(f)
			AwaitUnlock55 =>
				if (val == 0x55 and lo == 0x2AAA) Ok({ ..f, phase: AwaitCommand }) else Ok({ ..f, phase: Idle })
			AwaitCommand =>
				if f.read_mode == ChipId and val != 0xF0 {
					Ok({ ..f, phase: Idle })
				} else if val == 0x90 and lo == 0x5555 {
					Ok({ ..f, read_mode: ChipId, phase: Idle })
				} else if val == 0xF0 and lo == 0x5555 {
					Ok({ ..f, read_mode: ArrayData, phase: Idle })
				} else if val == 0xA0 and lo == 0x5555 {
					Ok({ ..f, phase: AwaitProgramByte })
				} else if val == 0xB0 and lo == 0x5555 {
					if f.chip == Sanyo or f.chip == Macronix128 {
						Ok({ ..f, phase: AwaitBankNumber })
					} else {
						Ok({ ..f, phase: Idle })
					}
				} else if val == 0x80 and lo == 0x5555 {
					Ok({ ..f, phase: AwaitEraseUnlockAA })
				} else {
					Ok({ ..f, phase: Idle })
				}
			AwaitProgramByte => {
				# Following GBATEK, an unerased val will cause issue as it is NOT a write in
				target = bank_offset + lo
				Ok({ ..f, bytes: f.bytes.set(target, f.bytes.get(target)?.bitwise_and(val))?, phase: Idle })
			}
			AwaitBankNumber => {
				match (lo, val) {
					(0, 0) => Ok({ ..f, bank: Bank0, phase: Idle })
					(0, 1) => Ok({ ..f, bank: Bank1, phase: Idle })
					_ => Ok({ ..f, phase: Idle })
				}
			}
			AwaitEraseUnlockAA =>
				if (val == 0xAA and lo == 0x5555) Ok({ ..f, phase: AwaitEraseUnlock55 }) else Ok({ ..f, phase: Idle })
			AwaitEraseUnlock55 =>
				if (val == 0x55 and lo == 0x2AAA) Ok({ ..f, phase: AwaitEraseCommand }) else Ok({ ..f, phase: Idle })
			AwaitEraseCommand => {
				match (lo, val) {
					(0x5555, 0x10) => Ok({
						..f,
						phase: Idle,
						bytes: f.bytes.map(|_| 0xFF),
					})
					(_, 0x30) if lo.bitwise_and(0xFFF) == 0 => {
						start = bank_offset + lo
						Ok({
							..f,
							phase: Idle,
							bytes: f.bytes.map_with_index(
								|num, idx| {
									if (Bits.bits_match_64(idx, 0x1F000, start)) 0xFF else num
								},
							),
						})
					}
					_ => Ok({ ..f, phase: Idle })
				}
			}
		}
	}

	from_save : Size, List(U8) -> Try(FLASH, [InvalidSaveLength])
	from_save = |size, bytes| {
		if (size == KiB64 and bytes.len() != 0x10000) return Err(InvalidSaveLength)
		if (size == KiB128 and bytes.len() != 0x20000) return Err(InvalidSaveLength)
		Ok({
			bytes: bytes,
			bank: Bank0,
			saved: None,
			read_mode: ArrayData,
			phase: Idle,
			# Yes there are much more manufacturers, for minimum campatability this is fine
			chip: if (size == KiB64) SST else Macronix128,
		})
	}

	repair_save : List(U8),
	List(U8),
	List([None, Some(U32)]) -> Try(
		List(U8),
		[OutOfBounds, Uncorrectable, InvalidEccLength, InvalidSaveLength],
	)
	repair_save = |save, ecc, corrections| {
		if (save.len() != 0x10000 and save.len() != 0x20000) return Err(InvalidSaveLength)
		if (ecc.len() != ((save.len() + 2) // 3) * 3) return Err(InvalidEccLength)
		Ok(
			save.chunks_of(3).fold_try(
				{ offset: 0, bytes: [] },
				|state, x| {
					(c0, c1, c2) = Bits.golay_decode_tri_u8(
						(
							x.get(0).ok_or(0),
							x.get(1).ok_or(0),
							x.get(2).ok_or(0),
						),
						(
							ecc.get(state.offset)?,
							ecc.get(state.offset.plus_wrap(1))?,
							ecc.get(state.offset.plus_wrap(2))?,
						),
						corrections,
					)?
					Ok({ bytes: state.bytes.append(c0).append(c1).append(c2), offset: state.offset.plus_wrap(3) })
				},
			)?.bytes.take_first(save.len()),
		)
	}
}
