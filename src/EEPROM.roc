import Bits

EEPROM :: {
	bytes : List(U8),
	saved : [None, Some({ time : U64, ecc : List(U8) })],
	phase : [
		Idle,
		AwaitSecondBit,
		Address({ op : [ReadBlock, WriteBlock], block_addr : U16, seen : U8 }),
		AwaitReadStop(U16),
		WriteData({ block_addr : U16, bits : U64, seen : U8 }),
		ReadOut({ block_addr : U16, sent : U8 }),
		AwaitWriteStop({ block_addr : U16, bits : U64 }),
	],
	size : [Unknown, Small, Large],
}.{
	init : () -> EEPROM
	init = || { bytes: List.repeat(0xFF, 0x2000), saved: None, phase: Idle, size: Unknown }

	get_bytes : EEPROM -> List(U8)
	get_bytes = |s| s.bytes

	get_saved : EEPROM -> [None, Some({ time : U64, ecc : List(U8) })]
	get_saved = |s| s.saved

	bytes_for_save : EEPROM -> [None, Some(List(U8))]
	bytes_for_save = |eeprom| {
		match eeprom.size {
			Unknown => None
			Small => Some(eeprom.bytes.take_first(512))
			Large => Some(eeprom.bytes.take_first(8192))
		}
	}

	hint_size_from_dma : EEPROM, U32 -> EEPROM
	hint_size_from_dma = |eeprom, halfword_count| {
		if (eeprom.size != Unknown) return eeprom
		{
			..eeprom,
			size: if halfword_count == 9 or halfword_count == 73 {
				Small # Stolen from NBA
			} else if halfword_count == 17 or halfword_count == 81 {
				Large
			} else {
				# dbg (UnexpectedEepromDmaLength(halfword_count))
				Unknown
			},
		}
	}

	write16 : EEPROM, U16 -> Try(EEPROM, [OutOfBounds])
	write16 = |eeprom, halfword| {
		if (eeprom.size == Unknown) return Ok(eeprom)
		match eeprom.phase {
			# Referring to mGBA
			Idle | ReadOut(_) => # ReadOut does not call a func by itself, it's more of a passive state waiting for consumption
				if (halfword.bitwise_and(0b1) == 0) Ok({ ..eeprom, phase: Idle }) else Ok({ ..eeprom, phase: AwaitSecondBit })
			AwaitSecondBit => {
				if halfword.bitwise_and(0b1) == 0 {
					Ok({ ..eeprom, phase: Address({ op: WriteBlock, block_addr: 0, seen: 0 }) })
				} else {
					Ok({ ..eeprom, phase: Address({ op: ReadBlock, block_addr: 0, seen: 0 }) })
				}
			}
			Address({ op, block_addr, seen }) => {
				next_addr = block_addr.shl_wrap(1).bitwise_or(halfword.bitwise_and(1))
				next_seen = seen + 1
				if (next_seen == 6 and eeprom.size == Small) or (next_seen == 14 and eeprom.size == Large) {
					block = next_addr.bitwise_and(0b11111_11111)
					return Ok({
						..eeprom,
						phase: match op {
							ReadBlock => AwaitReadStop(block)
							WriteBlock => WriteData({ block_addr: block, bits: 0, seen: 0 })
						},
					})
				}
				Ok({ ..eeprom, phase: Address({ op, block_addr: next_addr, seen: next_seen }) })
			}
			# Technically terminator should be 0, but there are always rogue ROM
			AwaitReadStop(block) => Ok({ ..eeprom, phase: ReadOut({ block_addr: block, sent: 0 }) })
			WriteData({ block_addr, bits, seen }) => {
				next_bits = bits.shl_wrap(1).bitwise_or(halfword.bitwise_and(1).to_u64())
				if (seen < 63) return Ok({ ..eeprom, phase: WriteData({ block_addr, bits: next_bits, seen: seen + 1 }) })
				Ok({ ..eeprom, phase: AwaitWriteStop({ block_addr, bits: next_bits }) })
			}
			AwaitWriteStop({ block_addr, bits }) => {
				Ok({
					..eeprom,
					bytes: [56.U8, 48, 40, 32, 24, 16, 8, 0].map(|shift| bits.shr_wrap(shift).to_u8_wrap())
						|> List.fold_try(
							{ bytes: eeprom.bytes, idx: block_addr.to_u64() * 8 },
							|state, byte| {
								Ok({ bytes: state.bytes.set(state.idx, byte)?, idx: state.idx + 1 })
							},
						)?.bytes,
					phase: Idle,
				})
			}
		}
	}

	read16 : EEPROM -> Try((EEPROM, U16), [OutOfBounds])
	read16 = |eeprom| {
		match eeprom.phase {
			ReadOut({ block_addr, sent }) => {
				if (sent < 4) return Ok(({ ..eeprom, phase: ReadOut({ block_addr, sent: sent + 1 }) }, 0))
				idx_of_byte = block_addr.to_u64().times_wrap(8) + (sent.to_u64() - 4) // 8
				bit_of_byte = 7 - (sent - 4).mod_by(8)
				Ok((
					{ ..eeprom, phase: if (sent == 67) Idle else ReadOut({ block_addr, sent: sent + 1 }) },
					Bits.get_seg_of_u16_certain(
						eeprom.bytes.get(idx_of_byte)?.to_u16(),
						bit_of_byte,
						1,
					),
				))
			}
			# Not accurate if you check out mGBA & NBA, they have a busy-or-not check and will rtn 0 upon busy
			# So for now, the EEPROM is on turbo mode upon write commit, it is way faster than actual hardware.
			# I hope there is no ROM rely on slowness of the EEPROM
			Idle | AwaitSecondBit | Address(_) | AwaitReadStop(_) | WriteData(_) | AwaitWriteStop(_) => Ok((eeprom, 1))
		}
	}

	set_saved : EEPROM, [None, Some({ time : U64, ecc : List(U8) })] -> EEPROM
	set_saved = |eeprom, given| { ..eeprom, saved: given }

	from_save : List(U8) -> Try(EEPROM, [InvalidSaveLength])
	from_save = |bytes| {
		if (bytes.len() != 512 and bytes.len() != 8192) return Err(InvalidSaveLength)
		Ok({
			bytes: if (bytes.len() != 512) bytes else bytes.concat(List.repeat(0xFF, 8192 - bytes.len())),
			saved: None,
			phase: Idle,
			size: Unknown,
		})
	}

	repair_save : List(U8),
	List(U8),
	List([None, Some(U32)]) -> Try(
		List(U8),
		[OutOfBounds, Uncorrectable, InvalidEccLength, InvalidSaveLength],
	)
	repair_save = |save, ecc, corrections| {
		if (save.len() != 512 and save.len() != 8192) return Err(InvalidSaveLength)
		if (ecc.len() != (save.len() + 1)) return Err(InvalidEccLength)
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
