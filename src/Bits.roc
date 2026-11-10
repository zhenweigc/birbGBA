Bits :: {}.{
	get_ith_bit_u16_certain : U16, U8 -> Bool
	get_ith_bit_u16_certain = |i, j| U16.shr_wrap(U16.shl_wrap(i, 16 - j - 1), 15) == 1

	get_ith_bit_u32_certain : U32, U8 -> Bool
	get_ith_bit_u32_certain = |i, j| U32.shr_wrap(U32.shl_wrap(i, 32 - j - 1), 31) == 1

	get_seg_of_u8_certain : U8, U8, U8 -> U8
	get_seg_of_u8_certain = |i, lsb, len| {
		tmp = 8 - len
		U8.shr_wrap(U8.shl_wrap(U8.shr_wrap(i, lsb), tmp), tmp)
	}

	get_seg_of_u16_certain : U16, U8, U8 -> U16
	get_seg_of_u16_certain = |i, lsb, len| {
		tmp = 16 - len
		U16.shr_wrap(U16.shl_wrap(U16.shr_wrap(i, lsb), tmp), tmp)
	}

	get_seg_of_u32_certain : U32, U8, U8 -> U32
	get_seg_of_u32_certain = |i, lsb, len| {
		tmp = 32 - len
		U32.shr_wrap(U32.shl_wrap(U32.shr_wrap(i, lsb), tmp), tmp)
	}

	bits_match_16 : U16, U16, U16 -> Bool
	bits_match_16 = |i, mask, target| U16.bitwise_and(i, mask) == target

	bits_match_32 : U32, U32, U32 -> Bool
	bits_match_32 = |i, mask, target| U32.bitwise_and(i, mask) == target

	replace_byte : U16, Bool, U8 -> U16
	replace_byte = |old_val, isHi, incoming_val| {
		if isHi {
			incoming_val.to_u16().shl_wrap(8) + old_val.bitwise_and(0b0000_0000_1111_1111)
		} else {
			incoming_val.to_u16() + old_val.bitwise_and(0b1111_1111_0000_0000)
		}
	}

	rotate_right_u32 : U32, U8 -> U32
	rotate_right_u32 = |i, j| {
		tmp = j % 32
		if (tmp == 0) i else i.shr_wrap(tmp).bitwise_or(i.shl_wrap(U8.minus_wrap(32, tmp)))
	}

	signed_extend_u32 : U32, U8 -> U32
	signed_extend_u32 = |val, e| {
		if (e == 0 or e >= 32) return val
		if (Bits.get_ith_bit_u32_certain(val, e - 1)) return val.bitwise_or(U32.highest.shl_wrap(e))
		val
	}

	arithmetic_shift_right : U32, U8 -> U32
	arithmetic_shift_right = |i, j| {
		if j == 0 or i == 0 or i == 4294967295 {
			i
		} else if j >= 32 {
			U32.minus_wrap(0, i.shr_wrap(31))
		} else {
			i.shr_wrap(j).bitwise_or(U32.minus_wrap(0, i.shr_wrap(31)).shl_wrap(U8.minus_wrap(32, j)))
		}
	}

	add_with_carry : U32, U32, Bool -> { val : U32, carry : Bool, overflow : Bool }
	add_with_carry = |i, j, b| {
		c = if (b) 1 else 0
		partial = U32.to_u64(i) + U32.to_u64(j) + U32.to_u64(c)
		res = U64.to_u32_wrap(partial)
		{
			val: res,
			carry: partial > U32.to_u64(U32.highest),
			overflow: I64.to_i32_try(
				I32.to_i64(U32.to_i32_wrap(i)) +
					I32.to_i64(U32.to_i32_wrap(j)) +
					U32.to_i64(c),
			).is_err(),
		}
	}

	bytes3_to_u12_pair : (U8, U8, U8) -> (U16, U16)
	bytes3_to_u12_pair = |(b0, b1, b2)| {
		raw1 = b0.to_u16().bitwise_or(b1.bitwise_and(0b1111).to_u16().shl_wrap(8))
		raw2 = b1.to_u16().shr_wrap(4).bitwise_or(b2.to_u16().shl_wrap(4))
		(raw1, raw2)
	}

	u12_pair_to_bytes3 : (U16, U16) -> (U8, U8, U8)
	u12_pair_to_bytes3 = |(b0, b1)| {
		raw1 = b0.to_u8_wrap()
		raw2 = b0.shr_wrap(8).to_u8_wrap().bitwise_and(0b1111).bitwise_or(b1.to_u8_wrap().bitwise_and(0b1111).shl_wrap(4))
		raw3 = b1.shr_wrap(4).to_u8_wrap()
		(raw1, raw2, raw3)
	}

	# https://www.irig106.org/docs/106-15/appendixQ.pdf
	golay_encode12 : U16 -> U32
	golay_encode12 = |data| {
		filtered = get_seg_of_u16_certain(data, 0, 12).to_u32()
		generator_matrix : List(U32)
		generator_matrix = [0xc75, 0x63b, 0xf68, 0x7b4, 0x3da, 0xd99, 0x6cd, 0x367, 0xdc6, 0xa97, 0x93e, 0x8eb]
		positions = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
		bits = positions.map(|i| get_ith_bit_u32_certain(filtered, i))
		cooking = generator_matrix.map2(bits, |mask, enable| if (enable) mask else 0)
		crc = cooking.fold(0, U32.bitwise_xor)
		filtered.shl_wrap(12).bitwise_or(crc)
	}

	# why pick syndrome as func name? no idea what is IRIG thinking
	golay_syndrome : U32 -> U16
	golay_syndrome = |candidate| {
		parity_matrix : List(U32)
		parity_matrix = [0xA4F, 0xF68, 0x7B4, 0x3DA, 0x1ED, 0xAB9, 0xF13, 0xDC6, 0x6E3, 0x93E, 0x49F, 0xC75]
		lo = get_seg_of_u32_certain(candidate, 0, 12)
		data = get_seg_of_u32_certain(candidate, 12, 12)
		positions = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
		bits = positions.map(|i| get_ith_bit_u32_certain(lo, i))
		cooking = parity_matrix.map2(bits, |mask, enable| if (enable) mask else 0)
		cooking.fold(data, U32.bitwise_xor).to_u16_wrap()
	}

	golay_init_corrections : () -> Try(List([None, Some(U32)]), [OutOfBounds])
	golay_init_corrections = || {
		add_correction = |lst, i| lst.set(golay_syndrome(i).to_u64(), Some(i))
		init = List.repeat(None, 4096).set(0, Some(0))?
		one_err_encoding = List.repeat(1.U32, 24).map_with_index(|i, idx| i.shl_wrap(idx.to_u8_wrap()))
		two_err_encoding = one_err_encoding
			.map_with_index(
				|i, idx| one_err_encoding.drop_first(idx + 1)
					.map(|j| j.bitwise_or(i)),
			).join()
		three_err_encoding = two_err_encoding
			.map(
				|x| one_err_encoding.drop_first(32 - U32.count_leading_zero_bits(x).to_u64())
					.map(|y| y.bitwise_or(x)),
			).join()
		three_err_encoding.fold_try(
			two_err_encoding.fold_try(
				one_err_encoding.fold_try(init, add_correction)?,
				add_correction,
			)?,
			add_correction,
		)
	}

	golay_decode12 : U32, List([None, Some(U32)]) -> Try(U16, [OutOfBounds, Uncorrectable])
	golay_decode12 = |candidate, corrections| {
		match corrections.get(golay_syndrome(candidate).to_u64())? {
			None => Err(Uncorrectable)
			Some(mask) => Ok(get_seg_of_u32_certain(candidate.bitwise_xor(mask), 12, 12).to_u16_wrap())
		}
	}

	golay_encode_tri_u8 : (U8, U8, U8) -> (U8, U8, U8)
	golay_encode_tri_u8 = |tri| {
		(lo, hi) = bytes3_to_u12_pair(tri)
		u12_pair_to_bytes3((golay_encode12(lo).to_u16_wrap(), golay_encode12(hi).to_u16_wrap()))
	}

	golay_decode_tri_u8 : (U8, U8, U8),
	(U8, U8, U8),
	List([None, Some(U32)]) -> Try(
		(U8, U8, U8),
		[OutOfBounds, Uncorrectable],
	)
	golay_decode_tri_u8 = |data, ecc, corrections| {
		(d0, d1) = bytes3_to_u12_pair(data)
		(e0, e1) = bytes3_to_u12_pair(ecc)
		lo = golay_decode12(d0.to_u32().shl_wrap(12).bitwise_or(e0.to_u32()), corrections)?
		hi = golay_decode12(d1.to_u32().shl_wrap(12).bitwise_or(e1.to_u32()), corrections)?
		Ok(u12_pair_to_bytes3((lo, hi)))
	}
}
