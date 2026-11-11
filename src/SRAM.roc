import Bits

SRAM :: {
	bytes : List(U8),
	saved : [None, Some({ time : U64, ecc : List(U8) })],
}.{
	init : () -> SRAM
	init = || { bytes: List.repeat(0xFF, 0x8000), saved: None }

	get_bytes : SRAM -> List(U8)
	get_bytes = |s| s.bytes

	get_saved : SRAM -> [None, Some({ time : U64, ecc : List(U8) })]
	get_saved = |s| s.saved

	read8 : SRAM, U32 -> Try(U8, [OutOfBounds])
	read8 = |sram, offset| (sram.bytes).get(offset.bitwise_and(0x7FFF).to_u64())

	write8 : SRAM, U32, U8 -> Try(SRAM, [OutOfBounds])
	write8 = |sram, offset, val| Ok({ ..sram, bytes: sram.bytes.set(offset.bitwise_and(0x7FFF).to_u64(), val)? })

	set_saved : SRAM, [None, Some({ time : U64, ecc : List(U8) })] -> SRAM
	set_saved = |sram, given| { ..sram, saved: given }

	from_save : List(U8) -> Try(SRAM, [InvalidSaveLength])
	from_save = |bytes| {
		if (bytes.len() != 32768) return Err(InvalidSaveLength)
		Ok({ bytes: bytes, saved: None })
	}

	gen_ecc_of_save : List(U8) -> List(U8)
	gen_ecc_of_save = |save| {
		save.chunks_of(3).fold(
			[],
			|state, x| {
				(e0, e1, e2) = Bits.golay_encode_tri_u8((
					x.get(0).ok_or(0),
					x.get(1).ok_or(0),
					x.get(2).ok_or(0),
				))
				state.append(e0).append(e1).append(e2)
			},
		)
	}

	repair_save : List(U8),
	List(U8),
	List([None, Some(U32)]) -> Try(
		List(U8),
		[OutOfBounds, Uncorrectable, InvalidEccLength, InvalidSaveLength],
	)
	repair_save = |save, ecc, corrections| {
		if (save.len() != 32768) return Err(InvalidSaveLength)
		if (ecc.len() != 32769) return Err(InvalidEccLength)
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
