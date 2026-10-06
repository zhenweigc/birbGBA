Bits :: {}.{
	get_ith_bit_u16_certain : U16, U8 -> Bool
	get_ith_bit_u16_certain = |i, j| {
		U16.shr_wrap(U16.shl_wrap(i, 16 - j - 1), 15) == 1
	}

	get_ith_bit_u32_certain : U32, U8 -> Bool
	get_ith_bit_u32_certain = |i, j| {
		U32.shr_wrap(U32.shl_wrap(i, 32 - j - 1), 31) == 1
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
	bits_match_16 = |i, mask, target| {
		U16.bitwise_and(i, mask) == target
	}

	bits_match_32 : U32, U32, U32 -> Bool
	bits_match_32 = |i, mask, target| {
		U32.bitwise_and(i, mask) == target
	}

	replace_byte : U16, Bool, U8 -> U16
	replace_byte = |old_val, isHi, incoming_val| {
		if isHi {
			incoming_val.to_u16().shl_wrap(8) + old_val.bitwise_and(0b0000_0000_1111_1111)
		} else {
			incoming_val.to_u16() + old_val.bitwise_and(0b1111_1111_0000_0000)
		}
	}
}
