GPR : [R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15]

Mode : [FIQ, Sup, Abort, IRQ, Undefined, User, Sys]

Regs : {
	r0 : U32,
	r1 : U32,
	r2 : U32,
	r3 : U32,
	r4 : U32,
	r5 : U32,
	r6 : U32,
	r7 : U32,
	r8 : U32,
	r8_fiq : U32,
	r9 : U32,
	r9_fiq : U32,
	r10 : U32,
	r10_fiq : U32,
	r11 : U32,
	r11_fiq : U32,
	r12 : U32,
	r12_fiq : U32,
	r13 : U32,
	r13_fiq : U32,
	r13_svc : U32,
	r13_abt : U32,
	r13_irq : U32,
	r13_und : U32,
	r14 : U32,
	r14_fiq : U32,
	r14_svc : U32,
	r14_abt : U32,
	r14_irq : U32,
	r14_und : U32,
	r15 : U32,
}

Thumb_ALUOpCode : {
	code : [AND, EOR, SUB, ADD, ADC, SBC, TST, CMP, CMN, ORR, MOV, BIC, MVN, LSR, LSL, ASR, ROR, MUL, NEG, NoSuchOp],
	format : Formats,
}

Conds : [EQ, NE, CS, CC, MI, PL, VS, VC, HI, LS, GE, LT, GT, LE, AL]

ShiftType : [LSL, LSR, ASR, ROR]

ThumbInstructions : [
	DataProcessing,
	Branch,
	SoftwareInterrupt,
	UndefinedInstruction,
	LoadLiteral,
	LoadStoreRegisterOffset,
	LoadStoreImmediateOffset,
	LoadStoreHalfwordImmediateOffset,
	LoadStoreSPRelative,
	PushPop,
	LoadStoreMultiple,
]

ArmInstructions : [
	DataProcessingPSRTransfer,
	Multiply,
	MultiplyLong,
	SingleDataSwap,
	BranchAndExchange,
	HalfwordDataTransferRegOffset,
	HalfwordDataTransferImmediateOffset,
	SingleDataTransfer,
	ArchitecturallyUndefined,
	Branch,
	CoprocessorDataTransfer,
	CoprocessorDataOperation,
	CoprocessorRegisterTransfer,
	SoftwareInterrupt,
	BlockDataTransfer,
	UndefinedInstruction,
]

ArmDataProcessingKind : [DataProcessing, PSRTransfer]

# Alias can be Data Processing
ALUOpCode : [AND, EOR, SUB, RSB, ADD, ADC, SBC, RSC, TST, TEQ, CMP, CMN, ORR, MOV, BIC, MVN]

Formats : [Format1, Format2, Format3, Format4, Format5, Format6, Format7, Format8, UndefinedFormat]

ArmPSRTransferOpCode : [MSR, MRS]

ArmMultiplyOpCode : [MUL, MLA]

ArmMultiplyLongOpCode : [UMULL, UMLAL, SMULL, SMLAL]

ArmSingleDataTransferOpCode : [STR, LDR, STRB, LDRB, LDRT, STRT, LDRBT, STRBT]

ArmSingleDataSwapOpCode : [SWP, SWPB]

ArmHalfwordDataTransferOpCode : [LDRH, STRH, LDRSB, LDRSH, UndefinedInstruction]

ArmBlockDataTransferOpCode : [LDM, STM]

Cpu := {
	regs : Regs,
	cpsr : U32,
	spsr_fiq : U32,
	spsr_svc : U32,
	spsr_irq : U32,
	spsr_und : U32,
	spsr_abt : U32,
}.{
	Execution_outcome : { cpu : Cpu, pc_status : PC_status }
	ReqWidth : [W8, W16, W32]
	Rotation : [Identity, RotRight(U8), SignedExtend8, SignedExtend16]
	WriteBackAction : [NoWriteBack, WriteBack({ rn : GPR, val : U32 })]

	Execution_state : [
		Complete(Cpu),
		R(
			{
				cpu : Cpu,
				addr : U32,
				width : ReqWidth,
				continuation : ReadContinuation,
			},
		),
		W(
			{
				cpu : Cpu,
				addr : U32,
				width : ReqWidth,
				val : U32,
				continuation : WriteContinuation,
			},
		),
	]

	ReadContinuation : [
		SetRegAndFinish(
			{
				rd : GPR,
				rot : Rotation,
				wba : WriteBackAction,
			},
		),
		GetValfromMem(
			{
				rd : GPR,
				addr : U32,
				rm_val : U32,
				width : ReqWidth,
				rot : Rotation,
			},
		),
		LoadMultiple(
			{
				mask : U32,
				next_addr : U32,
				wba : WriteBackAction,
				kind : [
					CurrentBank,
					UserBank,
					ModeChanges({ spsr : U32 }),
				],
			},
		),
	]

	WriteContinuation : [
		StoreAndFinish({ wba : WriteBackAction }),
		WriteMultiple(
			{
				mask : U32,
				next_addr : U32,
				wba : WriteBackAction,
				kind : [CurrentBank, UserBank],
			},
		),
		SetRegAndFinish(
			{
				rd : GPR,
				val : U32,
			},
		),
	]

	resume_read : Cpu,
	U32,
	ReadContinuation -> Try(
		Execution_state,
		[
			InvalidMode,
			UNPREDICTABLE,
			WTFisThis,
		],
	)
	resume_read = |c, raw_val, rc| {
		nuker = |x, i| {
			U32.bitwise_and(x, 4294967295 - U32.pow(2, i))
		}
		match rc {
			SetRegAndFinish(x) => {
				arm_post_memory_operation(
					if x.rd == R15 {
						if get_seg_of_u32_certain(raw_val, 0, 2) == 2 {
							return Err(UNPREDICTABLE)
						} else {
							c_raw = cpu_setReg(x.rd, c, rotate(x.rot, raw_val))?
							cpu_setReg(R15, c_raw, U32.bitwise_and(cpu_getReg(R15, c_raw)?, 0xFFFFFFFC))?
						}
					} else {
						cpu_setReg(x.rd, c, rotate(x.rot, raw_val))?
					},
					x.wba,
					if x.rd == R15 {
						PCWritten
					} else {
						PCSequential
					},
				)
			}
			LoadMultiple(x) => {
				pop_reg = U32.count_trailing_zero_bits(x.mask)
				new_mask = nuker(x.mask, pop_reg.to_u32())
				gpr = gpr_from_idx(pop_reg)?
				if gpr == R15 {
					match x.kind {
						CurrentBank => {
							arm_post_memory_operation(
								cpu_setReg(gpr, c, raw_val.bitwise_and(0xFFFFFFFC))?,
								x.wba,
								PCWritten,
							)
						}
						UserBank => Err(WTFisThis) # Impossible, LDM(2) cannot have PC
						ModeChanges(saved) => {
							if !cpsr_getT(saved.spsr) and get_ith_bit_u32_certain(raw_val, 1) {
								Err(UNPREDICTABLE)
							} else {
								cpu_wb = match x.wba {
									NoWriteBack => c
									WriteBack(wb) => cpu_setReg(wb.rn, c, wb.val)?
								}
								restore_cpsr = { ..cpu_wb, cpsr: saved.spsr }
								arm_post_memory_operation(
									cpu_setReg(
										R15,
										restore_cpsr,
										if cpsr_getT(saved.spsr) {
											raw_val.bitwise_and(0xFFFFFFFE)
										} else {
											raw_val.bitwise_and(0xFFFFFFFC)
										},
									)?,
									NoWriteBack,
									PCWritten,
								)
							}
						}
					}
				} else {
					new_cpu = if x.kind == UserBank {
						{
							..c,
							regs: regs_set(gpr, User, c.regs, raw_val),
						}
					} else {
						cpu_setReg(gpr, c, raw_val)?
					}
					if new_mask == 0 {
						arm_post_memory_operation(
							new_cpu,
							x.wba,
							PCSequential,
						)
					} else {
						Ok(
							R({
								cpu: new_cpu,
								addr: (x.next_addr),
								width: W32,
								continuation: LoadMultiple({
									..x,
									mask: new_mask,
									next_addr: x.next_addr.plus_wrap(4),
								}),
							}),
						)
					}
				}
			}
			GetValfromMem(x) => {
				Ok(
					W({
						cpu: c,
						addr: x.addr,
						width: x.width,
						val: x.rm_val,
						continuation: SetRegAndFinish({ rd: x.rd, val: rotate(x.rot, raw_val) }),
					}),
				)
			}
		}
	}

	resume_write : Cpu,
	WriteContinuation -> Try(
		Execution_state,
		[
			InvalidMode,
			WTFisThis,
		],
	)
	resume_write = |c, wc| {
		nuker = |x, i| {
			U32.bitwise_and(x, 4294967295 - U32.pow(2, i))
		}
		match wc {
			StoreAndFinish(x) => arm_post_memory_operation(c, x.wba, PCSequential)
			WriteMultiple(x) => {
				pop_reg = U32.count_trailing_zero_bits(x.mask)
				new_mask = nuker(x.mask, pop_reg.to_u32())
				if new_mask == 0 {
					arm_post_memory_operation(
						c,
						x.wba,
						PCSequential,
					)
				} else {
					val = {
						next_gpr = gpr_from_idx(new_mask.count_trailing_zero_bits())?
						if next_gpr == R15 {
							pc_inc(c.regs.r15, 12)
						} else if x.kind == CurrentBank {
							cpu_getReg(next_gpr, c)?
						} else {
							regs_get(next_gpr, User, c.regs)
						}
					}
					Ok(
						W({
							cpu: c,
							addr: (x.next_addr),
							width: W32,
							val: val,
							continuation: WriteMultiple({
								..x,
								mask: new_mask,
								next_addr: x.next_addr.plus_wrap(4),
							}),
						}),
					)
				}
			}
			SetRegAndFinish(x) =>
				arm_post_memory_operation(cpu_setReg(x.rd, c, x.val)?, NoWriteBack, PCSequential)
		}
	}

	is_thumb : Cpu -> Bool
	is_thumb = |c| {
		cpsr_getT(c.cpsr)
	}

	getPC : Cpu -> U32
	getPC = |c| {
		c.regs.r15
	}

	execute_arm_opcode : Cpu, U32 -> Try(Execution_state, _)
	execute_arm_opcode = |c, op| {
		arm_instructions_execute(op, c)
	}
}

arm_post_memory_operation : Cpu, WriteBackAction, PC_status -> Try(Execution_state, [InvalidMode])
arm_post_memory_operation = |c, wba, pcs| {
	Ok(
		arm_instructions_settle(
			match wba {
				NoWriteBack => { cpu: c, pc_status: pcs }
				WriteBack(x) => { cpu: cpu_setReg(x.rn, c, x.val)?, pc_status: pcs }
			},
		),
	)
}

PC_status : [PCSequential, PCWritten]

U32_carry : { val : U32, carry : Bool }

U32_carry_overflow : { val : U32, carry : Bool, overflow : Bool }

pc_inc : U32, U32 -> U32
pc_inc = |r15, val| {
	U32.plus_wrap(r15, val)
}

rotate_right_u32 : U32, U8 -> U32
rotate_right_u32 = |i, j| {
	tmp = j % 32
	if tmp == 0 {
		i
	} else {
		rotate_right_u32(i // 2 + 2147483648 * (i % 2), tmp - 1)
	}
}

signed_extend_u32 : U32, U8 -> U32
signed_extend_u32 = |val, e| {
	if e == 0 or e >= 32 {
		val
	} else {
		if get_ith_bit_u32_certain(val, e - 1) {
			U32.bitwise_or(4294967295 - U32.pow(2, e.to_u32()) + 1, val)
		} else {
			val
		}
	}
}

rotate : Rotation, U32 -> U32
rotate = |r, val| {
	match r {
		Identity => val
		RotRight(i) => rotate_right_u32(val, i)
		SignedExtend8 => {
			signed_extend_u32(val, 8)
		}
		SignedExtend16 => {
			signed_extend_u32(val, 16)
		}
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

get_ith_bit_u16_certain : U16, U8 -> Bool
get_ith_bit_u16_certain = |i, j| {
	U16.shr_wrap(U16.shl_wrap(i, 16 - j - 1), 15) == 1
}

get_ith_bit_u32_certain : U32, U8 -> Bool
get_ith_bit_u32_certain = |i, j| {
	U32.shr_wrap(U32.shl_wrap(i, 32 - j - 1), 31) == 1
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

get_gpr_16_19 : U32 -> Try(GPR, [WTFisThis])
get_gpr_16_19 = |i| {
	tmp = get_seg_of_u32_certain(i, 16, 4)
	gpr_from_idx(U32.to_u8_wrap(tmp))
}

arm_data_processing_get_rn_value : U32, Cpu -> Try(U32, [InvalidMode, WTFisThis])
arm_data_processing_get_rn_value = |i, c| {
	rn = get_gpr_16_19(i)?
	arm_data_processing_operand_reg_value(i, rn, c)
}

get_gpr_12_15 : U32 -> Try(GPR, [WTFisThis])
get_gpr_12_15 = |i| {
	tmp = get_seg_of_u32_certain(i, 12, 4)
	gpr_from_idx(U32.to_u8_wrap(tmp))
}

# Man it's always the PC being different
arm_data_processing_operand_reg_value : U32, GPR, Cpu -> Try(U32, [InvalidMode])
arm_data_processing_operand_reg_value = |i, gpr, c| {
	match gpr {
		R15 => if get_ith_bit_u32_certain(i, 25) {
			Ok(pc_inc(c.regs.r15, 8))
		} else if get_ith_bit_u32_certain(i, 4) {
			Ok(pc_inc(c.regs.r15, 12))
		} else {
			Ok(pc_inc(c.regs.r15, 8))
		}
		_ => cpu_getReg(gpr, c)
	}
}

arm_data_processing_operands_register : U32, Cpu -> Try(U32_carry, [InvalidMode, WTFisThis, UB_ShiftbyPC])
arm_data_processing_operands_register = |i, c| {
	rm = get_gpr_0_3(i)?
	rm_val = arm_data_processing_operand_reg_value(i, rm, c)?
	shift_type = arm_data_processing_get_shift_type(i)
	c_flag = cpsr_getC(c.cpsr)
	if get_ith_bit_u32_certain(i, 4) {
		x = arm_data_processing_get_rs(i)?
		match x {
			R15 => Err(UB_ShiftbyPC)
			_ => Ok(data_processing_shift_by_register(shift_type, rm_val, cpu_getReg(x, c)?, c_flag))
		}
	} else {
		shift_imm = arm_data_processing_get_shift_imm(i)
		Ok(data_processing_shift_by_immediate(shift_type, rm_val, shift_imm, c_flag))
	}
}

arm_data_processing_operands_immediate : U32, Bool -> U32_carry
arm_data_processing_operands_immediate = |i, c_flag| {
	rotate_imm = arm_data_processing_rotate_imm(i)
	tmp = rotate_right_u32(U8.to_u32(arm_data_processing_get_immed_8(i)), rotate_imm * 2)
	if rotate_imm == 0 {
		{ val: tmp, carry: c_flag }
	} else {
		{ val: tmp, carry: get_ith_bit_u32_certain(tmp, 31) }
	}
}

arm_data_processing_operand2 : U32, Cpu -> Try(U32_carry, [InvalidMode, WTFisThis, UB_ShiftbyPC])
arm_data_processing_operand2 = |i, c| {
	c_flag = cpsr_getC(c.cpsr)
	if arm_data_processing_uses_immediate(i) {
		Ok(arm_data_processing_operands_immediate(i, c_flag))
	} else {
		arm_data_processing_operands_register(i, c)
	}
}

arm_data_processing_decode : U32 -> ALUOpCode
arm_data_processing_decode = |i| {
	# ctrl cv template: 0b0000000_1111_000000000000000000000
	# 0b0000000_????_000000000000000000000
	if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0000_000000000000000000000) {
		AND
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0001_000000000000000000000) {
		EOR
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0010_000000000000000000000) {
		SUB
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0011_000000000000000000000) {
		RSB
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0100_000000000000000000000) {
		ADD
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0101_000000000000000000000) {
		ADC
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0110_000000000000000000000) {
		SBC
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_0111_000000000000000000000) {
		RSC
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1000_000000000000000000000) {
		TST
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1001_000000000000000000000) {
		TEQ
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1010_000000000000000000000) {
		CMP
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1011_000000000000000000000) {
		CMN
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1100_000000000000000000000) {
		ORR
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1101_000000000000000000000) {
		MOV
	} else if bits_match_32(i, 0b0000000_1111_000000000000000000000, 0b0000000_1110_000000000000000000000) {
		BIC
	} else {
		MVN
	}
}

arm_data_processing_shift_amount_uses_reg : U32 -> Bool
arm_data_processing_shift_amount_uses_reg = |i| {
	get_ith_bit_u32_certain(i, 4)
}

data_processing_lsl_by_immediate : U32, U8, Bool -> U32_carry
data_processing_lsl_by_immediate = |rm_val, shift_imm, c_flag| {
	if shift_imm == 0 {
		{ val: rm_val, carry: c_flag }
	} else {
		{
			val: U32.shl_wrap(rm_val, shift_imm),
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
		{ val: U32.shl_wrap(rm_val, tmp), carry: get_ith_bit_u32_certain(rm_val, 32 - tmp) }
	} else if tmp == 32 {
		{ val: 0, carry: get_ith_bit_u32_certain(rm_val, 0) }
	} else {
		{ val: 0, carry: Bool.False }
	}
}

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
		{ val: U32.shr_wrap(rm_val, shift_imm), carry: get_ith_bit_u32_certain(rm_val, shift_imm - 1) }
	}
}

data_processing_lsr_by_register : U32, U32, Bool -> U32_carry
data_processing_lsr_by_register = |rm_val, rs_val, c_flag| {
	tmp = U32.to_u8_wrap(get_seg_of_u32_certain(rs_val, 0, 8))
	if tmp == 0 {
		{ val: rm_val, carry: c_flag }
	} else if tmp < 32 {
		{ val: U32.shr_wrap(rm_val, tmp), carry: get_ith_bit_u32_certain(rm_val, tmp - 1) }
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
			Bool.True => U32.bitwise_or(2147483648, U32.shr_wrap(rm_val, 1))
			_ => U32.shr_wrap(rm_val, 1)
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

arm_data_processing_get_shift_imm : U32 -> U8
arm_data_processing_get_shift_imm = |i| {
	U32.to_u8_wrap(get_seg_of_u32_certain(i, 7, 5))
}

get_gpr_0_3 : U32 -> Try(GPR, [WTFisThis])
get_gpr_0_3 = |i| {
	gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(i, 0, 4)))
}

arm_data_processing_get_rs : U32 -> Try(GPR, [WTFisThis])
arm_data_processing_get_rs = |i| {
	gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(i, 8, 4)))
}

arm_instructions_decode : U32 -> Try(ArmInstructions, [WTFisThis, UNPREDICTABLE])
arm_instructions_decode = |i| {
	if bits_match_32(i, 0b111_11011_00000000000000000000, 0b001_10000_00000000000000000000) {
		Ok(UndefinedInstruction)
	} else if bits_match_32(i, 0b111_11111_000000000000_1111_0000, 0b011_11111_000000000000_1111_0000) {
		Ok(ArchitecturallyUndefined)
	} else if bits_match_32(i, 0b1111_000000000000000000000000, 0b1111_000000000000000000000000) {
		Ok(SoftwareInterrupt)
	} else if bits_match_32(i, 0b0000_1111_1100_0000_0000_0000_1111_0000, 144) {
		Ok(Multiply)
	} else if bits_match_32(i, 0b0000_1111_1000_0000_0000_0000_1111_0000, 8388752) {
		Ok(MultiplyLong)
	} else if bits_match_32(i, 0b0000_1111_1011_0000_0000_1111_1111_0000, 16777360) {
		Ok(SingleDataSwap)
	} else if bits_match_32(i, 0b0000_1111_1111_1111_1111_1111_1111_0000, 0b1001011111111111100010000) {
		Ok(BranchAndExchange)
	} else if bits_match_32(i, 0b0000_1110_0100_0000_0000_0000_1001_0000, 0b1001_0000)
		and (get_ith_bit_u32_certain(i, 6) or get_ith_bit_u32_certain(i, 5)) {
		if get_seg_of_u32_certain(i, 8, 4) == 0 {
			Ok(HalfwordDataTransferRegOffset)
		} else {
			match arm_halfword_data_transfer_decode(i) {
				UndefinedInstruction => Ok(UndefinedInstruction)
				_ => Err(UNPREDICTABLE)
			}
		}
	} else if bits_match_32(i, 0b0000_1110_0100_0000_0000_0000_1001_0000, 0b0100_0000_0000_0000_1001_0000)
		and (get_ith_bit_u32_certain(i, 6) or get_ith_bit_u32_certain(i, 5)) {
		Ok(HalfwordDataTransferImmediateOffset)
	} else if bits_match_32(i, 234881024, 134217728) {
		Ok(BlockDataTransfer)
	} else if bits_match_32(i, 0b1110_000000000000000000000000, 0b1010_000000000000000000000000) {
		Ok(Branch)
	} else if bits_match_32(i, 0b1110_000000000000000000000000, 0b1100_000000000000000000000000) {
		Ok(CoprocessorDataTransfer)
	} else if bits_match_32(i, 0b1111_00000000000000000001_0000, 0b1110_000000000000000000000000) {
		Ok(CoprocessorDataOperation)
	} else if bits_match_32(i, 0b1111_00000000000000000001_0000, 0b1110_00000000000000000001_0000) {
		Ok(CoprocessorRegisterTransfer)
	} else if bits_match_32(i, 0b111_00000000000000000000_1_0000, 0b011_00000000000000000000_1_0000) {
		Ok(UndefinedInstruction) # 4.17 Undefined Instruction, arm-instructionset.pdf
	} else if bits_match_32(i, 0b1100_00000000000000000000_0000, 0b0100_00000000000000000000_0000) {
		Ok(SingleDataTransfer)
	} else if !get_ith_bit_u32_certain(i, 25)
		and get_ith_bit_u32_certain(i, 4)
			and get_ith_bit_u32_certain(i, 7) {
		Err(WTFisThis) # A5-3 DDI01001
	} else if bits_match_32(i, 0b1100_00000000000000000000_0000, 0) {
		Ok(DataProcessingPSRTransfer)
	} else {
		Err(WTFisThis)
	}
}

arm_instructions_finalize : Execution_outcome -> Cpu
arm_instructions_finalize = |content| {
	match content.pc_status {
		PCSequential => {
			..content.cpu,
			regs: {
				..content.cpu.regs,
				r15: pc_inc(content.cpu.regs.r15, 4),
			},
		}
		_ => content.cpu
	}
}

arm_instructions_settle : Execution_outcome -> Execution_state
arm_instructions_settle = |outcome| {
	Complete(arm_instructions_finalize(outcome))
}

arm_instructions_execute : U32, Cpu -> Try(Execution_state, _)
arm_instructions_execute = |op, c| {
	cond = arm_opcode_parse_cond(op)?
	if condition_pass(cond, c.cpsr) {
		action = arm_instructions_decode(op)?
		match action {
			DataProcessingPSRTransfer => match arm_data_processing_kind(op) {
				DataProcessing => Ok(arm_instructions_settle(arm_data_processing_execute(op, c)?))
				PSRTransfer => Ok(
					arm_instructions_settle({
						cpu: arm_psr_transfer_execute(op, c)?,
						pc_status: PCSequential,
					}),
				)
			}
			BranchAndExchange => Ok(
				arm_instructions_settle({
					cpu: arm_branch_exchange_execute(op, c)?,
					pc_status: PCWritten,
				}),
			)
			Branch => Ok(
				arm_instructions_settle({
					cpu: arm_branch_execute(op, c)?,
					pc_status: PCWritten,
				}),
			)
			Multiply => Ok(
				arm_instructions_settle({
					cpu: arm_multiply_execute(op, c)?,
					pc_status: PCSequential,
				}),
			)
			MultiplyLong => Ok(
				arm_instructions_settle({
					cpu: arm_multiply_long_execute(op, c)?,
					pc_status: PCSequential,
				}),
			)
			SoftwareInterrupt => Ok(
				arm_instructions_settle({
					cpu: arm_software_interrupt_execute(c)?,
					pc_status: PCWritten,
				}),
			)
			SingleDataTransfer => arm_single_data_transfer_execute(op, c)
			HalfwordDataTransferImmediateOffset | HalfwordDataTransferRegOffset => arm_halfword_data_transfer_execute(op, c)
			UndefinedInstruction | ArchitecturallyUndefined | CoprocessorDataOperation | CoprocessorDataTransfer | CoprocessorRegisterTransfer => Ok(
				arm_instructions_settle({
					cpu: arm_undefined_instruction_execute(c)?,
					pc_status: PCWritten,
				}),
			)
			BlockDataTransfer => arm_block_data_transfer_execute(op, c)
			SingleDataSwap => arm_single_data_swap_execute(op, c)
		}
	} else {
		Ok(
			arm_instructions_settle({
				cpu: c,
				pc_status: PCSequential,
			}),
		)
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

arm_data_processing_kind : U32 -> ArmDataProcessingKind
arm_data_processing_kind = |i| {
	if bits_match_32(i, 0b11001_00000_00000_00000_00000, 0b10000_00000_00000_00000_00000) {
		PSRTransfer
	} else {
		DataProcessing
	}
}

arm_data_processing_calculate : U32, Cpu, ALUOpCode -> Try(U32_carry_overflow, [InvalidMode, WTFisThis, UB_ShiftbyPC])
arm_data_processing_calculate = |instruction, c, alu_opc| {
	rn_val = arm_data_processing_get_rn_value(instruction, c)?
	c_flag = cpsr_getC(c.cpsr)
	v_flag = cpsr_getV(c.cpsr)
	op2 = arm_data_processing_operand2(instruction, c)?
	Ok(data_processing_alu(alu_opc, rn_val, op2, c_flag, v_flag))
}

arm_data_processing_execute : U32, Cpu -> Try(Execution_outcome, [InvalidMode, WTFisThis, UB_ShiftbyPC, NoSPSR])
arm_data_processing_execute = |op, c| {
	alu_op = arm_data_processing_decode(op)
	res = arm_data_processing_calculate(op, c, alu_op)?
	if data_processing_writes_rd(alu_op) {
		rd = get_gpr_12_15(op)?
		match rd {
			R15 => if arm_s_flag(op) {
				Ok({
					cpu: {
						..{
							if cpsr_getT(cpu_getSPSR(c)?) {
								cpu_setReg(rd, c, res.val.bitwise_and(0xFFFFFFFE))?
							} else {
								cpu_setReg(rd, c, res.val)?
							}
						},
						cpsr: cpu_getSPSR(c)?,
					},
					pc_status: PCWritten,
				})
			} else {
				Ok({ cpu: cpu_setReg(rd, c, res.val)?, pc_status: PCWritten })
			}
			_ => if arm_s_flag(op) {
				Ok({
					cpu: { ..cpu_setReg(rd, c, res.val)?, cpsr: cpsr_setNZCV(c.cpsr, res) },
					pc_status: PCSequential,
				})
			} else {
				Ok({
					cpu: cpu_setReg(rd, c, res.val)?,
					pc_status: PCSequential,
				})
			}
		}
	} else {
		Ok({
			cpu: { ..c, cpsr: cpsr_setNZCV(c.cpsr, res) },
			pc_status: PCSequential,
		})
	}
}

arm_data_processing_uses_immediate : U32 -> Bool
arm_data_processing_uses_immediate = |i| {
	get_ith_bit_u32_certain(i, 25)
}

arm_data_processing_rotate_imm : U32 -> U8
arm_data_processing_rotate_imm = |i| {
	U32.to_u8_wrap(get_seg_of_u32_certain(i, 8, 4))
}

arm_data_processing_get_immed_8 : U32 -> U8
arm_data_processing_get_immed_8 = |i| {
	U32.to_u8_wrap(get_seg_of_u32_certain(i, 0, 8))
}

arm_data_processing_get_shift_type : U32 -> ShiftType
arm_data_processing_get_shift_type = |i| {
	if bits_match_32(i, 0b1100000, 0) {
		LSL
	} else if bits_match_32(i, 0b1100000, 0b0100000) {
		LSR
	} else if bits_match_32(i, 0b1100000, 0b1000000) {
		ASR
	} else {
		ROR
	}
}

arm_psr_transfer_decode : U32 -> Try(
	ArmPSRTransferOpCode,
	[
		UnknownPSRType,
		PSR_malformed_MSR_immediate,
		PSR_malformed_MSR_register,
		PSR_malformed_MRS,
	],
)
arm_psr_transfer_decode = |op| {
	if bits_match_32(op, 0b0000_1111_1011_000000000000_1111_0000, 0b0000_0001_0000_000000000000_0000_0000) {
		if get_seg_of_u32_certain(op, 16, 4) != 0xF or get_seg_of_u32_certain(op, 0, 12) != 0 {
			Err(PSR_malformed_MRS)
		} else {
			Ok(MRS)
		}
	} else if bits_match_32(op, 0b11111_0_11_00000000000000000000, 0b00110_0_10_00000000000000000000) {
		if get_seg_of_u32_certain(op, 12, 4) != 0xF {
			Err(PSR_malformed_MSR_immediate)
		} else {
			Ok(MSR) # transfer immediate
		}
	} else if bits_match_32(op, 0b11111_0_11_0000_0000_0000_1111_0000, 0b00010_0_10_0000_0000_0000_0000_0000) {
		if get_seg_of_u32_certain(op, 12, 4) != 0xF or get_seg_of_u32_certain(op, 8, 4) != 0 {
			Err(PSR_malformed_MSR_register)
		} else {
			Ok(MSR) # transfer register contents to PSR
		}
	} else {
		Err(UnknownPSRType)
	}
}

arm_psr_transfer_uses_spsr : U32 -> Bool
arm_psr_transfer_uses_spsr = |op| {
	get_ith_bit_u32_certain(op, 22)
}

arm_psr_transfer_uses_immediate : U32 -> Bool
arm_psr_transfer_uses_immediate = |op| {
	get_ith_bit_u32_certain(op, 25)
}

arm_psr_transfer_mrs_get_rd : U32 -> Try(GPR, [WTFisThis, UB_PSR_PC_as_dest])
arm_psr_transfer_mrs_get_rd = |op| {
	match get_gpr_12_15(op)? {
		R15 => Err(UB_PSR_PC_as_dest)
		x => Ok(x)
	}
}

arm_psr_transfer_mrs_value : U32, Cpu -> Try(U32, [InvalidMode, NoSPSR])
arm_psr_transfer_mrs_value = |op, c| {
	if arm_psr_transfer_uses_spsr(op) {
		cpu_getSPSR(c)
	} else {
		Ok(c.cpsr)
	}
}

arm_psr_transfer_mrs_execute : U32,
Cpu -> Try(
	Cpu,
	[
		InvalidMode,
		NoSPSR,
		WTFisThis,
		UB_PSR_PC_as_dest,
	],
)
arm_psr_transfer_mrs_execute = |op, c| {
	rd = arm_psr_transfer_mrs_get_rd(op)?
	val = arm_psr_transfer_mrs_value(op, c)?
	cpu_setReg(rd, c, val)
}

arm_psr_transfer_msr_operand : U32, Cpu -> Try(U32, [InvalidMode, WTFisThis, UB_PSR_PC_as_source])
arm_psr_transfer_msr_operand = |op, c| {
	if arm_psr_transfer_uses_immediate(op) {
		# Does not care about c_flag
		Ok(arm_data_processing_operands_immediate(op, Bool.False).val)
	} else {
		match get_gpr_0_3(op)? {
			R15 => Err(UB_PSR_PC_as_source)
			x => cpu_getReg(x, c)
		}
	}
}

arm_psr_transfer_field_mask : U32 -> U8
arm_psr_transfer_field_mask = |op| {
	U32.to_u8_wrap(get_seg_of_u32_certain(op, 16, 4))
}

arm_psr_transfer_msr_byte_mask : U8 -> U32
arm_psr_transfer_msr_byte_mask = |mask| {
	one_to_FF = |res, m, k| if m == 0 {
		res
	} else {
		one_to_FF(res + U32.shl_wrap(255, k) * U8.to_u32(U8.mod_by(m, 2)), m // 2, k + 8)
	}
	one_to_FF(0, mask, 0)
}

arm_psr_transfer_msr_execute : U32,
Cpu -> Try(
	Cpu,
	[
		InvalidMode,
		NoSPSR,
		WTFisThis,
		UB_PSR_PC_as_source,
		UB_PSR_reserved_bits,
		UB_PSR_non_ARM_state,
	],
)
arm_psr_transfer_msr_execute = |op, c| {
	operand = arm_psr_transfer_msr_operand(op, c)?
	if U32.bitwise_and(operand, 0x0FFFFF00) != 0 {
		Err(UB_PSR_reserved_bits)
	} else {
		# Turns out DDI01001 is wrong
		# Privileged MSR must not set CPSR.T; SPSR.T is writable.
		byte_mask = arm_psr_transfer_msr_byte_mask(arm_psr_transfer_field_mask(op))
		if arm_psr_transfer_uses_spsr(op) {
			old_spsr = cpu_getSPSR(c)?
			final_mask = U32.bitwise_and(byte_mask, 0xF00000FF)
			cpu_setSPSR(c, U32.bitwise_or(U32.bitwise_and(old_spsr, U32.bitwise_not(final_mask)), U32.bitwise_and(operand, final_mask)))
		} else {
			mode = cpsr_getMode(c.cpsr)?
			if mode != User {
				if cpsr_getT(operand) {
					Err(UB_PSR_non_ARM_state)
				} else {
					# Note: DDI 0100I A2-14: reserved CPSR M[4:0] values are UNPREDICTABLE.
					# Valid ROMs avoid them; malformed writes can make later cpsr_getMode calls fail.
					mask = U32.bitwise_and(byte_mask, 0xF00000DF)
					old_cpsr = c.cpsr
					Ok({ ..c, cpsr: U32.bitwise_or(U32.bitwise_and(old_cpsr, U32.bitwise_not(mask)), U32.bitwise_and(operand, mask)) })
				}
			} else {
				mask = U32.bitwise_and(byte_mask, 0xF0000000)
				old_cpsr = c.cpsr
				Ok({ ..c, cpsr: U32.bitwise_or(U32.bitwise_and(old_cpsr, U32.bitwise_not(mask)), U32.bitwise_and(operand, mask)) })
			}
		}
	}
}

arm_psr_transfer_execute : U32,
Cpu -> Try(
	Cpu,
	[
		InvalidMode,
		NoSPSR,
		WTFisThis,
		UB_PSR_PC_as_dest,
		UB_PSR_PC_as_source,
		UB_PSR_reserved_bits,
		UB_PSR_non_ARM_state,
		UnknownPSRType,
		PSR_malformed_MSR_immediate,
		PSR_malformed_MSR_register,
		PSR_malformed_MRS,
	],
)
arm_psr_transfer_execute = |op, c| {
	match arm_psr_transfer_decode(op)? {
		MSR => arm_psr_transfer_msr_execute(op, c)
		MRS => arm_psr_transfer_mrs_execute(op, c)
	}
}

arm_multiply_decode : U32 -> ArmMultiplyOpCode
arm_multiply_decode = |op| {
	if get_ith_bit_u32_certain(op, 21) {
		MLA
	} else {
		MUL
	}
}

# Do not confuse with multiply Long
arm_multiply_execute : U32,
Cpu -> Try(
	Cpu,
	[
		WTFisThis,
		UB_multiply_rd_rm_same,
		UB_multiply_use_of_R15,
		InvalidMode,
	],
)
arm_multiply_execute = |op, c| {
	catch_R15 = |gpr| match gpr {
		R15 => Err(UB_multiply_use_of_R15)
		x => Ok(x)
	}
	rm = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 0, 4)))?)?
	rs = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 8, 4)))?)?
	rd = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 16, 4)))?)?
	rm_val = cpu_getReg(rm, c)?
	rs_val = cpu_getReg(rs, c)?
	if rd == rm {
		Err(UB_multiply_rd_rm_same)
	} else {
		res = if arm_multiply_decode(op) == MLA {
			rn = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 12, 4)))?)?
			rn_val = cpu_getReg(rn, c)?
			U32.plus_wrap(U32.times_wrap(rm_val, rs_val), rn_val)
		} else {
			U32.times_wrap(rm_val, rs_val)
		}
		if arm_s_flag(op) {
			Ok({ ..cpu_setReg(rd, c, res)?, cpsr: cpsr_setZ(cpsr_setN(c.cpsr, get_ith_bit_u32_certain(res, 31)), res == 0) })
		} else {
			cpu_setReg(rd, c, res)
		}
	}
}

arm_multiplyLong_decode : U32 -> ArmMultiplyLongOpCode
arm_multiplyLong_decode = |op| {
	match get_seg_of_u32_certain(op, 21, 2) {
		0b00 => UMULL
		0b01 => UMLAL
		0b10 => SMULL
		_ => SMLAL
	}
}

arm_multiply_long_execute : U32,
Cpu -> Try(
	Cpu,
	[
		WTFisThis,
		UB_multiplyLong_rd_same_hi_lo,
		UB_multiplyLong_same_rdlo_rm,
		UB_multiplyLong_same_rdhi_rm,
		UB_multiplyLong_use_of_R15,
		InvalidMode,
	],
)
arm_multiply_long_execute = |op, c| {
	catch_R15 = |gpr| match gpr {
		R15 => Err(UB_multiplyLong_use_of_R15)
		x => Ok(x)
	}
	rm = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 0, 4)))?)?
	rs = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 8, 4)))?)?
	rdhi = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 16, 4)))?)?
	rdlo = catch_R15(gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 12, 4)))?)?
	rm_val = cpu_getReg(rm, c)?
	rs_val = cpu_getReg(rs, c)?
	if rdhi == rdlo {
		Err(UB_multiplyLong_rd_same_hi_lo)
	} else if rdhi == rm {
		Err(UB_multiplyLong_same_rdhi_rm)
	} else if rdlo == rm {
		Err(UB_multiplyLong_same_rdlo_rm)
	} else {
		rdhi_val = cpu_getReg(rdhi, c)?
		rdlo_val = cpu_getReg(rdlo, c)?
		m = arm_multiplyLong_decode(op)
		res = if m == UMLAL {
			U64.plus_wrap(U64.times(U32.to_u64(rm_val), U32.to_u64(rs_val)), U64.bitwise_or(U64.shl_wrap(U32.to_u64(rdhi_val), 32), U32.to_u64(rdlo_val)))
		} else if m == SMLAL {
			I64.to_u64_wrap(I64.plus_wrap(I64.times(I32.to_i64(U32.to_i32_wrap(rm_val)), I32.to_i64(U32.to_i32_wrap(rs_val))), I64.bitwise_or(I64.shl_wrap(U32.to_i64(rdhi_val), 32), U32.to_i64(rdlo_val))))
		} else if m == UMULL {
			U64.times(U32.to_u64(rm_val), U32.to_u64(rs_val))
		} else {
			I64.to_u64_wrap(I64.times(I32.to_i64(U32.to_i32_wrap(rm_val)), I32.to_i64(U32.to_i32_wrap(rs_val))))
		}
		hi = U64.to_u32_wrap(U64.shr_wrap(res, 32))
		lo = U64.to_u32_wrap(res)
		if arm_s_flag(op) {
			Ok({
				..cpu_setReg(rdlo, cpu_setReg(rdhi, c, hi)?, lo)?,
				cpsr: cpsr_setZ(cpsr_setN(c.cpsr, get_ith_bit_u32_certain(hi, 31)), (hi == 0) and (lo == 0)),
			})
		} else {
			cpu_setReg(rdlo, cpu_setReg(rdhi, c, hi)?, lo)
		}
	}
}

arm_branch_execute : U32, Cpu -> Try(Cpu, [InvalidMode, Branch_Type_Unknown])
arm_branch_execute = |op, c| {
	if bits_match_32(op, 0b1110_000000000000000000000000, 0b1010_000000000000000000000000) {
		old_PC = cpu_getReg(R15, c)?
		signed_immed_24 = get_seg_of_u32_certain(op, 0, 24)
		pc = U32.plus_wrap(
			old_PC,
			U32.plus_wrap(
				8,
				if get_ith_bit_u32_certain(signed_immed_24, 23) {
					U32.times_wrap(U32.bitwise_or(signed_immed_24, 0b111111_000000000000000000000000), 4)
				} else {
					U32.times_wrap(signed_immed_24, 4)
				},
			),
		)
		if get_ith_bit_u32_certain(op, 24) {
			cpu_setReg(R15, cpu_setReg(R14, c, pc_inc(old_PC, 4))?, pc)
		} else {
			cpu_setReg(R15, c, pc)
		}
	} else {
		Err(Branch_Type_Unknown)
	}
}

arm_branch_exchange_execute : U32, Cpu -> Try(Cpu, [InvalidMode, Branch_Exchange_malformed, WTFisThis])
arm_branch_exchange_execute = |op, c| {
	if get_seg_of_u32_certain(op, 8, 12) != 0b1111_1111_1111 {
		Err(Branch_Exchange_malformed)
	} else {
		rm = gpr_from_idx(U32.to_u8_wrap(get_seg_of_u32_certain(op, 0, 4)))?
		rm_val = if (rm != R15) {
			cpu_getReg(rm, c)?
		} else {
			# Here we go again
			pc_inc(cpu_getReg(rm, c)?, 8)
		}
		if get_seg_of_u32_certain(rm_val, 0, 2) == 2 {
			Err(Branch_Exchange_malformed)
		} else {
			Ok({ ..cpu_setReg(R15, c, U32.bitwise_and(rm_val, 0xFFFFFFFE))?, cpsr: cpsr_setT(c.cpsr, get_ith_bit_u32_certain(rm_val, 0)) })
		}
	}
}

arm_single_data_transfer_execute : U32,
Cpu -> Try(
	Execution_state,
	[
		Temp_not_done,
		WTFisThis,
		InvalidMode,
		UNPREDICTABLE,
	],
)
arm_single_data_transfer_execute = |op, c| {
	i_bit = get_ith_bit_u32_certain(op, 25)
	p_bit = get_ith_bit_u32_certain(op, 24)
	u_bit = get_ith_bit_u32_certain(op, 23)
	w_bit = get_ith_bit_u32_certain(op, 21)
	rd = get_gpr_12_15(op)?
	rn = get_gpr_16_19(op)?
	match arm_single_data_transfer_decode(op) {
		LDR => {
			base = if rn == R15 {
				pc_inc(c.regs.r15, 8)
			} else {
				cpu_getReg(rn, c)?
			}
			offset = if i_bit {
				rm = get_gpr_0_3(op)?
				pre_shift = match rm {
					R15 => return Err(UNPREDICTABLE)
					_ => cpu_getReg(rm, c)?
				}
				shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
				data_processing_shift_by_immediate(
					arm_data_processing_get_shift_type(op),
					pre_shift,
					shift_imm,
					cpsr_getC(c.cpsr),
				).val
			} else {
				get_seg_of_u32_certain(op, 0, 12)
			}
			adjusted = if u_bit {
				U32.plus_wrap(base, offset)
			} else {
				U32.minus_wrap(base, offset)
			}
			addr = if p_bit {
				if rd == R15 and get_seg_of_u32_certain(adjusted, 0, 2) != 0 {
					return Err(UNPREDICTABLE)
				} else {
					U32.bitwise_and(adjusted, 0xFFFFFFFC)
				}
			} else {
				if rd == R15 and get_seg_of_u32_certain(base, 0, 2) != 0 {
					return Err(UNPREDICTABLE)
				} else {
					U32.bitwise_and(base, 0xFFFFFFFC)
				}
			}
			Ok(
				R({
					cpu: c,
					addr: addr,
					width: W32,
					continuation: SetRegAndFinish({
						rd: rd,
						rot: RotRight(
							U8.times_wrap(
								8,
								U32.to_u8_wrap(
									get_seg_of_u32_certain(
										if p_bit {
											adjusted
										} else {
											base
										},
										0,
										2,
									),
								),
							),
						),
						wba: if w_bit or !(p_bit) {
							if rn == R15 or rd == rn or (i_bit and get_gpr_0_3(op)? == rn) {
								return Err(UNPREDICTABLE)
							} else {
								WriteBack({ rn: rn, val: adjusted })
							}
						} else {
							NoWriteBack
						},
					}),
				}),
			)
		}
		STR => {
			rd_val = if rd == R15 {
				pc_inc(c.regs.r15, 12)
			} else {
				cpu_getReg(rd, c)?
			}
			base = if rn == R15 {
				pc_inc(c.regs.r15, 8)
			} else {
				cpu_getReg(rn, c)?
			}
			offset = if i_bit {
				rm = get_gpr_0_3(op)?
				pre_shift = match rm {
					R15 => return Err(UNPREDICTABLE)
					_ => cpu_getReg(rm, c)?
				}
				shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
				data_processing_shift_by_immediate(
					arm_data_processing_get_shift_type(op),
					pre_shift,
					shift_imm,
					cpsr_getC(c.cpsr),
				).val
			} else {
				get_seg_of_u32_certain(op, 0, 12)
			}
			adjusted = if u_bit {
				U32.plus_wrap(base, offset)
			} else {
				U32.minus_wrap(base, offset)
			}
			addr = if p_bit {
				U32.bitwise_and(adjusted, 0xFFFFFFFC)
			} else {
				U32.bitwise_and(base, 0xFFFFFFFC)
			}
			Ok(
				W({
					cpu: c,
					addr: addr,
					width: W32,
					val: rd_val,
					continuation: StoreAndFinish({
						wba: if w_bit or !(p_bit) {
							if rn == R15 or rd == rn or (i_bit and get_gpr_0_3(op)? == rn) {
								return Err(UNPREDICTABLE)
							} else {
								WriteBack({ rn: rn, val: adjusted })
							}
						} else {
							NoWriteBack
						},
					}),
				}),
			)
		}
		STRB => {
			rd_val = if rd == R15 {
				return Err(UNPREDICTABLE)
			} else {
				cpu_getReg(rd, c)?
			}
			base = if rn == R15 {
				pc_inc(c.regs.r15, 8)
			} else {
				cpu_getReg(rn, c)?
			}
			offset = if i_bit {
				rm = get_gpr_0_3(op)?
				pre_shift = match rm {
					R15 => return Err(UNPREDICTABLE)
					_ => cpu_getReg(rm, c)?
				}
				shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
				data_processing_shift_by_immediate(
					arm_data_processing_get_shift_type(op),
					pre_shift,
					shift_imm,
					cpsr_getC(c.cpsr),
				).val
			} else {
				get_seg_of_u32_certain(op, 0, 12)
			}
			adjusted = if u_bit {
				U32.plus_wrap(base, offset)
			} else {
				U32.minus_wrap(base, offset)
			}
			addr = if p_bit {
				adjusted
			} else {
				base
			}
			Ok(
				W({
					cpu: c,
					addr: addr,
					width: W8,
					val: rd_val,
					continuation: StoreAndFinish({
						wba: if w_bit or !(p_bit) {
							if rn == R15 or rd == rn or (i_bit and get_gpr_0_3(op)? == rn) {
								return Err(UNPREDICTABLE)
							} else {
								WriteBack({ rn: rn, val: adjusted })
							}
						} else {
							NoWriteBack
						},
					}),
				}),
			)
		}
		LDRB => {
			if rd == R15 {
				return Err(UNPREDICTABLE)
			} else {
				base = if rn == R15 {
					pc_inc(c.regs.r15, 8)
				} else {
					cpu_getReg(rn, c)?
				}
				offset = if i_bit {
					rm = get_gpr_0_3(op)?
					pre_shift = match rm {
						R15 => return Err(UNPREDICTABLE)
						_ => cpu_getReg(rm, c)?
					}
					shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
					data_processing_shift_by_immediate(
						arm_data_processing_get_shift_type(op),
						pre_shift,
						shift_imm,
						cpsr_getC(c.cpsr),
					).val
				} else {
					get_seg_of_u32_certain(op, 0, 12)
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = if p_bit {
					adjusted
				} else {
					base
				}
				Ok(
					R({
						cpu: c,
						addr: addr,
						width: W8,
						continuation: SetRegAndFinish({
							rd: rd,
							rot: Identity,
							wba: if w_bit or !(p_bit) {
								if rn == R15 or rd == rn or (i_bit and get_gpr_0_3(op)? == rn) {
									return Err(UNPREDICTABLE)
								} else {
									WriteBack({ rn: rn, val: adjusted })
								}
							} else {
								NoWriteBack
							},
						}),
					}),
				)
			}
		}
		LDRT => {
			if rd == R15 or rd == rn or rn == R15 {
				Err(UNPREDICTABLE)
			} else {
				base = cpu_getReg(rn, c)?
				offset = if i_bit {
					rm = get_gpr_0_3(op)?
					if rm == rn {
						return Err(UNPREDICTABLE)
					} else {
						pre_shift = match rm {
							R15 => return Err(UNPREDICTABLE)
							_ => cpu_getReg(rm, c)?
						}
						shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
						data_processing_shift_by_immediate(
							arm_data_processing_get_shift_type(op),
							pre_shift,
							shift_imm,
							cpsr_getC(c.cpsr),
						).val
					}
				} else {
					get_seg_of_u32_certain(op, 0, 12)
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = base.bitwise_and(0xFFFFFFFC)
				Ok(
					R({
						cpu: c,
						addr: addr,
						width: W32,
						continuation: SetRegAndFinish({
							rd: rd,
							rot: RotRight(
								U8.times_wrap(
									8,
									get_seg_of_u32_certain(base, 0, 2).to_u8_wrap(),
								),
							),
							wba: WriteBack({ rn: rn, val: adjusted }),
						}),
					}),
				)
			}
		}
		LDRBT => {
			if rd == R15 or rd == rn or rn == R15 {
				Err(UNPREDICTABLE)
			} else {
				base = cpu_getReg(rn, c)?
				offset = if i_bit {
					rm = get_gpr_0_3(op)?
					if rm == rn {
						return Err(UNPREDICTABLE)
					} else {
						pre_shift = match rm {
							R15 => return Err(UNPREDICTABLE)
							_ => cpu_getReg(rm, c)?
						}
						shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
						data_processing_shift_by_immediate(
							arm_data_processing_get_shift_type(op),
							pre_shift,
							shift_imm,
							cpsr_getC(c.cpsr),
						).val
					}
				} else {
					get_seg_of_u32_certain(op, 0, 12)
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = base
				Ok(
					R({
						cpu: c,
						addr: addr,
						width: W8,
						continuation: SetRegAndFinish({
							rd: rd,
							rot: Identity,
							wba: WriteBack({ rn: rn, val: adjusted }),
						}),
					}),
				)
			}
		}
		STRT => {
			rd_val = if rd == R15 {
				pc_inc(c.regs.r15, 12)
			} else {
				cpu_getReg(rd, c)?
			}
			base = if rn == R15 or rd == rn {
				return Err(UNPREDICTABLE)
			} else {
				cpu_getReg(rn, c)?
			}
			offset = if i_bit {
				rm = get_gpr_0_3(op)?
				if rm == rn {
					return Err(UNPREDICTABLE)
				} else {
					pre_shift = match rm {
						R15 => return Err(UNPREDICTABLE)
						_ => cpu_getReg(rm, c)?
					}
					shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
					data_processing_shift_by_immediate(
						arm_data_processing_get_shift_type(op),
						pre_shift,
						shift_imm,
						cpsr_getC(c.cpsr),
					).val
				}
			} else {
				get_seg_of_u32_certain(op, 0, 12)
			}
			adjusted = if u_bit {
				U32.plus_wrap(base, offset)
			} else {
				U32.minus_wrap(base, offset)
			}
			addr = U32.bitwise_and(base, 0xFFFFFFFC)
			Ok(
				W({
					cpu: c,
					addr: addr,
					width: W32,
					val: rd_val,
					continuation: StoreAndFinish({ wba: WriteBack({ rn: rn, val: adjusted }) }),
				}),
			)
		}
		STRBT => {
			rd_val = if rd == R15 or rd == rn {
				return Err(UNPREDICTABLE)
			} else {
				cpu_getReg(rd, c)?
			}
			base = if rn == R15 {
				return Err(UNPREDICTABLE)
			} else {
				cpu_getReg(rn, c)?
			}
			offset = if i_bit {
				rm = get_gpr_0_3(op)?
				if rm == rn {
					return Err(UNPREDICTABLE)
				} else {
					pre_shift = match rm {
						R15 => return Err(UNPREDICTABLE)
						_ => cpu_getReg(rm, c)?
					}
					shift_imm = U32.to_u8_wrap(get_seg_of_u32_certain(op, 7, 5))
					data_processing_shift_by_immediate(
						arm_data_processing_get_shift_type(op),
						pre_shift,
						shift_imm,
						cpsr_getC(c.cpsr),
					).val
				}
			} else {
				get_seg_of_u32_certain(op, 0, 12)
			}
			adjusted = if u_bit {
				U32.plus_wrap(base, offset)
			} else {
				U32.minus_wrap(base, offset)
			}
			addr = base
			Ok(
				W({
					cpu: c,
					addr: addr,
					width: W8,
					val: rd_val,
					continuation: StoreAndFinish({
						wba: WriteBack({ rn: rn, val: adjusted }),
					}),
				}),
			)
		}
	}
}

arm_single_data_transfer_decode : U32 -> ArmSingleDataTransferOpCode
arm_single_data_transfer_decode = |op| {
	if bits_match_32(op, 0b101_00000_00000_00000_00000, 0b0) {
		if bits_match_32(op, 0b10010_00000_00000_00000_00000, 0b10_00000_00000_00000_00000) {
			STRT
		} else {
			STR
		}
	} else if bits_match_32(op, 0b101_00000_00000_00000_00000, 0b001_00000_00000_00000_00000) {
		if bits_match_32(op, 0b10010_00000_00000_00000_00000, 0b10_00000_00000_00000_00000) {
			LDRT
		} else {
			LDR
		}
	} else if bits_match_32(op, 0b101_00000_00000_00000_00000, 0b101_00000_00000_00000_00000) {
		if bits_match_32(op, 0b10010_00000_00000_00000_00000, 0b10_00000_00000_00000_00000) {
			LDRBT
		} else {
			LDRB
		}
	} else {
		if bits_match_32(op, 0b10010_00000_00000_00000_00000, 0b10_00000_00000_00000_00000) {
			STRBT
		} else {
			STRB
		}
	}
}

arm_single_data_swap_execute : U32,
Cpu -> Try(
	Execution_state,
	[
		UNPREDICTABLE,
		WTFisThis,
		InvalidMode,
	],
)
arm_single_data_swap_execute = |op, c| {
	rd = get_gpr_12_15(op)?
	rn = get_gpr_16_19(op)?
	rm = get_gpr_0_3(op)?
	if (rd == R15 or rn == R15 or rm == R15) or (rn == rm or rn == rd) {
		Err(UNPREDICTABLE)
	} else {
		match arm_single_data_swap_decode(op) {
			SWP => {
				raw_addr = cpu_getReg(rn, c)?
				bus_addr = raw_addr.bitwise_and(0xFFFFFFFC) # murder the last 2 bits to align addr val.
				rot_val = get_seg_of_u32_certain(raw_addr, 0, 2)
				Ok(
					R({
						cpu: c,
						addr: bus_addr,
						width: W32,
						continuation: GetValfromMem({
							rd: rd,
							addr: bus_addr,
							rm_val: cpu_getReg(rm, c)?,
							width: W32,
							rot: RotRight(U32.to_u8_wrap(8 * rot_val)),
						}),
					}),
				)
			}
			SWPB => {
				bus_addr = cpu_getReg(rn, c)?
				Ok(
					R({
						cpu: c,
						addr: bus_addr,
						width: W8,
						continuation: GetValfromMem({
							rd: rd,
							addr: bus_addr,
							rm_val: get_seg_of_u32_certain(cpu_getReg(rm, c)?, 0, 8),
							width: W8,
							rot: Identity,
						}),
					}),
				)
			}
		}
	}
}

arm_single_data_swap_decode : U32 -> ArmSingleDataSwapOpCode
arm_single_data_swap_decode = |op| {
	if get_ith_bit_u32_certain(op, 22) {
		SWPB
	} else {
		SWP
	}
}

arm_halfword_data_transfer_decode : U32 -> ArmHalfwordDataTransferOpCode
arm_halfword_data_transfer_decode = |op| {
	if bits_match_32(op, 0b1110_0001_000000000000_1111_0000, 0b0000_0001_000000000000_1011_0000) {
		LDRH
	} else if bits_match_32(op, 0b1110_0001_000000000000_1111_0000, 0b0000_0000_000000000000_1011_0000) {
		STRH
	} else if bits_match_32(op, 0b1110_0001_000000000000_1111_0000, 0b0000_0001_000000000000_1101_0000) {
		LDRSB
	} else if bits_match_32(op, 0b1110_0001_000000000000_1111_0000, 0b0000_0001_000000000000_1111_0000) {
		LDRSH
	} else {
		UndefinedInstruction
	}
}

arm_halfword_data_transfer_execute : U32,
Cpu -> Try(
	Execution_state,
	[
		Temp_not_done,
		WTFisThis,
		InvalidMode,
		UNPREDICTABLE,
		NoSPSR,
	],
)
arm_halfword_data_transfer_execute = |op, c| {
	i_bit = get_ith_bit_u32_certain(op, 22)
	p_bit = get_ith_bit_u32_certain(op, 24)
	u_bit = get_ith_bit_u32_certain(op, 23)
	w_bit = get_ith_bit_u32_certain(op, 21)
	rd = get_gpr_12_15(op)?
	rn = get_gpr_16_19(op)?
	match arm_halfword_data_transfer_decode(op) {
		UndefinedInstruction => Ok(
			arm_instructions_settle({
				cpu: arm_undefined_instruction_execute(c)?,
				pc_status: PCWritten,
			}),
		)
		LDRH => {
			if rd == R15 {
				return Err(UNPREDICTABLE)
			} else {
				base = if rn == R15 {
					pc_inc(c.regs.r15, 8)
				} else {
					cpu_getReg(rn, c)?
				}
				offset = if i_bit {
					immedL = get_seg_of_u32_certain(op, 0, 4)
					immedH = get_seg_of_u32_certain(op, 8, 4)
					U32.bitwise_or(U32.shl_wrap(immedH, 4), immedL)
				} else {
					if get_gpr_0_3(op)? == R15 {
						return Err(UNPREDICTABLE)
					} else {
						cpu_getReg(get_gpr_0_3(op)?, c)?
					}
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = if p_bit {
					adjusted
				} else {
					if w_bit {
						return Err(UNPREDICTABLE)
					} else {
						base
					}
				}
				if get_ith_bit_u32_certain(addr, 0) {
					Err(UNPREDICTABLE)
				} else {
					Ok(
						R({
							cpu: c,
							addr: addr,
							width: W16,
							continuation: SetRegAndFinish({
								rd: rd,
								rot: Identity,
								wba: if w_bit or !(p_bit) {
									if rd == rn or rn == R15 or (!i_bit and get_gpr_0_3(op)? == rn) {
										return Err(UNPREDICTABLE)
									} else {
										WriteBack({ rn: rn, val: adjusted })
									}
								} else {
									NoWriteBack
								},
							}),
						}),
					)
				}
			}
		}
		LDRSB => {
			if rd == R15 {
				return Err(UNPREDICTABLE)
			} else {
				base = if rn == R15 {
					pc_inc(c.regs.r15, 8)
				} else {
					cpu_getReg(rn, c)?
				}
				offset = if i_bit {
					immedL = get_seg_of_u32_certain(op, 0, 4)
					immedH = get_seg_of_u32_certain(op, 8, 4)
					U32.bitwise_or(U32.shl_wrap(immedH, 4), immedL)
				} else {
					if get_gpr_0_3(op)? == R15 {
						return Err(UNPREDICTABLE)
					} else {
						cpu_getReg(get_gpr_0_3(op)?, c)?
					}
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = if p_bit {
					adjusted
				} else {
					if w_bit {
						return Err(UNPREDICTABLE)
					} else {
						base
					}
				}
				Ok(
					R({
						cpu: c,
						addr: addr,
						width: W8,
						continuation: SetRegAndFinish({
							rd: rd,
							rot: SignedExtend8,
							wba: if w_bit or !(p_bit) {
								if rd == rn or rn == R15 or (!i_bit and get_gpr_0_3(op)? == rn) {
									return Err(UNPREDICTABLE)
								} else {
									WriteBack({ rn: rn, val: adjusted })
								}
							} else {
								NoWriteBack
							},
						}),
					}),
				)
			}
		}
		LDRSH => {
			if rd == R15 {
				return Err(UNPREDICTABLE)
			} else {
				base = if rn == R15 {
					pc_inc(c.regs.r15, 8)
				} else {
					cpu_getReg(rn, c)?
				}
				offset = if i_bit {
					immedL = get_seg_of_u32_certain(op, 0, 4)
					immedH = get_seg_of_u32_certain(op, 8, 4)
					U32.bitwise_or(U32.shl_wrap(immedH, 4), immedL)
				} else {
					if get_gpr_0_3(op)? == R15 {
						return Err(UNPREDICTABLE)
					} else {
						cpu_getReg(get_gpr_0_3(op)?, c)?
					}
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = if p_bit {
					adjusted
				} else {
					if w_bit {
						return Err(UNPREDICTABLE)
					} else {
						base
					}
				}
				if get_ith_bit_u32_certain(addr, 0) {
					Err(UNPREDICTABLE)
				} else {
					Ok(
						R({
							cpu: c,
							addr: addr,
							width: W16,
							continuation: SetRegAndFinish({
								rd: rd,
								rot: SignedExtend16,
								wba: if w_bit or !(p_bit) {
									if rd == rn or rn == R15 or (!i_bit and get_gpr_0_3(op)? == rn) {
										return Err(UNPREDICTABLE)
									} else {
										WriteBack({ rn: rn, val: adjusted })
									}
								} else {
									NoWriteBack
								},
							}),
						}),
					)
				}
			}
		}
		STRH => {
			if rd == R15 {
				return Err(UNPREDICTABLE)
			} else {
				rd_val = get_seg_of_u32_certain(cpu_getReg(rd, c)?, 0, 16)
				base = if rn == R15 {
					pc_inc(c.regs.r15, 8)
				} else {
					cpu_getReg(rn, c)?
				}
				offset = if i_bit {
					immedL = get_seg_of_u32_certain(op, 0, 4)
					immedH = get_seg_of_u32_certain(op, 8, 4)
					U32.bitwise_or(U32.shl_wrap(immedH, 4), immedL)
				} else {
					if get_gpr_0_3(op)? == R15 {
						return Err(UNPREDICTABLE)
					} else {
						cpu_getReg(get_gpr_0_3(op)?, c)?
					}
				}
				adjusted = if u_bit {
					U32.plus_wrap(base, offset)
				} else {
					U32.minus_wrap(base, offset)
				}
				addr = if p_bit {
					adjusted
				} else {
					if w_bit {
						return Err(UNPREDICTABLE)
					} else {
						base
					}
				}
				if get_ith_bit_u32_certain(addr, 0) {
					Err(UNPREDICTABLE)
				} else {
					Ok(
						W({
							cpu: c,
							addr: addr,
							width: W16,
							val: rd_val,
							continuation: StoreAndFinish({
								wba: if w_bit or !(p_bit) {
									if rd == rn or rn == R15 or (!i_bit and get_gpr_0_3(op)? == rn) {
										return Err(UNPREDICTABLE)
									} else {
										WriteBack({ rn: rn, val: adjusted })
									}
								} else {
									NoWriteBack
								},
							}),
						}),
					)
				}
			}
		}
	}
}

arm_block_data_transfer_decode : U32 -> ArmBlockDataTransferOpCode
arm_block_data_transfer_decode = |op| {
	if get_ith_bit_u32_certain(op, 20) {
		LDM
	} else {
		STM
	}
}

arm_block_data_transfer_execute : U32,
Cpu -> Try(
	Execution_state,
	[
		Temp_not_done,
		UNPREDICTABLE,
		InvalidMode,
		WTFisThis,
		NoSPSR,
	],
)
arm_block_data_transfer_execute = |op, c| {
	rn_included = |x| {
		get_ith_bit_u32_certain(x, get_seg_of_u32_certain(x, 16, 4).to_u8_wrap())
	}
	sharp_reg = |x| {
		U32.count_one_bits(get_seg_of_u32_certain(x, 0, 16))
	}
	if bits_match_32(op, 0b1_11111_11111_11111, 0) {
		Err(UNPREDICTABLE)
	} else {
		rn = get_gpr_16_19(op)?
		if rn == R15 {
			return Err(UNPREDICTABLE)
		} else {
			s_bit = get_ith_bit_u32_certain(op, 22)
			p_bit = get_ith_bit_u32_certain(op, 24)
			u_bit = get_ith_bit_u32_certain(op, 23)
			w_bit = get_ith_bit_u32_certain(op, 21)
			mode = cpsr_getMode(c.cpsr)?
			base = cpu_getReg(rn, c)?
			aligned_base = (base // 4) * 4
			span = U8.to_u32(sharp_reg(op)) * 4
			trio = if !p_bit and u_bit {
				# IA
				{
					start_addr: aligned_base,
					end_addr: U32.plus_wrap(aligned_base, span).minus_wrap(4),
					wb_addr: base.plus_wrap(span),
				}
			} else if p_bit and u_bit {
				# IB
				{
					start_addr: aligned_base.plus_wrap(4),
					end_addr: aligned_base.plus_wrap(span),
					wb_addr: base.plus_wrap(span),
				}
			} else if !p_bit and !u_bit {
				# DA
				{
					start_addr: aligned_base.minus_wrap(span).plus_wrap(4),
					end_addr: aligned_base,
					wb_addr: base.minus_wrap(span),
				}
			} else {
				# DB
				{
					start_addr: aligned_base.minus_wrap(span),
					end_addr: aligned_base.minus_wrap(4),
					wb_addr: base.minus_wrap(span),
				}
			}
			wba = if w_bit {
				WriteBack({ rn: rn, val: trio.wb_addr })
			} else {
				NoWriteBack
			}
			match arm_block_data_transfer_decode(op) {
				LDM => {
					if s_bit and (mode == User or mode == Sys) {
						Err(UNPREDICTABLE)
					} else if w_bit and rn_included(op) {
						Err(UNPREDICTABLE)
					} else if bits_match_32(op, 0b111_0000_1_000000000000000, 0b111_0000_0_000000000000000) {
						Err(UNPREDICTABLE)
					} else {
						Ok(
							R({
								cpu: c,
								addr: trio.start_addr,
								width: W32,
								continuation: LoadMultiple({
									mask: get_seg_of_u32_certain(op, 0, 16),
									next_addr: trio.start_addr.plus_wrap(4),
									wba: wba,
									kind: if !s_bit {
										CurrentBank
									} else if get_ith_bit_u32_certain(op, 15) {
										ModeChanges({ spsr: cpu_getSPSR(c)? })
									} else {
										UserBank
									},
								}),
							}),
						)
					}
				}
				STM => {
					first_reg = gpr_from_idx(U32.count_trailing_zero_bits(get_seg_of_u32_certain(op, 0, 16)))?
					if s_bit and ((mode == User or mode == Sys) or w_bit) {
						Err(UNPREDICTABLE)
					} else if w_bit and rn_included(op)
						and (get_seg_of_u32_certain(op, 16, 4).to_u8_wrap() != 0
							and U32.count_one_bits(get_seg_of_u32_certain(op, 0, get_seg_of_u32_certain(op, 16, 4).to_u8_wrap())) != 0) {
						Err(UNPREDICTABLE)
					} else {
						Ok(
							W({
								cpu: c,
								addr: trio.start_addr,
								width: W32,
								val: if first_reg == R15 {
									pc_inc(c.regs.r15, 12)
								} else if !s_bit {
									cpu_getReg(first_reg, c)?
								} else {
									regs_get(first_reg, User, c.regs)
								},
								continuation: WriteMultiple({
									mask: get_seg_of_u32_certain(op, 0, 16),
									next_addr: trio.start_addr.plus_wrap(4),
									wba: wba,
									kind: if !s_bit {
										CurrentBank
									} else {
										UserBank
									},
								}),
							}),
						)
					}
				}
			}
		}
	}
}

arm_software_interrupt_execute : Cpu -> Try(Cpu, [InvalidMode, NoSPSR])
arm_software_interrupt_execute = |c| {
	pc_val = cpu_getReg(R15, c)?
	r14_svc_new_val = pc_inc(pc_val, 4)
	old_cpsr = c.cpsr
	new_cpsr = cpsr_setI(cpsr_setT(cpsr_setMode(Sup, old_cpsr), Bool.False), Bool.True)
	c_sup = { ..c, cpsr: new_cpsr }
	cpu_setSPSR(cpu_setReg(R15, cpu_setReg(R14, c_sup, r14_svc_new_val)?, 0x8)?, old_cpsr)
}

arm_undefined_instruction_execute : Cpu -> Try(Cpu, [InvalidMode, NoSPSR])
arm_undefined_instruction_execute = |c| {
	pc_val = cpu_getReg(R15, c)?
	r14_und_new_val = pc_inc(pc_val, 4)
	old_cpsr = c.cpsr
	new_cpsr = cpsr_setI(cpsr_setT(cpsr_setMode(Undefined, old_cpsr), Bool.False), Bool.True)
	c_und = { ..c, cpsr: new_cpsr }
	cpu_setSPSR(cpu_setReg(R15, cpu_setReg(R14, c_und, r14_und_new_val)?, 0x4)?, old_cpsr)
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

thumb_instructions_finalize : Execution_outcome -> Cpu
thumb_instructions_finalize = |content| {
	match content.pc_status {
		PCSequential => {
			..content.cpu,
			regs: {
				..content.cpu.regs,
				r15: pc_inc(content.cpu.regs.r15, 2),
			},
		}
		_ => content.cpu
	}
}

thumb_instructions_decode : U16 -> Try(ThumbInstructions, [WTFisThis, UNPREDICTABLE, TEMP_NOT_DONE])
thumb_instructions_decode = |i| {
	is_dp = |op| {
		tmp = thumb_data_processing_decode(op)
		return tmp.format != UndefinedFormat and tmp.code != NoSuchOp
	}
	if bits_match_16(i, 0b1111_1111_00000000, 0b1101_1110_00000000) or bits_match_16(i, 0b11111_00000000000, 0b11101_00000000000) {
		Ok(UndefinedInstruction)
	} else if bits_match_16(i, 0b1111_1111_00000000, 0b1101_1111_00000000) {
		Ok(SoftwareInterrupt)
	} else if bits_match_16(i, 0b11111111_1_0000_111, 0b01000111_0_0000_000) # Reg BLX is not supported by old ARM
		or bits_match_16(i, 0b1111_000000000000, 0b1101_000000000000)
			or bits_match_16(i, 0b11111_00000000000, 0b11100_00000000000)
				or bits_match_16(i, 0b11111_00000000000, 0b11110_00000000000)
					or bits_match_16(i, 0b11111_00000000000, 0b11111_00000000000) {
		Ok(Branch)
	} else if is_dp(i) {
		Ok(DataProcessing)
	} else {
		Err(TEMP_NOT_DONE)
	}
}

thumb_undefined_instruction_execute : Cpu -> Try(Cpu.Execution_outcome, [InvalidMode, NoSPSR])
thumb_undefined_instruction_execute = |c| {
	pc_val = cpu_getReg(R15, c)?
	r14_und_new_val = pc_inc(pc_val, 2)
	old_cpsr = c.cpsr
	new_cpsr = cpsr_setI(cpsr_setT(cpsr_setMode(Undefined, old_cpsr), Bool.False), Bool.True)
	c_und = { ..c, cpsr: new_cpsr }
	Ok({
		cpu: cpu_setSPSR(cpu_setReg(R15, cpu_setReg(R14, c_und, r14_und_new_val)?, 0x4)?, old_cpsr)?,
		pc_status: PCWritten,
	})
}

thumb_software_interrupt_execute : Cpu -> Try(Execution_outcome, [InvalidMode, NoSPSR])
thumb_software_interrupt_execute = |c| {
	pc_val = cpu_getReg(R15, c)?
	r14_svc_new_val = pc_inc(pc_val, 2)
	old_cpsr = c.cpsr
	new_cpsr = cpsr_setI(cpsr_setT(cpsr_setMode(Sup, old_cpsr), Bool.False), Bool.True)
	c_sup = { ..c, cpsr: new_cpsr }
	Ok({
		cpu: cpu_setSPSR(cpu_setReg(R15, cpu_setReg(R14, c_sup, r14_svc_new_val)?, 0x8)?, old_cpsr)?,
		pc_status: PCWritten,
	})
}

thumb_branch_execute : U16,
Cpu -> Try(
	Execution_outcome,
	[
		InvalidMode,
		Branch_Type_Unknown,
		Huh,
		ReservedinArm7,
		WTFisThis,
		UNPREDICTABLE,
	],
)
thumb_branch_execute = |op, c| {
	if bits_match_16(op, 0b11111_00000000000, 0b11100_00000000000) {
		old_PC = cpu_getReg(R15, c)?
		signed_immed_11 = get_seg_of_u16_certain(op, 0, 11)
		extended_immed = signed_extend_u32(signed_immed_11.to_u32(), 11)
		pc = U32.plus_wrap(old_PC.plus_wrap(4), extended_immed.shl_wrap(1))
		Ok({ cpu: cpu_setReg(R15, c, pc)?, pc_status: PCWritten })
	} else if bits_match_16(op, 0b1111_000000000000, 0b1101_000000000000) {
		old_PC = cpu_getReg(R15, c)?
		signed_immed_8 = get_seg_of_u16_certain(op, 0, 8)
		extended_immed = signed_extend_u32(signed_immed_8.to_u32(), 8)
		cond_val = get_seg_of_u16_certain(op, 8, 4)
		if cond_val >= 14 {
			return Err(Branch_Type_Unknown) # SWI and undefined, should be intercepted earlier.
		} else {
			cond = arm_opcode_parse_cond(cond_val.to_u32().shl_wrap(28))?
			if condition_pass(cond, c.cpsr) {
				Ok({
					cpu: cpu_setReg(R15, c, U32.plus_wrap(old_PC.plus_wrap(4), extended_immed.shl_wrap(1)))?,
					pc_status: PCWritten,
				})
			} else {
				Ok({ cpu: c, pc_status: PCSequential })
			}
		}
	} else if bits_match_16(op, 0b111111111_0_000_111, 0b010001110_0_000_000) {
		rm = gpr_from_idx(get_seg_of_u16_certain(op, 3, 4).to_u8_wrap())?
		rm_val = cpu_getReg(rm, c)?.plus_wrap(
			if rm == R15 {
				4
			} else {
				0
			},
		)
		if get_seg_of_u32_certain(rm_val, 0, 2) == 0b10 {
			Err(UNPREDICTABLE)
		} else {
			new_cpsr = cpsr_setT(c.cpsr, get_ith_bit_u32_certain(rm_val, 0))
			pc_update = cpu_setReg(R15, c, get_seg_of_u32_certain(rm_val, 1, 31).shl_wrap(1))?
			Ok({
				cpu: { ..pc_update, cpsr: new_cpsr },
				pc_status: PCWritten,
			})
		}
	} else if bits_match_16(op, 0b111_0000000000000, 0b111_0000000000000) {
		h = get_seg_of_u16_certain(op, 11, 2)
		offset_11 = get_seg_of_u16_certain(op, 0, 11).to_u32()
		old_PC = cpu_getReg(R15, c)?
		if h == 0b10 {
			extended_immed = signed_extend_u32(offset_11, 11)
			Ok({
				cpu: cpu_setReg(R14, c, old_PC.plus_wrap(extended_immed.shl_wrap(12)).plus_wrap(4))?,
				pc_status: PCSequential,
			})
		} else if h == 0b11 {
			pc = cpu_getReg(R14, c)?.plus_wrap(offset_11.shl_wrap(1))
			r14_val = old_PC.plus_wrap(2).bitwise_or(0b1)
			Ok({
				cpu: cpu_setReg(R15, cpu_setReg(R14, c, r14_val)?, pc)?,
				pc_status: PCWritten,
			})
		} else {
			Err(Branch_Type_Unknown)
		}
	} else {
		Err(Branch_Type_Unknown)
	}
}

thumb_data_processing_execute : U16,
Cpu -> Try(
	Execution_outcome,
	[
		WTFisThis,
		UB_multiply_rd_rm_same,
		UB_multiply_use_of_R15,
		InvalidMode,
		ImpossibleFormatOpCombination(Thumb_ALUOpCode),
		UNPREDICTABLE,
	],
)
thumb_data_processing_execute = |i, c| {
	op = thumb_data_processing_decode(i)
	chk = match op.format {
		Format1 => {
			rd = get_seg_of_u16_certain(i, 0, 3).to_u32()
			rn = get_seg_of_u16_certain(i, 3, 3).to_u32()
			rm = get_seg_of_u16_certain(i, 6, 3).to_u32()
			match op.code {
				ADD => {
					base = 0b1110_00001001_0000_0000_00000000_0000
					equiv_op = base + rm + rn.shl_wrap(16) + rd.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				SUB => {
					base = 0b1110_00000101_0000_0000_00000000_0000
					equiv_op = base + rm + rn.shl_wrap(16) + rd.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		Format2 => {
			rd = get_seg_of_u16_certain(i, 0, 3).to_u32()
			rn = get_seg_of_u16_certain(i, 3, 3).to_u32()
			tri_bit_immediate = get_seg_of_u16_certain(i, 6, 3).to_u32()
			match op.code {
				ADD => {
					base = 0b1110_00101001_0000_0000_00000000_0000
					equiv_op = base + tri_bit_immediate + rn.shl_wrap(16) + rd.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				SUB => {
					base = 0b1110_00100101_0000_0000_00000000_0000
					equiv_op = base + tri_bit_immediate + rn.shl_wrap(16) + rd.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		Format3 => {
			octa_bit_immediate = get_seg_of_u16_certain(i, 0, 8).to_u32()
			rdrn = get_seg_of_u16_certain(i, 8, 3).to_u32()
			match op.code {
				ADD => {
					base = 0b1110_00101001_0000_0000_00000000_0000
					equiv_op = base + octa_bit_immediate + rdrn.shl_wrap(16) + rdrn.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				SUB => {
					base = 0b1110_00100101_0000_0000_0000_00000000
					equiv_op = base + octa_bit_immediate + rdrn.shl_wrap(16) + rdrn.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				MOV => {
					base = 0b1110_00111011_0000_0000_0000_00000000
					equiv_op = base + octa_bit_immediate + rdrn.shl_wrap(12)
					arm_data_processing_execute(equiv_op, c)
				}
				CMP => {
					base = 0b1110_00110101_0000_0000_0000_00000000
					equiv_op = base + octa_bit_immediate + rdrn.shl_wrap(16)
					arm_data_processing_execute(equiv_op, c)
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		Format4 => {
			shift_immediate = get_seg_of_u16_certain(i, 6, 5).to_u32()
			rm = get_seg_of_u16_certain(i, 3, 3).to_u32()
			rd = get_seg_of_u16_certain(i, 0, 3).to_u32()
			match op.code {
				LSL => {
					base = 0b1110_00011011_0000_0000_00000_000_0000
					equiv_op = base + shift_immediate.shl_wrap(7) + rd.shl_wrap(12) + rm
					arm_data_processing_execute(equiv_op, c)
				}
				LSR => {
					base = 0b1110_00011011_0000_0000_00000_010_0000
					equiv_op = base + shift_immediate.shl_wrap(7) + rd.shl_wrap(12) + rm
					arm_data_processing_execute(equiv_op, c)
				}
				ASR => {
					base = 0b1110_00011011_0000_0000_00000_100_0000
					equiv_op = base + shift_immediate.shl_wrap(7) + rd.shl_wrap(12) + rm
					arm_data_processing_execute(equiv_op, c)
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		Format5 => {
			rdrn = get_seg_of_u16_certain(i, 0, 3).to_u32()
			rmrs = get_seg_of_u16_certain(i, 3, 3).to_u32()
			match op.code {
				AND => {
					base = 0b1110_00000001_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				EOR => {
					base = 0b1110_00000011_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				LSL => {
					base = 0b1110_00011011_0000_0000_0000_0001_0000
					equiv_op = base + rdrn + rdrn.shl_wrap(12) + rmrs.shl_wrap(8)
					arm_data_processing_execute(equiv_op, c)
				}
				LSR => {
					base = 0b1110_00011011_0000_0000_0000_0011_0000
					equiv_op = base + rdrn + rdrn.shl_wrap(12) + rmrs.shl_wrap(8)
					arm_data_processing_execute(equiv_op, c)
				}
				ASR => {
					base = 0b1110_00011011_0000_0000_0000_0101_0000
					equiv_op = base + rdrn + rdrn.shl_wrap(12) + rmrs.shl_wrap(8)
					arm_data_processing_execute(equiv_op, c)
				}
				ADC => {
					base = 0b1110_00001011_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				SBC => {
					base = 0b1110_00001101_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				ROR => {
					base = 0b1110_00011011_0000_0000_0000_0111_0000
					equiv_op = base + rdrn + rdrn.shl_wrap(12) + rmrs.shl_wrap(8)
					arm_data_processing_execute(equiv_op, c)
				}
				TST => {
					base = 0b1110_00010001_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				NEG => {
					base = 0b1110_00100111_0000_0000_000000000000
					equiv_op = base + rdrn.shl_wrap(12) + rmrs.shl_wrap(16)
					arm_data_processing_execute(equiv_op, c)
				}
				CMP => {
					base = 0b1110_00010101_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				CMN => {
					base = 0b1110_00010111_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				ORR => {
					base = 0b1110_00011001_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				MUL => {
					base = 0b1110_00000001_0000_0000_0000_1001_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(8) + rmrs
					Ok({
						cpu: arm_multiply_execute(equiv_op, c)?,
						pc_status: PCSequential,
					})
				}
				BIC => {
					base = 0b1110_00011101_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(16) + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				MVN => {
					base = 0b1110_00011111_0000_0000_00000000_0000
					equiv_op = base + rdrn.shl_wrap(12) + rmrs
					arm_data_processing_execute(equiv_op, c)
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		Format6 => {
			shift_immediate = get_seg_of_u16_certain(i, 0, 8).to_u32()
			rd = get_seg_of_u16_certain(i, 8, 3).to_u32()
			sp_pc = get_ith_bit_u16_certain(i, 11)
			if sp_pc {
				base = 0b1110_00101000_1101_0000_1111_00000000
				equiv_op = base + shift_immediate + rd.shl_wrap(12)
				arm_data_processing_execute(equiv_op, c)
			} else {
				thumb_pc = (c.regs.r15).plus_wrap(4)
				pc_aligned = thumb_pc.bitwise_and(0xFFFFFFFC)
				tmp = shift_immediate.times_wrap(4)
				rd_new_val = pc_aligned.plus_wrap(tmp)
				Ok({
					cpu: cpu_setReg(gpr_from_idx(rd.to_u8_wrap())?, c, rd_new_val)?,
					pc_status: PCSequential,
				})
			}
		}
		Format7 => {
			sept_bit_immediate = get_seg_of_u16_certain(i, 0, 7).to_u32()
			match op.code {
				ADD => {
					base = 0b1110_00101000_1101_1101_11110_0000000
					equiv_op = base + sept_bit_immediate
					arm_data_processing_execute(equiv_op, c)
				}
				SUB => {
					base = 0b1110_00100100_1101_1101_11110_0000000
					equiv_op = base + sept_bit_immediate
					arm_data_processing_execute(equiv_op, c)
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		Format8 => {
			h1 = get_seg_of_u16_certain(i, 7, 1).to_u32()
			h2 = get_seg_of_u16_certain(i, 6, 1).to_u32()
			rm = get_seg_of_u16_certain(i, 3, 3).to_u32()
			rdrn = get_seg_of_u16_certain(i, 0, 3).to_u32()
			rm_exact = gpr_from_idx((h2.shl_wrap(3) + rm).to_u8_wrap())?
			rm_val = cpu_getReg(rm_exact, c)?.plus_wrap(
				if rm_exact == R15 {
					4
				} else {
					0
				},
			)
			match op.code {
				ADD => {
					if h1 == 0 and h1 == h2 {
						return Err(UNPREDICTABLE)
					} else {
						rd = gpr_from_idx((h1.shl_wrap(3) + rdrn).to_u8_wrap())?
						rd_val = cpu_getReg(rd, c)?.plus_wrap(
							if rd == R15 {
								4
							} else {
								0
							},
						)
						res = rd_val.plus_wrap(rm_val)
						if rd == R15 {
							Ok({
								cpu: cpu_setReg(rd, c, res.bitwise_and(0xFFFFFFFE))?, # 'When R15 is written, bit0 is IGNORED...'
								pc_status: PCWritten,
							})
						} else {
							Ok({
								cpu: cpu_setReg(rd, c, res)?,
								pc_status: PCSequential,
							})
						}
					}
				}
				MOV => {
					if (h1 == 0 and h1 == h2) {
						return Err(UNPREDICTABLE)
					} else {
						rd = gpr_from_idx((h1.shl_wrap(3) + rdrn).to_u8_wrap())?
						if rd == R15 {
							Ok({
								cpu: cpu_setReg(rd, c, rm_val.bitwise_and(0xFFFFFFFE))?,
								pc_status: PCWritten,
							})
						} else {
							Ok({
								cpu: cpu_setReg(rd, c, rm_val)?,
								pc_status: PCSequential,
							})
						}
					}
				}
				CMP => {
					if (h1 == 0 and h1 == h2) or (h1 == 1 and rdrn == 0b111) {
						return Err(UNPREDICTABLE)
					} else {
						rn = gpr_from_idx((h1.shl_wrap(3) + rdrn).to_u8_wrap())?
						rn_val = cpu_getReg(rn, c)?.plus_wrap(
							if rn == R15 {
								4
							} else {
								0
							},
						)
						# plus is minus, unsigned is signed, ....and I cannot make another joke.
						intermediate_res = add_with_carry(rn_val, rm_val.bitwise_not(), True)
						Ok({
							cpu: { ..c, cpsr: cpsr_setNZCV(c.cpsr, intermediate_res) },
							pc_status: PCSequential,
						})
					}
				}
				_ => return Err(ImpossibleFormatOpCombination({ code: op.code, format: op.format }))
			}
		}
		UndefinedFormat => return Err(UNPREDICTABLE)
	}
	match chk {
		Ok(x) => Ok(x)
		Err(UB_ShiftbyPC) | Err(NoSPSR) => Err(WTFisThis) # Shouldnt happen in thumb cases
		Err(WTFisThis) => Err(WTFisThis)
		Err(InvalidMode) => Err(InvalidMode)
	}
}

thumb_data_processing_decode : U16 -> Thumb_ALUOpCode
thumb_data_processing_decode = |i| {
	if bits_match_16(i, 0b111111_00000_00000, 0b000110_00000_00000) {
		if get_ith_bit_u16_certain(i, 9) {
			{ code: SUB, format: Format1 }
		} else {
			{ code: ADD, format: Format1 }
		}
	} else if bits_match_16(i, 0b111111_00000_00000, 0b000111_00000_00000) {
		if get_ith_bit_u16_certain(i, 9) {
			{ code: SUB, format: Format2 }
		} else {
			{ code: ADD, format: Format2 }
		}
	} else if bits_match_16(i, 0b111000_00000_00000, 0b001000_00000_00000) {
		if bits_match_16(i, 0b110_00000_00000, 0b000_00000_00000) {
			{ code: MOV, format: Format3 }
		} else if bits_match_16(i, 0b110_00000_00000, 0b010_00000_00000) {
			{ code: CMP, format: Format3 }
		} else if bits_match_16(i, 0b110_00000_00000, 0b100_00000_00000) {
			{ code: ADD, format: Format3 }
		} else {
			{ code: SUB, format: Format3 }
		}
	} else if bits_match_16(i, 0b111000_00000_00000, 0) {
		if bits_match_16(i, 0b000110_00000_00000, 0) {
			{ code: LSL, format: Format4 }
		} else if bits_match_16(i, 0b000110_00000_00000, 0b010_00000_00000) {
			{ code: LSR, format: Format4 }
		} else if bits_match_16(i, 0b000110_00000_00000, 0b100_00000_00000) {
			{ code: ASR, format: Format4 }
		} else {
			{ code: NoSuchOp, format: Format4 }
		}
	} else if bits_match_16(i, 0b111111_00000_00000, 0b010000_00000_00000) {
		if bits_match_16(i, 0b1111_000000, 0b0000_000000) {
			{ code: AND, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0001_000000) {
			{ code: EOR, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0010_000000) {
			{ code: LSL, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0011_000000) {
			{ code: LSR, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0100_000000) {
			{ code: ASR, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0101_000000) {
			{ code: ADC, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0110_000000) {
			{ code: SBC, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b0111_000000) {
			{ code: ROR, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1000_000000) {
			{ code: TST, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1001_000000) {
			{ code: NEG, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1010_000000) {
			{ code: CMP, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1011_000000) {
			{ code: CMN, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1100_000000) {
			{ code: ORR, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1101_000000) {
			{ code: MUL, format: Format5 }
		} else if bits_match_16(i, 0b1111_000000, 0b1110_000000) {
			{ code: BIC, format: Format5 }
		} else {
			{ code: MVN, format: Format5 }
		}
	} else if bits_match_16(i, 0b111100_00000_00000, 0b101000_00000_00000) {
		{ code: ADD, format: Format6 }
	} else if bits_match_16(i, 0b11111111_000_00000, 0b10110000_000_00000) {
		if bits_match_16(i, 0b1_0000000, 0b1_0000000) {
			{ code: SUB, format: Format7 }
		} else {
			{ code: ADD, format: Format7 }
		}
	} else if bits_match_16(i, 0b111111_00000_00000, 0b010001_00000_00000) {
		if bits_match_16(i, 0b11_00000000, 0b10_00000000) {
			{ code: MOV, format: Format8 }
		} else if bits_match_16(i, 0b11_00000000, 0b00_00000000) {
			{ code: ADD, format: Format8 }
		} else if bits_match_16(i, 0b11_00000000, 0b01_00000000) {
			{ code: CMP, format: Format8 }
		} else {
			{ code: NoSuchOp, format: Format8 }
		}
	} else {
		{ code: ADD, format: UndefinedFormat }
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
	U32.shr_wrap(i, 31) == 1
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
	U32.is_odd(U32.shr_wrap(i, 30))
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
	U32.shr_wrap(U32.shl_wrap(i, 2), 31) == 1
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
	U32.shr_wrap(U32.shl_wrap(i, 3), 31) == 1
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
	U32.shr_wrap(U32.shl_wrap(i, 24), 31) == 1
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
	U32.shr_wrap(U32.shl_wrap(i, 25), 31) == 1
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
	U32.shr_wrap(U32.shl_wrap(i, 26), 31) == 1
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
	i = U32.shr_wrap(U32.shl_wrap(j, 27), 27)
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
	j = U32.shl_wrap(U32.shr_wrap(i, 5), 5)
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

arm_opcode_parse_cond : U32 -> Try(Conds, [ReservedinArm7, Huh])
arm_opcode_parse_cond = |i| {
	tmp = U32.shr_wrap(i, 28)
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
