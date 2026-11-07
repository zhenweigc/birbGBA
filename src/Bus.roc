import MemoryRegion
import IoRegs
import SystemRegs
import Bits
import BusSignals
import DisplayRegs

ReadResult(val_type, type) : {
	val : val_type,
	state : [Unchanged, Updated(Box(type))], # Put the bus struct on heap rather than stack
	signal : BusSignals,
}

ReadPurpose : [Fetch, CpuData, Dma(U8)]

ReadView : {
	ewram : List(U8),
	iwram : List(U8),
	paletteram : List(U8),
	vram : List(U8),
	oam : List(U8),
	gamepak_rom : List(U8),
	bios : List(U8),
	display : DisplayRegs,
	wait_cnt : U16,
}

WritePurpose : [CpuData, Dma(U8)]

Bus := {
	ewram : List(U8),
	iwram : List(U8),
	paletteram : List(U8),
	vram : List(U8),
	oam : List(U8),
	gamepak_rom : List(U8),
	bios : List(U8),
	io_regs : IoRegs,
	signal : BusSignals,
}.{
	init : List(U8), List(U8) -> Try(Bus, [ROMSizeTooLarge, InvalidBIOSSize])
	init = |bios, rom| {
		if rom.len() > 0x02000000 {
			Err(ROMSizeTooLarge)
		} else if bios.len() != 0x4000 {
			Err(InvalidBIOSSize)
		} else {
			Ok({
				ewram: List.repeat(0, 0x40000),
				iwram: List.repeat(0, 0x8000),
				paletteram: List.repeat(0, 1024),
				vram: List.repeat(0, 0x18000),
				oam: List.repeat(0, 0x400),
				gamepak_rom: rom,
				bios: bios,
				io_regs: IoRegs.init(),
				signal: BusSignals.init(),
			})
		}
	}

	get_read_view : Bus -> ReadView
	get_read_view = |bus| {
		{
			ewram: bus.ewram,
			iwram: bus.iwram,
			paletteram: bus.paletteram,
			vram: bus.vram,
			oam: bus.oam,
			gamepak_rom: bus.gamepak_rom,
			bios: bus.bios,
			display: bus.io_regs.display,
			wait_cnt: SystemRegs.get_waitcnt(bus.io_regs.system),
		}
	}

	read8 : Bus,
	U32 -> Try(
		ReadResult(U8, Bus),
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			UnsupportedIORegOffset(U32),
		],
	)
	read8 = |bus, addr| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		(val, state) = match region {
			CPUExternalRAM => ((bus.ewram).get(U32.to_u64(relative_addr))?, Unchanged)
			CPUInternalRAM => ((bus.iwram).get(U32.to_u64(relative_addr))?, Unchanged)
			PaletteRAM => ((bus.paletteram).get(U32.to_u64(relative_addr))?, Unchanged)
			VRAM => {
				mode = DisplayRegs.get_bg_mode(bus.io_regs.display)
				window_offset = (addr - 0x6000000).mod_by(0x20000)
				if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
					(0, Unchanged)
				} else {
					((bus.vram).get(U32.to_u64(relative_addr))?, Unchanged)
				}
			}
			OAM => ((bus.oam).get(U32.to_u64(relative_addr))?, Unchanged)
			GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => {
				(
					if relative_addr.to_u64() + 1 <= bus.gamepak_rom.len() {
						(bus.gamepak_rom).get(relative_addr.to_u64())?
					} else {
						addr.shr_wrap(1 + (if (addr.mod_by(2) == 0) 0 else 8)).to_u8_wrap()
					},
					Unchanged,
				)
			}
			SystemROM => ((bus.bios).get(U32.to_u64(relative_addr))?, Unchanged)
			IORegs => {
				intermediate = IoRegs.read8(bus.io_regs, relative_addr)?
				(
					intermediate.val,
					match intermediate.reg {
						Unchanged => Unchanged
						Updated(x) => Updated(Box.box({ ..bus, io_regs: x }))
					},
				)
			}
			_ => return Err(UnsupportedRegion(region))
		}
		Ok({ val: val, state: state, signal: BusSignals.record_read8(bus.signal, addr, val) })
	}

	write8 : Bus,
	U32,
	U8 -> Try(
		Bus,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			UnsupportedIORegOffset(U32),
			WriteIntoROM(U32),
		],
	)
	write8 = |bus, addr, cxt| {
		{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
		new_signal = BusSignals.record_write8(bus.signal, addr, cxt)
		match region {
			CPUExternalRAM => Ok({
				..bus,
				ewram: (bus.ewram).set(relative_addr.to_u64(), cxt)?,
				signal: new_signal,
			})
			CPUInternalRAM => Ok({
				..bus,
				iwram: (bus.iwram).set(relative_addr.to_u64(), cxt)?,
				signal: new_signal,
			})
			PaletteRAM => {
				aligned_addr = if relative_addr.mod_by(2) == 0 {
					relative_addr
				} else {
					relative_addr - 1
				}
				Ok({
					..bus,
					paletteram: (bus.paletteram).set(aligned_addr.to_u64(), cxt)?.set(aligned_addr.plus(1).to_u64(), cxt)?,
					signal: new_signal,
				})
			}
			VRAM => {
				mode = DisplayRegs.get_bg_mode(bus.io_regs.display)
				window_offset = (addr - 0x06000000).mod_by(0x20000)
				maximum_addr = if mode < 3 {
					0x10000
				} else if mode < 6 {
					0x14000
				} else {
					0x14000 # technically banned, but somehow mGBA allows it
				}
				aligned_addr = if relative_addr.mod_by(2) == 0 {
					relative_addr
				} else {
					relative_addr - 1
				}
				if window_offset >= maximum_addr {
					Ok({ ..bus, signal: new_signal })
				} else {
					Ok({ ..bus, vram: (bus.vram).set(aligned_addr.to_u64(), cxt)?.set(aligned_addr.plus(1).to_u64(), cxt)?, signal: new_signal })
				}
			}
			OAM => Ok({ ..bus, signal: new_signal }) # GBAtek explicitly said no 1byte write
			GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Err(WriteIntoROM(addr))
			SystemROM => Ok({ ..bus, signal: new_signal })
			IORegs => Ok({
				..bus,
				io_regs: IoRegs.write8(bus.io_regs, relative_addr, cxt)?,
				signal: new_signal,
			})
			_ => Err(UnsupportedRegion(region))
		}
	}

	read16 : Bus,
	U32,
	ReadPurpose -> Try(
		ReadResult(U16, Bus),
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	read16 = |bus, addr, purpose| {
		if addr.mod_by(2) == 1 {
			Err(MisalignedAddress(addr))
		} else {
			read_le16 : List(U8), U32 -> Try(U16, [OutOfBounds])
			read_le16 = |lst, relative_addr| {
				i = lst.get(relative_addr.plus(1).to_u64())?
				j = lst.get(relative_addr.to_u64())?
				Ok(i.to_u16().shl_wrap(8) + j.to_u16())
			}
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			(val, state) = match region {
				CPUExternalRAM => (read_le16(bus.ewram, relative_addr)?, Unchanged)
				CPUInternalRAM => (read_le16(bus.iwram, relative_addr)?, Unchanged)
				PaletteRAM => (read_le16(bus.paletteram, relative_addr)?, Unchanged)
				VRAM => {
					mode = DisplayRegs.get_bg_mode(bus.io_regs.display)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						# If cond directly stolen from mGBA
						(0, Unchanged)
					} else {
						(read_le16(bus.vram, relative_addr)?, Unchanged)
					}
				}
				OAM => (read_le16(bus.oam, relative_addr)?, Unchanged)
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => {
					value = if relative_addr.to_u64() + 2 <= bus.gamepak_rom.len() {
						read_le16(bus.gamepak_rom, relative_addr)?
					} else {
						# Out of bound addr -> ROM will not WB value
						# So the CPU will just read the low 16 bits of Halfword addr back.
						addr.shr_wrap(1).to_u16_wrap()
					}
					(value, Unchanged)
				}
				SystemROM => (read_le16(bus.bios, relative_addr)?, Unchanged)
				IORegs => {
					intermediate = IoRegs.read16(bus.io_regs, relative_addr)?
					(
						intermediate.val,
						match intermediate.reg {
							Unchanged => Unchanged
							Updated(x) => Updated(Box.box({ ..bus, io_regs: x }))
						},
					)
				}
				_ => return Err(UnsupportedRegion(region))
			}
			Ok({ val: val, state: state, signal: BusSignals.record_read16(bus.signal, purpose, addr, val) })
		}
	}

	write16 : Bus,
	U32,
	U16,
	WritePurpose -> Try(
		Bus,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			WriteIntoROM(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	write16 = |bus, addr, cxt, purpose| {
		chopper = |i| {
			{ lo: i.to_u8_wrap(), hi: i.shr_wrap(8).to_u8_wrap() }
		}
		new_signal = BusSignals.record_write16(bus.signal, purpose, addr, cxt)
		if addr.mod_by(2) == 1 {
			Err(MisalignedAddress(addr))
		} else {
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			{ lo, hi } = chopper(cxt)
			match region {
				CPUExternalRAM => Ok({
					..bus,
					ewram: (bus.ewram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
					signal: new_signal,
				})
				CPUInternalRAM => Ok({
					..bus,
					iwram: (bus.iwram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
					signal: new_signal,
				})
				PaletteRAM => Ok({
					..bus,
					paletteram: (bus.paletteram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
					signal: new_signal,
				})
				VRAM => {
					mode = DisplayRegs.get_bg_mode(bus.io_regs.display)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						Ok({ ..bus, signal: new_signal })
					} else {
						Ok({
							..bus,
							vram: (bus.vram).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
							signal: new_signal,
						})
					}
				}
				OAM => Ok({
					..bus,
					oam: (bus.oam).set(relative_addr.to_u64(), lo)?.set(relative_addr.plus(1).to_u64(), hi)?,
					signal: new_signal,
				})
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Err(WriteIntoROM(addr))
				SystemROM => Ok({ ..bus, signal: new_signal })
				IORegs => Ok({
					..bus,
					io_regs: IoRegs.write16(bus.io_regs, relative_addr, cxt)?,
					signal: new_signal,
				})
				_ => Err(UnsupportedRegion(region))
			}
		}
	}

	read32 : Bus,
	U32,
	ReadPurpose -> Try(
		ReadResult(U32, Bus),
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	read32 = |bus, addr, purpose| {
		if addr.mod_by(4) > 0 {
			Err(MisalignedAddress(addr))
		} else {
			read_le32 : List(U8), U32 -> Try(U32, [OutOfBounds])
			read_le32 = |lst, relative_addr| {
				i = lst.get(relative_addr.plus(3).to_u64())?
				j = lst.get(relative_addr.plus(2).to_u64())?
				k = lst.get(relative_addr.plus(1).to_u64())?
				l = lst.get(relative_addr.to_u64())?
				Ok(i.to_u32().shl_wrap(24) + j.to_u32().shl_wrap(16) + k.to_u32().shl_wrap(8) + l.to_u32())
			}
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			(val, state) = match region {
				CPUExternalRAM => (read_le32(bus.ewram, relative_addr)?, Unchanged)
				CPUInternalRAM => (read_le32(bus.iwram, relative_addr)?, Unchanged)
				PaletteRAM => (read_le32(bus.paletteram, relative_addr)?, Unchanged)
				VRAM => {
					mode = DisplayRegs.get_bg_mode(bus.io_regs.display)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						(0, Unchanged)
					} else {
						(read_le32(bus.vram, relative_addr)?, Unchanged)
					}
				}
				OAM => (read_le32(bus.oam, relative_addr)?, Unchanged)
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => {
					(
						if relative_addr.to_u64() + 4 <= bus.gamepak_rom.len() {
							read_le32(bus.gamepak_rom, relative_addr)?
						} else {
							half = addr.shr_wrap(1)
							lo = half.bitwise_and(0xFFFF)
							hi = half.plus_wrap(1)
							hi.shl_wrap(16).bitwise_or(lo)
						},
						Unchanged,
					)
				}
				SystemROM => (read_le32(bus.bios, relative_addr)?, Unchanged)
				IORegs => {
					intermediate = IoRegs.read32(bus.io_regs, relative_addr)?
					(
						intermediate.val,
						match intermediate.reg {
							Unchanged => Unchanged
							Updated(x) => Updated(Box.box({ ..bus, io_regs: x }))
						},
					)
				}
				_ => return Err(UnsupportedRegion(region))
			}
			Ok({ val: val, state: state, signal: BusSignals.record_read32(bus.signal, purpose, addr, val) })
		}
	}

	write32 : Bus,
	U32,
	U32,
	WritePurpose -> Try(
		Bus,
		[
			OutOfBounds,
			UnsupportedRegion(MemoryRegion),
			MisalignedAddress(U32),
			WriteIntoROM(U32),
			UnsupportedIORegOffset(U32),
		],
	)
	write32 = |bus, addr, cxt, purpose| {
		chopper = |i| {
			{
				semel: i.to_u8_wrap(),
				bis: i.shr_wrap(8).to_u8_wrap(),
				ter: i.shr_wrap(16).to_u8_wrap(),
				quater: i.shr_wrap(24).to_u8_wrap(),
			}
		}
		new_signal = BusSignals.record_write32(bus.signal, purpose, addr, cxt)
		if addr.mod_by(4) > 0 {
			Err(MisalignedAddress(addr))
		} else {
			{ region, relative_addr } = MemoryRegion.memory_map_decode(addr)
			{ semel, bis, ter, quater } = chopper(cxt)
			match region {
				CPUExternalRAM => Ok({
					..bus,
					ewram: (bus.ewram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
					signal: new_signal,
				})
				CPUInternalRAM => Ok({
					..bus,
					iwram: (bus.iwram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
					signal: new_signal,
				})
				PaletteRAM => Ok({
					..bus,
					paletteram: (bus.paletteram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
					signal: new_signal,
				})
				VRAM => {
					mode = DisplayRegs.get_bg_mode(bus.io_regs.display)
					window_offset = (addr - 0x6000000).mod_by(0x20000)
					if mode >= 3 and window_offset >= 0x18000 and window_offset < 0x1c000 {
						Ok({ ..bus, signal: new_signal })
					} else {
						Ok({
							..bus,
							vram: (bus.vram).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
							signal: new_signal,
						})
					}
				}
				OAM => Ok({
					..bus,
					oam: (bus.oam).set(relative_addr.to_u64(), semel)?.set(relative_addr.plus(1).to_u64(), bis)?.set(relative_addr.plus(2).to_u64(), ter)?.set(relative_addr.plus(3).to_u64(), quater)?,
					signal: new_signal,
				})
				GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => Err(WriteIntoROM(addr))
				SystemROM => Ok({ ..bus, signal: new_signal })
				IORegs => Ok({
					..bus,
					io_regs: IoRegs.write32(bus.io_regs, relative_addr, cxt)?,
					signal: new_signal,
				})
				_ => Err(UnsupportedRegion(region))
			}
		}
	}

	requires_bios : [W8, W16, W32], U32 -> Bool
	requires_bios = |width, addr| {
		match width {
			W8 => addr == 0x4000300 or addr == 0x4000301
			W16 | W32 => addr == 0x4000300
		}
	}

	# Stolen from mGBA and NoCashGBA author's tech manual
	# https://mgba-emu.github.io/gbatek/gba.html#gbamemorymap
	# https://mgba-emu.github.io/gbatek/gba.html#gbasystemcontrol
	access_cycles : U16, [W8, W16, W32], U32, [NonSequential, Sequential] -> U64
	access_cycles = |wait_cnt, width, addr, kind| {
		region = MemoryRegion.memory_map_decode(addr).region
		match region {
			SystemROM | CPUInternalRAM | IORegs | OAM => 1
			CPUExternalRAM => match width {
				W32 => 6
				_ => 3
			}
			PaletteRAM | VRAM => match width {
				W32 => 2
				_ => 1
			}
			GamePakROMWS0 | GamePakROMWS1 | GamePakROMWS2 => {
				# Just to save some memcpy I had to break the encapsulation :)
				two_bits = match region {
					GamePakROMWS0 => Bits.get_seg_of_u16_certain(wait_cnt, 2, 2)
					GamePakROMWS1 => Bits.get_seg_of_u16_certain(wait_cnt, 5, 2)
					_ => Bits.get_seg_of_u16_certain(wait_cnt, 8, 2)
				}
				# n(onsequential)_cycles
				n_cycles = match two_bits {
					0 => 5
					1 => 4
					2 => 3
					_ => 9
				}
				s_cycles = match region {
					GamePakROMWS0 => if (Bits.get_ith_bit_u16_certain(wait_cnt, 4)) 2 else 3
					GamePakROMWS1 => if (Bits.get_ith_bit_u16_certain(wait_cnt, 7)) 2 else 5
					_ => if (Bits.get_ith_bit_u16_certain(wait_cnt, 10)) 2 else 9
				}
				first_cycles = if (kind == NonSequential or addr.mod_by(0x20000) == 0) n_cycles else s_cycles
				if (width == W32) first_cycles + s_cycles else first_cycles
			}
			GamePakRAM => match wait_cnt.bitwise_and(3) {
				0 => 5
				1 => 4
				2 => 3
				_ => 9
			}
			Unused => 1
		}
	}

	base_access_cycles : Bus, [W8, W16, W32], U32, [NonSequential, Sequential] -> U64
	base_access_cycles = |bus, width, addr, kind| {
		wait_cnt = SystemRegs.get_waitcnt(bus.io_regs.system)
		access_cycles(wait_cnt, width, addr, kind)
	}
}

resolve_read32 : U32, U32, U32 -> U32
resolve_read32 = |val, device_mask, open_bus| {
	device_bits = val.bitwise_and(device_mask)
	bus_bits = open_bus.bitwise_and(device_mask.bitwise_not())
	device_bits.bitwise_or(bus_bits)
}
