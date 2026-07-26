GPR : [R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15]

Mode : [FIQ, Sup, Abort, IRQ, Undefined, User, Sys]

Regs : { r0 : U32, r1 : U32, r2 : U32, r3 : U32, r4 : U32, r5 : U32, r6 : U32, r7 : U32, r8 : U32, r8_fiq : U32, r9 : U32, r9_fiq : U32, r10 : U32, r10_fiq : U32, r11 : U32, r11_fiq : U32, r12 : U32, r12_fiq : U32, r13 : U32, r13_fiq : U32, r13_svc : U32, r13_abt : U32, r13_irq : U32, r13_und : U32, r14 : U32, r14_fiq : U32, r14_svc : U32, r14_abt : U32, r14_irq : U32, r14_und : U32, r15 : U32 }

Conds : [EQ, NE, CS, CC, MI, PL, VS, VC, HI, LS, GE, LT, GT, LE, AL]

ShiftType : [LSL, LSR, ASR, ROR]

ArmInstructions : [DataProcessingPSRTransfer, Multiply, MultiplyLong, SingleDataSwap, BranchAndExchange, HalfwordDataTransferRegOffset, HalfwordDataTransferImmediateOffset, SingleDataTransfer, Undefined, Branch, CoprocessorDataTransfer, CoprocessorDataOperation, CoprocessorRegisterTransfer, SoftwareInterrupt, BlockDataTransfer]

DataProcessingKind : [DataProcessing, PSRTransfer]

# Alias can be Data Processing
ALUOpCode : [AND, EOR, SUB, RSB, ADD, ADC, SBC, RSC, TST, TEQ, CMP, CMN, ORR, MOV, BIC, MVN]

PSRTransferOpCode : [MSR, MRS]

Cpu := { regs : Regs, cpsr : U32, spsr_fiq : U32, spsr_svc : U32, spsr_irq : U32, spsr_und : U32, spsr_abt : U32 }

U32_carry : { val : U32, carry : Bool }

U32_carry_overflow : { val : U32, carry : Bool, overflow : Bool }

rotate_right_u32 : U32, U8 -> U32
rotate_right_u32 = |i, j| {
	tmp = j % 32
	if tmp == 0 {
		i
	} else {
		rotate_right_u32(i // 2 + 2147483648 * (i % 2), tmp - 1)
	}
}

arithmetic_shift_right : U32, U8 -> U32
arithmetic_shift_right = |i, j| {
	if j == 0 or i == 0 or i == 4294967295 {
		i
	} else {
		tmp = get_ith_bit_u32_certain(i, 31)
		if tmp {
			arithmetic_shift_right(2147483648 + i // 2, j - 1)
		} else {
			arithmetic_shift_right(i // 2, j - 1)
		}
	}
}

add_with_carry : U32, U32, Bool -> U32_carry_overflow
add_with_carry = |i, j, b| {
	c = if b {
		1
	} else {
		0
	}
	partial = U32.to_u64(i) + U32.to_u64(j) + U32.to_u64(c)
	res = U64.to_u32_wrap(partial)
	{
		val: res,
		carry: partial > U32.to_u64(U32.highest),
		overflow: match I64.to_i32_try(
			I32.to_i64(U32.to_i32_wrap(i)) +
				I32.to_i64(U32.to_i32_wrap(j)) +
				U32.to_i64(c),
		) {
			Ok(_) => Bool.False
			_ => Bool.True
		},
	}
}

# LSB is 0th bit, not 1!
get_ith_bit_u32 : U32, U8 -> Try(Bool, [WTFisThis])
get_ith_bit_u32 = |i, j| {
	if j >= 32 {
		Err(WTFisThis)
	} else {
		Ok(get_ith_bit_u32_certain(i, j))
	}
}

get_ith_bit_u32_certain : U32, U8 -> Bool
get_ith_bit_u32_certain = |i, j| {
	U32.shift_right_by(U32.shift_left_by(i, 32 - j - 1), 31) == 1
}

arm_s_flag : U32 -> Bool
arm_s_flag = |i| {
	get_ith_bit_u32_certain(i, 20)
}

get_seg_of_u32 : U32, U8, U8 -> Try(U32, [WTFisThis])
get_seg_of_u32 = |i, lsb, len| {
	if lsb > 31 or len < 1 or len > 32 - lsb {
		Err(WTFisThis)
	} else {
		Ok(get_seg_of_u32_certain(i, lsb, len))
	}
}

get_seg_of_u32_certain : U32, U8, U8 -> U32
get_seg_of_u32_certain = |i, lsb, len| {
	tmp = 32 - len
	U32.shift_right_by(U32.shift_left_by(U32.shift_right_by(i, lsb), tmp), tmp)
}

bits_match : U32, U32, U32 -> Bool
bits_match = |i, mask, target| {
	U32.bitwise_and(i, mask) == target
}

gpr_from_idx : U8 -> Try(GPR, [WTFisThis])
gpr_from_idx = |i| {
	match i {
		0 => Ok(R0)
		1 => Ok(R1)
		2 => Ok(R2)
		3 => Ok(R3)
		4 => Ok(R4)
		5 => Ok(R5)
		6 => Ok(R6)
		7 => Ok(R7)
		8 => Ok(R8)
		9 => Ok(R9)
		10 => Ok(R10)
		11 => Ok(R11)
		12 => Ok(R12)
		13 => Ok(R13)
		14 => Ok(R14)
		15 => Ok(R15)
		_ => Err(WTFisThis)
	}
}

data_processing_get_rn : U32 -> Try(GPR, [WTFisThis])
data_processing_get_rn = |i| {
	tmp = get_seg_of_u32_certain(i, 16, 4)
	gpr_from_idx(U32.to_u8_wrap(tmp))
}

data_processing_get_rn_value : U32, Cpu -> Try(U32, [InvalidMode, WTFisThis])
data_processing_get_rn_value = |i, c| {
	rn = data_processing_get_rn(i)?
	Ok(data_processing_operand_reg_value(i, rn, c)?)
}

data_processing_get_rd : U32 -> Try(GPR, [WTFisThis])
data_processing_get_rd = |i| {
	tmp = get_seg_of_u32_certain(i, 12, 4)
	gpr_from_idx(U32.to_u8_wrap(tmp))
}

# Man it's always the PC being different
data_processing_operand_reg_value : U32, GPR, Cpu -> Try(U32, [InvalidMode])
data_processing_operand_reg_value = |i, gpr, c| {
	match gpr {
		R15 => if get_ith_bit_u32_certain(i, 25) {
			Ok(c.regs.r15 + 8)
		} else if get_ith_bit_u32_certain(i, 4) {
			Ok(c.regs.r15 + 12)
		} else {
			Ok(c.regs.r15 + 8)
		}
		_ => cpu_getReg(gpr, c)
	}
}

data_processing_operands_register : U32, Cpu -> Try(U32_carry, [InvalidMode, WTFisThis, UB_ShiftbyPC])
data_processing_operands_register = |i, c| {
	rm = data_processing_get_rm(i)?
	rm_val = data_processing_operand_reg_value(i, rm, c)?
	shift_type = data_processing_get_shift_type(i)
	c_flag = cpsr_getC(c.cpsr)
	if get_ith_bit_u32_certain(i, 4) {
		x = data_processing_get_rs(i)?
		match x {
			R15 => Err(UB_ShiftbyPC)
			_ => Ok(data_processing_shift_by_register(shift_type, rm_val, cpu_getReg(x, c)?, c_flag))
		}
	} else {
		shift_imm = data_processing_get_shift_imm(i)
		Ok(data_processing_shift_by_immediate(shift_type, rm_val, shift_imm, c_flag))
	}
}

data_processing_operands_immediate : U32, Bool -> U32_carry
data_processing_operands_immediate = |i, c_flag| {
	rotate_imm = data_processing_rotate_imm(i)
	tmp = rotate_right_u32(U8.to_u32(data_processing_get_immed_8(i)), rotate_imm * 2)
	if rotate_imm == 0 {
		{ val: tmp, carry: c_flag }
	} else {
		{ val: tmp, carry: get_ith_bit_u32_certain(tmp, 31) }
	}
}

data_processing_operand2 : U32, Cpu -> Try(U32_carry, [InvalidMode, WTFisThis, UB_ShiftbyPC])
data_processing_operand2 = |i, c| {
	c_flag = cpsr_getC(c.cpsr)
	if data_processing_uses_immediate(i) {
		Ok(data_processing_operands_immediate(i, c_flag))
	} else {
		data_processing_operands_register(i, c)
	}
}

data_processing_decode : U32 -> ALUOpCode
data_processing_decode = |i| {
	# ctrl cv template: 0b0000000_1111_000000000000000000000
	# 0b0000000_????_000000000000000000000
	if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0000_000000000000000000000) {
		AND
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0001_000000000000000000000) {
		EOR
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0010_000000000000000000000) {
		SUB
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0011_000000000000000000000) {
		RSB
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0100_000000000000000000000) {
		ADD
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0101_000000000000000000000) {
		ADC
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0110_000000000000000000000) {
		SBC
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_0111_000000000000000000000) {
		RSC
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1000_000000000000000000000) {
		TST
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1001_000000000000000000000) {
		TEQ
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1010_000000000000000000000) {
		CMP
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1011_000000000000000000000) {
		CMN
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1100_000000000000000000000) {
		ORR
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1101_000000000000000000000) {
		MOV
	} else if bits_match(i, 0b0000000_1111_000000000000000000000, 0b0000000_1110_000000000000000000000) {
		BIC
	} else {
		MVN
	}
}

data_processing_shift_amount_uses_reg : U32 -> Bool
data_processing_shift_amount_uses_reg = |i| {
	get_ith_bit_u32_certain(i, 4)
}

data_processing_lsl_by_immediate : U32, U8, Bool -> U32_carry
data_processing_lsl_by_immediate = |rm_val, shift_imm, c_flag| {
	if shift_imm == 0 {
		{ val: rm_val, carry: c_flag }
	} else {
		{
			val: U32.shift_left_by(rm_val, shift_imm),
			carry: get_ith_bit_u32_certain(rm_val, 32 - shift_imm),
		}
	}
}

data_processing_lsl_by_register : U32, U32, Bool -> U32_carry
data_processing_lsl_by_register = |rm_val, rs_val, c_flag| {
	tmp = U32.to_u8_wrap(get_seg_of_u32_certain(rs_val, 0, 8))
	if tmp == 0 {
		{ val: rm_val, carry: c_flag }
	} else if tmp < 32 {
		{ val: U32.shift_left_by(rm_val, tmp), carry: get_ith_bit_u32_certain(rm_val, 32 - tmp) }
	} else if tmp == 32 {
		{ val: 0, carry: get_ith_bit_u32_certain(rm_val, 0) }
	} else {
		{ val: 0, carry: Bool.False }
	}
}

# [LSL, LSR, ASR, ROR]
data_processing_shift_by_immediate : ShiftType, U32, U8, Bool -> U32_carry
data_processing_shift_by_immediate = |s, rm_val, shift_imm, c_flag| {
	match s {
		ASR => data_processing_asr_by_immediate(rm_val, shift_imm)
		LSR => data_processing_lsr_by_immediate(rm_val, shift_imm)
		LSL => data_processing_lsl_by_immediate(rm_val, shift_imm, c_flag)
		ROR => data_processing_ror_by_immediate(rm_val, shift_imm, c_flag)
	}
}

data_processing_shift_by_register : ShiftType, U32, U32, Bool -> U32_carry
data_processing_shift_by_register = |s, rm_val, rs_val, c_flag| {
	match s {
		ASR => data_processing_asr_by_register(rm_val, rs_val, c_flag)
		LSR => data_processing_lsr_by_register(rm_val, rs_val, c_flag)
		LSL => data_processing_lsl_by_register(rm_val, rs_val, c_flag)
		ROR => data_processing_ror_by_register(rm_val, rs_val, c_flag)
	}
}

data_processing_lsr_by_immediate : U32, U8 -> U32_carry
data_processing_lsr_by_immediate = |rm_val, shift_imm| {
	if shift_imm == 0 {
		{ val: 0, carry: get_ith_bit_u32_certain(rm_val, 31) }
	} else {
		{ val: U32.shift_right_by(rm_val, shift_imm), carry: get_ith_bit_u32_certain(rm_val, shift_imm - 1) }
	}
}

data_processing_lsr_by_register : U32, U32, Bool -> U32_carry
data_processing_lsr_by_register = |rm_val, rs_val, c_flag| {
	tmp = U32.to_u8_wrap(get_seg_of_u32_certain(rs_val, 0, 8))
	if tmp == 0 {
		{ val: rm_val, carry: c_flag }
	} else if tmp < 32 {
		{ val: U32.shift_right_by(rm_val, tmp), carry: get_ith_bit_u32_certain(rm_val, tmp - 1) }
	} else if tmp == 32 {
		{ val: 0, carry: get_ith_bit_u32_certain(rm_val, 31) }
	} else {
		{ val: 0, carry: Bool.False }
	}
}

data_processing_asr_by_immediate : U32, U8 -> U32_carry
data_processing_asr_by_immediate = |rm_val, shift_imm| {
	if shift_imm == 0 {
		tmp = get_ith_bit_u32_certain(rm_val, 31)
		if !tmp {
			{ val: 0, carry: Bool.False }
		} else {
			{ val: 0xFFFFFFFF, carry: Bool.True }
		}
	} else {
		{ val: arithmetic_shift_right(rm_val, shift_imm), carry: get_ith_bit_u32_certain(rm_val, shift_imm - 1) }
	}
}

data_processing_asr_by_register : U32, U32, Bool -> U32_carry
data_processing_asr_by_register = |rm_val, rs_val, c_flag| {
	tmp = U32.to_u8_wrap(get_seg_of_u32_certain(rs_val, 0, 8))
	if tmp == 0 {
		{ val: rm_val, carry: c_flag }
	} else if tmp < 32 {
		{ val: arithmetic_shift_right(rm_val, tmp), carry: get_ith_bit_u32_certain(rm_val, tmp - 1) }
	} else {
		if !get_ith_bit_u32_certain(rm_val, 31) {
			{ val: 0, carry: Bool.False }
		} else {
			{ val: 4294967295, carry: Bool.True }
		}
	}
}

data_processing_rrx : U32, Bool -> U32_carry
data_processing_rrx = |rm_val, c_flag| {
	{
		val: match c_flag {
			Bool.True => U32.bitwise_or(2147483648, U32.shift_right_by(rm_val, 1))
			_ => U32.shift_right_by(rm_val, 1)
		},
		carry: get_ith_bit_u32_certain(rm_val, 0),
	}
}

data_processing_ror_by_immediate : U32, U8, Bool -> U32_carry
data_processing_ror_by_immediate = |rm_val, shift_imm, c_flag| {
	if shift_imm == 0 {
		data_processing_rrx(rm_val, c_flag)
	} else {
		{ val: rotate_right_u32(rm_val, shift_imm), carry: get_ith_bit_u32_certain(rm_val, shift_imm - 1) }
	}
}

data_processing_ror_by_register : U32, U32, Bool -> U32_carry
data_processing_ror_by_register = |rm_val, rs_val, c_flag| {
	if U32.to_u8_wrap(get_seg_of_u32_certain(rs_val, 0, 8)) == 0 {
		{ val: rm_val, carry: c_flag }
	} else {
		tmp = U32.to_u8_wrap(get_seg_of_u32_certain(rs_val, 0, 5))
		if tmp == 0 {
			{ val: rm_val, carry: get_ith_bit_u32_certain(rm_val, 31) }
		} else {
			{
				val: rotate_right_u32(rm_val, tmp),
				carry: get_ith_bit_u32_certain(rm_val, tmp - 1),
			}
		}
	}
}

data_processing_get_shift_imm : U32 -> U8
data_processing_get_shift_imm = |i| {
	U32.to_u8_wrap(get_seg_of_u32_certain(i, 7, 5))
}

data_processing_get_rm : U32 -> Try(GPR, [WTFisThis])
data_processing_get_rm = |i| {
	gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(i, 0, 4)))
}

data_processing_get_rs : U32 -> Try(GPR, [WTFisThis])
data_processing_get_rs = |i| {
	gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(i, 8, 4)))
}

arm_instructions_decoder : U32 -> Try(ArmInstructions, [WTFisThis])
arm_instructions_decoder = |i| {
	if bits_match(i, 251658240, 251658240) {
		Ok(SoftwareInterrupt)
	} else if bits_match(i, 0b0000_1111_1100_0000_0000_0000_1111_0000, 144) {
		Ok(Multiply)
	} else if bits_match(i, 0b0000_1111_1000_0000_0000_0000_1111_0000, 8388752) {
		Ok(MultiplyLong)
	} else if bits_match(i, 0b0000_1111_1011_0000_0000_1111_1111_0000, 16777360) {
		Ok(SingleDataSwap)
	} else if bits_match(i, 0b0000_1111_1111_1111_1111_1111_1111_0000, 0b1001011111111111100010000) {
		Ok(BranchAndExchange)
	} else if bits_match(i, 0b0000_1110_0100_0000_0000_1111_1001_0000, 0b10010000) and (get_ith_bit_u32_certain(i, 6) or get_ith_bit_u32_certain(i, 5)) {
		Ok(HalfwordDataTransferRegOffset)
	} else if bits_match(i, 0b0000_1110_0100_0000_0000_0000_1001_0000, 0b0100_0000_0000_0000_1001_0000) and (get_ith_bit_u32_certain(i, 6) or get_ith_bit_u32_certain(i, 5)) {
		Ok(HalfwordDataTransferImmediateOffset)
	} else if bits_match(i, 234881040, 100663312) {
		Ok(Undefined)
	} else if bits_match(i, 234881024, 134217728) {
		Ok(BlockDataTransfer)
	} else if bits_match(i, 0b1110_000000000000000000000000, 0b1010_000000000000000000000000) {
		Ok(Branch)
	} else if bits_match(i, 0b1110_000000000000000000000000, 0b1100_000000000000000000000000) {
		Ok(CoprocessorDataTransfer)
	} else if bits_match(i, 0b1111_00000000000000000001_0000, 0b1110_000000000000000000000000) {
		Ok(CoprocessorDataOperation)
	} else if bits_match(i, 0b1111_00000000000000000001_0000, 0b1110_00000000000000000001_0000) {
		Ok(CoprocessorRegisterTransfer)
	} else if bits_match(i, 0b1100_00000000000000000000_0000, 0b0100_00000000000000000000_0000) {
		Ok(SingleDataTransfer)
	} else if bits_match(i, 0b1100_00000000000000000000_0000, 0) {
		Ok(DataProcessingPSRTransfer)
	} else {
		Err(WTFisThis)
	}
}

data_processing_writes_rd : ALUOpCode -> Bool
data_processing_writes_rd = |op| {
	match op {
		TST | TEQ | CMP | CMN => Bool.False
		_ => Bool.True
	}
}

data_processing_alu : ALUOpCode, U32, U32_carry, Bool, Bool -> U32_carry_overflow
data_processing_alu = |alu_op, op1, op2, c_flag, v_flag| {
	match alu_op {
		AND | TST => { val: U32.bitwise_and(op1, op2.val), carry: op2.carry, overflow: v_flag }
		EOR | TEQ => { val: U32.bitwise_xor(op1, op2.val), carry: op2.carry, overflow: v_flag }
		ORR => { val: U32.bitwise_or(op1, op2.val), carry: op2.carry, overflow: v_flag }
		MOV => { val: op2.val, carry: op2.carry, overflow: v_flag }
		BIC => { val: U32.bitwise_and(op1, U32.bitwise_not(op2.val)), carry: op2.carry, overflow: v_flag }
		MVN => { val: U32.bitwise_not(op2.val), carry: op2.carry, overflow: v_flag }
		SUB | CMP => add_with_carry(op1, U32.bitwise_not(op2.val), Bool.True)
		RSB => add_with_carry(op2.val, U32.bitwise_not(op1), Bool.True)
		ADD | CMN => add_with_carry(op1, op2.val, Bool.False)
		ADC => add_with_carry(op1, op2.val, c_flag)
		SBC => add_with_carry(op1, U32.bitwise_not(op2.val), c_flag)
		RSC => add_with_carry(op2.val, U32.bitwise_not(op1), c_flag)
	}
}

data_processing_kind : U32 -> DataProcessingKind
data_processing_kind = |i| {
	if bits_match(i, 0b11001_00000_00000_00000_00000, 0b10000_00000_00000_00000_00000) {
		PSRTransfer
	} else {
		DataProcessing
	}
}

data_processing_calculate : U32, Cpu -> Try(U32_carry_overflow, [InvalidMode, WTFisThis, UB_ShiftbyPC])
data_processing_calculate = |instruction, c| {
	alu_opc = data_processing_decode(instruction)
	rn_val = data_processing_get_rn_value(instruction, c)?
	c_flag = cpsr_getC(c.cpsr)
	v_flag = cpsr_getV(c.cpsr)
	op2 = data_processing_operand2(instruction, c)?
	Ok(data_processing_alu(alu_opc, rn_val, op2, c_flag, v_flag))
}

data_processing_uses_immediate : U32 -> Bool
data_processing_uses_immediate = |i| {
	get_ith_bit_u32_certain(i, 25)
}

data_processing_rotate_imm : U32 -> U8
data_processing_rotate_imm = |i| {
	U32.to_u8_wrap(get_seg_of_u32_certain(i, 8, 4))
}

data_processing_get_immed_8 : U32 -> U8
data_processing_get_immed_8 = |i| {
	U32.to_u8_wrap(get_seg_of_u32_certain(i, 0, 8))
}

data_processing_get_shift_type : U32 -> ShiftType
data_processing_get_shift_type = |i| {
	if bits_match(i, 0b1100000, 0) {
		LSL
	} else if bits_match(i, 0b1100000, 0b0100000) {
		LSR
	} else if bits_match(i, 0b1100000, 0b1000000) {
		ASR
	} else {
		ROR
	}
}

psr_transfer_decode : U32 -> PSRTransferOpCode
psr_transfer_decode = |op| {
	if get_ith_bit_u32_certain(op, 21) {
		MSR
	} else {
		MRS
	}
}

psr_transfer_uses_spsr : U32 -> Bool
psr_transfer_uses_spsr = |op| {
	get_ith_bit_u32_certain(op, 22)
}

psr_transfer_uses_immediate : U32 -> Bool
psr_transfer_uses_immediate = |op| {
	get_ith_bit_u32_certain(op, 25)
}

psr_transfer_mrs_get_rd : U32 -> Try(GPR, [WTFisThis])
psr_transfer_mrs_get_rd = |op| {
	data_processing_get_rd(op)
}

psr_transfer_msr_operand : U32, Cpu -> Try(U32, [InvalidMode, WTFisThis, UB_PSR_PC_as_source])
psr_transfer_msr_operand = |op, c| {
	if psr_transfer_uses_immediate(op) {
		# Does not care about c_flag
		Ok(data_processing_operands_immediate(op, Bool.False).val)
	} else {
		# Had to write this in such awkward way to avoid a compiler bug
		# I should fix this when a new nightly is here.
		match data_processing_get_rm(op) {
			Ok(R15) => Err(UB_PSR_PC_as_source)
			Err(_) => Err(WTFisThis)
			Ok(x) => match cpu_getReg(x, c) {
				Ok(o) => Ok(o)
				Err(_) => Err(InvalidMode)
			}
		}
	}
}

psr_transfer_field_mask : U32 -> U8
psr_transfer_field_mask = |op| {
	U32.to_u8_wrap(get_seg_of_u32_certain(op, 16, 4))
}

condition_pass : Conds, U32 -> Bool
condition_pass = |c, i| {
	match c {
		EQ => cpsr_getZ(i)
		NE => !cpsr_getZ(i)
		CS => cpsr_getC(i)
		CC => !cpsr_getC(i)
		MI => cpsr_getN(i)
		PL => !cpsr_getN(i)
		VS => cpsr_getV(i)
		VC => !cpsr_getV(i)
		HI => cpsr_getC(i) and !cpsr_getZ(i)
		LS => !cpsr_getC(i) or cpsr_getZ(i)
		GE => (cpsr_getN(i) == cpsr_getV(i))
		LT => (cpsr_getN(i) != cpsr_getV(i))
		GT => (cpsr_getN(i) == cpsr_getV(i)) and !cpsr_getZ(i)
		LE => (cpsr_getN(i) != cpsr_getV(i)) or cpsr_getZ(i)
		AL => Bool.True
	}
}

# WIP!
softReset : Cpu -> Cpu
softReset = |prev| {
	..prev,
	regs: {
		..prev.regs,
		r0: 0,
		r1: 0,
		r2: 0,
		r3: 0,
		r4: 0,
		r5: 0,
		r6: 0,
		r7: 0,
		r8: 0,
		r8_fiq: 0,
		r9: 0,
		r9_fiq: 0,
		r10: 0,
		r10_fiq: 0,
		r11: 0,
		r11_fiq: 0,
		r12: 0,
		r12_fiq: 0,
		r14_svc: 0,
		r14_irq: 0,
	},
	cpsr: 0,
	spsr_svc: 0,
	spsr_irq: 0,
}

cpsr_getN : U32 -> Bool
cpsr_getN = |i| {
	U32.shift_right_by(i, 31) == 1
}

cpsr_setN : U32, Bool -> U32
cpsr_setN = |i, b| {
	if b {
		U32.bitwise_or(i, 0b10_00000_00000_00000_00000_00000_00000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b10_00000_00000_00000_00000_00000_00000))
	}
}

cpsr_getZ : U32 -> Bool
cpsr_getZ = |i| {
	U32.is_odd(U32.shift_right_by(i, 30))
}

cpsr_setZ : U32, Bool -> U32
cpsr_setZ = |i, b| {
	if b {
		U32.bitwise_or(i, 0b1_00000_00000_00000_00000_00000_00000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b1_00000_00000_00000_00000_00000_00000))
	}
}

cpsr_getC : U32 -> Bool
cpsr_getC = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 2), 31) == 1
}

cpsr_setC : U32, Bool -> U32
cpsr_setC = |i, b| {
	if b {
		U32.bitwise_or(i, 0b10000_00000_00000_00000_00000_00000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b10000_00000_00000_00000_00000_00000))
	}
}

cpsr_getV : U32 -> Bool
cpsr_getV = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 3), 31) == 1
}

cpsr_setV : U32, Bool -> U32
cpsr_setV = |i, b| {
	if b {
		U32.bitwise_or(i, 0b1_0000_0000_0000_0000_0000_0000_0000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b1_0000_0000_0000_0000_0000_0000_0000))
	}
}

cpsr_getI : U32 -> Bool
cpsr_getI = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 24), 31) == 1
}

cpsr_setI : U32, Bool -> U32
cpsr_setI = |i, b| {
	if b {
		U32.bitwise_or(i, 0b1000_0000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b1000_0000))
	}
}

cpsr_getF : U32 -> Bool
cpsr_getF = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 25), 31) == 1
}

cpsr_setF : U32, Bool -> U32
cpsr_setF = |i, b| {
	if b {
		U32.bitwise_or(i, 0b100_0000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b100_0000))
	}
}

cpsr_getT : U32 -> Bool
cpsr_getT = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 26), 31) == 1
}

cpsr_setT : U32, Bool -> U32
cpsr_setT = |i, b| {
	if b {
		U32.bitwise_or(i, 0b100000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b100000))
	}
}

cpsr_getMode : U32 -> Try(Mode, [InvalidMode])
cpsr_getMode = |j| {
	i = U32.shift_right_by(U32.shift_left_by(j, 27), 27)
	if U32.bitwise_xor(i, 16) == 0 {
		Ok(User)
	} else if U32.bitwise_xor(i, 17) == 0 {
		Ok(FIQ)
	} else if U32.bitwise_xor(i, 18) == 0 {
		Ok(IRQ)
	} else if U32.bitwise_xor(i, 19) == 0 {
		Ok(Sup)
	} else if U32.bitwise_xor(i, 23) == 0 {
		Ok(Abort)
	} else if U32.bitwise_xor(i, 27) == 0 {
		Ok(Undefined)
	} else if U32.bitwise_xor(i, 31) == 0 {
		Ok(Sys)
	} else {
		Err(InvalidMode)
	}
}

cpsr_setMode : Mode, U32 -> U32
cpsr_setMode = |m, i| {
	j = U32.shift_left_by(U32.shift_right_by(i, 5), 5)
	match m {
		User => U32.bitwise_or(j, 16)
		FIQ => U32.bitwise_or(j, 17)
		IRQ => U32.bitwise_or(j, 18)
		Sup => U32.bitwise_or(j, 19)
		Abort => U32.bitwise_or(j, 23)
		Undefined => U32.bitwise_or(j, 27)
		Sys => U32.bitwise_or(j, 31)
	}
}

regs_get : GPR, Mode, Regs -> U32
regs_get = |r, m, regs| {
	match r {
		R8 => match m {
			FIQ => regs.r8_fiq
			_ => regs.r8
		}
		R9 => match m {
			FIQ => regs.r9_fiq
			_ => regs.r9
		}
		R10 => match m {
			FIQ => regs.r10_fiq
			_ => regs.r10
		}
		R11 => match m {
			FIQ => regs.r11_fiq
			_ => regs.r11
		}
		R12 => match m {
			FIQ => regs.r12_fiq
			_ => regs.r12
		}
		R13 => match m {
			Sys | User => regs.r13
			FIQ => regs.r13_fiq
			Sup => regs.r13_svc
			Abort => regs.r13_abt
			IRQ => regs.r13_irq
			Undefined => regs.r13_und
		}
		R14 => match m {
			Sys | User => regs.r14
			FIQ => regs.r14_fiq
			Sup => regs.r14_svc
			Abort => regs.r14_abt
			IRQ => regs.r14_irq
			Undefined => regs.r14_und
		}
		R0 => regs.r0
		R1 => regs.r1
		R2 => regs.r2
		R3 => regs.r3
		R4 => regs.r4
		R5 => regs.r5
		R6 => regs.r6
		R7 => regs.r7
		R15 => regs.r15
	}
}

regs_set : GPR, Mode, Regs, U32 -> Regs
regs_set = |r, m, regs, i| {
	match r {
		R8 => match m {
			FIQ => { ..regs, r8_fiq: i }
			_ => { ..regs, r8: i }
		}
		R9 => match m {
			FIQ => { ..regs, r9_fiq: i }
			_ => { ..regs, r9: i }
		}
		R10 => match m {
			FIQ => { ..regs, r10_fiq: i }
			_ => { ..regs, r10: i }
		}
		R11 => match m {
			FIQ => { ..regs, r11_fiq: i }
			_ => { ..regs, r11: i }
		}
		R12 => match m {
			FIQ => { ..regs, r12_fiq: i }
			_ => { ..regs, r12: i }
		}
		R13 => match m {
			Sys | User => { ..regs, r13: i }
			FIQ => { ..regs, r13_fiq: i }
			Sup => { ..regs, r13_svc: i }
			Abort => { ..regs, r13_abt: i }
			IRQ => { ..regs, r13_irq: i }
			Undefined => { ..regs, r13_und: i }
		}
		R14 => match m {
			Sys | User => { ..regs, r14: i }
			FIQ => { ..regs, r14_fiq: i }
			Sup => { ..regs, r14_svc: i }
			Abort => { ..regs, r14_abt: i }
			IRQ => { ..regs, r14_irq: i }
			Undefined => { ..regs, r14_und: i }
		}
		R0 => { ..regs, r0: i }
		R1 => { ..regs, r1: i }
		R2 => { ..regs, r2: i }
		R3 => { ..regs, r3: i }
		R4 => { ..regs, r4: i }
		R5 => { ..regs, r5: i }
		R6 => { ..regs, r6: i }
		R7 => { ..regs, r7: i }
		R15 => { ..regs, r15: i }
	}
}

cpu_getReg : GPR, Cpu -> Try(U32, [InvalidMode])
cpu_getReg = |r, cpu| {
	m = cpsr_getMode(cpu.cpsr)?
	Ok(regs_get(r, m, cpu.regs))
}

cpu_setReg : GPR, Cpu, U32 -> Try(Cpu, [InvalidMode])
cpu_setReg = |r, cpu, i| {
	m = cpsr_getMode(cpu.cpsr)?
	Ok({ ..cpu, regs: regs_set(r, m, cpu.regs, i) })
}

opcode_parse_cond : U32 -> Try(Conds, [ReservedinArm7, Huh])
opcode_parse_cond = |i| {
	tmp = U32.shift_right_by(i, 28)
	match tmp {
		0 => Ok(EQ)
		1 => Ok(NE)
		2 => Ok(CS)
		3 => Ok(CC)
		4 => Ok(MI)
		5 => Ok(PL)
		6 => Ok(VS)
		7 => Ok(VC)
		8 => Ok(HI)
		9 => Ok(LS)
		10 => Ok(GE)
		11 => Ok(LT)
		12 => Ok(GT)
		13 => Ok(LE)
		14 => Ok(AL)
		15 => Err(ReservedinArm7)
		_ => Err(Huh)
	}
}

# Mode : [FIQ, Sup, Abort, IRQ, Undefined, User, Sys]
cpu_getSPSR : Cpu -> Try(U32, [InvalidMode, NoSPSR])
cpu_getSPSR = |c| {
	m = cpsr_getMode(c.cpsr)?
	match m {
		FIQ => Ok(c.spsr_fiq)
		Sup => Ok(c.spsr_svc)
		Abort => Ok(c.spsr_abt)
		IRQ => Ok(c.spsr_irq)
		Undefined => Ok(c.spsr_und)
		User | Sys => Err(NoSPSR)
	}
}

cpu_setSPSR : Cpu, U32 -> Try(Cpu, [InvalidMode, NoSPSR])
cpu_setSPSR = |c, i| {
	m = cpsr_getMode(c.cpsr)?
	match m {
		FIQ => Ok({ ..c, spsr_fiq: i })
		Sup => Ok({ ..c, spsr_svc: i })
		Abort => Ok({ ..c, spsr_abt: i })
		IRQ => Ok({ ..c, spsr_irq: i })
		Undefined => Ok({ ..c, spsr_und: i })
		User | Sys => Err(NoSPSR)
	}
}

cpsr_setNZCV : U32, U32_carry_overflow -> U32
cpsr_setNZCV = |old_cpsr, alu_op_res| {
	cpsr_setC(cpsr_setV(cpsr_setZ(cpsr_setN(old_cpsr, get_ith_bit_u32_certain(alu_op_res.val, 31)), alu_op_res.val == 0), alu_op_res.overflow), alu_op_res.carry)
}
