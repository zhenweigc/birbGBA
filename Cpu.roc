GPR : [R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15]

Mode : [FIQ, Sup, Abort, IRQ, Undefined, User, Sys]

Regs : { r0 : U32, r1 : U32, r2 : U32, r3 : U32, r4 : U32, r5 : U32, r6 : U32, r7 : U32, r8 : U32, r8_fiq : U32, r9 : U32, r9_fiq : U32, r10 : U32, r10_fiq : U32, r11 : U32, r11_fiq : U32, r12 : U32, r12_fiq : U32, r13 : U32, r13_fiq : U32, r13_svc : U32, r13_abt : U32, r13_irq : U32, r13_und : U32, r14 : U32, r14_fiq : U32, r14_svc : U32, r14_abt : U32, r14_irq : U32, r14_und : U32, r15 : U32 }

Cpu := { regs : Regs, cpsr : U32, spsr_fiq : U32, spsr_svc : U32, spsr_irq : U32, spsr_und : U32, spsr_abt : U32 }

Conds : [EQ, NE, CS, CC, MI, PL, VS, VC, HI, LS, GE, LT, GT, LE, AL, NV]

ArmInstructions : [DataProcessingPSRTransfer, Multiply, MultiplyLong, SingleDataSwap, BranchAndExchange, HalfwordDataTransferRegOffset, HalfwordDataTransferImmediateOffset, SingleDataTransfer, Undefined, Branch, CoprocessorDataTransfer, CoprocessorDataOperation, CoprocessorRegisterTransfer, SoftwareInterrupt, BlockDataTransfer]

# LSB is 0th bit, not 1!
get_ith_bit_u32 : U32, U8 -> Try(Bool, [WTFisThis])
get_ith_bit_u32 = |i, j| {
	if j >= 32 {
		Err(WTFisThis)
	} else {
		Ok(U32.shift_right_by(U32.shift_left_by(i, 32 - j - 1), 31) == 1)
	}
}

opcode_match : U32, U32, U32 -> Bool
opcode_match = |i, mask, target| {
	U32.bitwise_and(i, mask) == target
}

arm_instructions_decoder : U32 -> Try(ArmInstructions, [WTFisThis])
arm_instructions_decoder = |i| {
	if opcode_match(i, 251658240, 251658240) {
		Ok(SoftwareInterrupt)
	} else if opcode_match(i, 0b0000_1111_1100_0000_0000_0000_1111_0000, 144) {
		Ok(Multiply)
	} else if opcode_match(i, 0b0000_1111_1000_0000_0000_0000_1111_0000, 8388752) {
		Ok(MultiplyLong)
	} else if opcode_match(i, 0b0000_1111_1011_0000_0000_1111_1111_0000, 16777360) {
		Ok(SingleDataSwap)
	} else if opcode_match(i, 0b0000_1111_1111_1111_1111_1111_1111_0000, 0b1001011111111111100010000) {
		Ok(BranchAndExchange)
	} else if opcode_match(i, 0b0000_1110_0100_0000_0000_1111_1001_0000, 0b10010000) and (get_ith_bit_u32(i, 6)? or get_ith_bit_u32(i, 5)?) {
		Ok(HalfwordDataTransferRegOffset)
	} else if opcode_match(i, 0b0000_1110_0100_0000_0000_0000_1001_0000, 0b0100_0000_0000_0000_1001_0000) and (get_ith_bit_u32(i, 6)? or get_ith_bit_u32(i, 5)?) {
		Ok(HalfwordDataTransferImmediateOffset)
	} else if opcode_match(i, 234881040, 100663312) {
		Ok(Undefined)
	} else if opcode_match(i, 234881024, 134217728) {
		Ok(BlockDataTransfer)
	} else if opcode_match(i, 0b1110_000000000000000000000000, 0b1010_000000000000000000000000) {
		Ok(Branch)
	} else if opcode_match(i, 0b1110_000000000000000000000000, 0b1100_000000000000000000000000) {
		Ok(CoprocessorDataTransfer)
	} else if opcode_match(i, 0b1111_00000000000000000001_0000, 0b1110_000000000000000000000000) {
		Ok(CoprocessorDataOperation)
	} else if opcode_match(i, 0b1111_00000000000000000001_0000, 0b1110_00000000000000000001_0000) {
		Ok(CoprocessorRegisterTransfer)
	} else if opcode_match(i, 0b1100_00000000000000000000_0000, 0b0100_00000000000000000000_0000) {
		Ok(SingleDataTransfer)
	} else if opcode_match(i, 0b1100_00000000000000000000_0000, 0) {
		Ok(DataProcessingPSRTransfer)
	} else {
		Err(WTFisThis)
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

cpsr_getZ : U32 -> Bool
cpsr_getZ = |i| {
	U32.is_odd(U32.shift_right_by(i, 30))
}

cpsr_getC : U32 -> Bool
cpsr_getC = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 2), 31) == 1
}

cpsr_getV : U32 -> Bool
cpsr_getV = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 3), 31) == 1
}

cpsr_getQ : U32 -> Bool
cpsr_getQ = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 4), 31) == 1
}

cpsr_getJ : U32 -> Bool
cpsr_getJ = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 7), 31) == 1
}

cpsr_getI : U32 -> Bool
cpsr_getI = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 24), 31) == 1
}

cpsr_getF : U32 -> Bool
cpsr_getF = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 25), 31) == 1
}

cpsr_getT : U32 -> Bool
cpsr_getT = |i| {
	U32.shift_right_by(U32.shift_left_by(i, 26), 31) == 1
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

cpsr_setT : U32, Bool -> U32
cpsr_setT = |i, b| {
	if b {
		U32.bitwise_or(i, 0b100000)
	} else {
		U32.bitwise_and(i, U32.bitwise_not(0b100000))
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
	m = cpsr_getMode(cpu.cpsr)
	match m {
		Ok(x) => Ok(regs_get(r, x, cpu.regs))
		_ => Err(InvalidMode)
	}
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
