import Bus
import Cpu
import MemoryRegion

Machine :: {
	bus : Bus,
	cpu : Cpu,
}.{
	step_forward : Machine -> Try(
		Machine,
		[
			Temp_Thumb_not_implemented,
			ReservedinArm7,
			Huh,
			WTFisThis,
			InvalidMode,
			UB_ShiftbyPC,
			NoSPSR,
			PSR_malformed_MRS,
			PSR_malformed_MSR_immediate,
			PSR_malformed_MSR_register,
			UB_PSR_PC_as_dest,
			UB_PSR_PC_as_source,
			UB_PSR_non_ARM_state,
			UB_PSR_reserved_bits,
			UnknownPSRType,
			Branch_Exchange_malformed,
			Branch_Type_UnKnown,
			UB_multiply_rd_rm_same,
			UB_multiply_use_of_R15,
			UB_multiplyLong_rd_same_hi_lo,
			UB_multiplyLong_same_rdlo_rm,
			UB_multiplyLong_same_rdhi_rm,
			UB_multiplyLong_use_of_R15,
			UNPREDICTABLE,
			Temp_not_done,
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			Resume_Read_Impossible_intermediate_State,
			WriteIntoROM(U32),
		],
	)
	step_forward = |m| {
		if (m.cpu).is_thumb() {
			Err(Temp_Thumb_not_implemented)
		} else {
			cur_pc = (m.cpu).getPC()
			instruction = Bus.read32(m.bus, cur_pc)?
			match Cpu.execute_arm_opcode(m.cpu, instruction)? {
				Complete(c) => Ok({ ..m, cpu: c })
				R(box) => {
					raw_val = match box.width {
						W8 => U8.to_u32(m.bus.read8(box.addr)?)
						W16 => U16.to_u32(m.bus.read16(box.addr)?)
						W32 => m.bus.read32(box.addr)?
					}
					cpu_continue = Cpu.resume_read(
						box.cpu,
						raw_val,
						box.continuation,
					)?
					match cpu_continue {
						Complete(c) => Ok({ ..m, cpu: c })
						_ => Err(Temp_not_done)
					}
				}
				W(box) => {
					post_write_bus = match box.width {
						W8 => m.bus.write8(box.addr, U32.to_u8_wrap(box.val))?
						W16 => m.bus.write16(box.addr, U32.to_u16_wrap(box.val))?
						W32 => m.bus.write32(box.addr, box.val)?
					}
					cpu_continue = Cpu.resume_write(
						box.cpu,
						box.continuation,
					)?
					match cpu_continue {
						Complete(c) => Ok({ ..m, cpu: c, bus: post_write_bus })
						_ => Err(Temp_not_done)
					}
				}
			}
		}
	}
}
