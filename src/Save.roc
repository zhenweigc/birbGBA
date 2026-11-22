import SRAM
import EEPROM
import FLASH

Save := [SRAM(SRAM), EEPROM(EEPROM), FLASH(FLASH)].{
	Kind : [EEPROM, SRAM, FLASH(FLASH.Size), Unrecognized]

	detect_save_type : List(U8) -> Kind
	detect_save_type = |rom| {
		# No goto header magic :) Scan my little dude
		# https://problemkaputt.de/gbatek.htm#gbacartbackupids
		ids = [
			("EEPROM_V".to_utf8(), EEPROM),
			("SRAM_V".to_utf8(), SRAM),
			("SRAM_F_V".to_utf8(), SRAM),
			("FLASH_V".to_utf8(), FLASH(KiB64)),
			("FLASH512_V".to_utf8(), FLASH(KiB64)),
			("FLASH1M_V".to_utf8(), FLASH(KiB128)),
		]
		rom.fold_with_index_until(
			Unrecognized,
			|state, _, i| {
				if i.mod_by(4) == 0 {
					# Stolen from NBA GetBackupType()
					chunk = rom.sublist({ start: i, len: 10 })
					match ids.find_first(|(prefix, _)| chunk.starts_with(prefix)) {
						Ok((_, kind)) => Break(kind)
						Err(NotFound) => Continue(state)
					}
				} else {
					Continue(state)
				}
			},
		)
	}

	get_saved : Save -> [None, Some({ time : U64, ecc : List(U8) })]
	get_saved = |sav| {
		match sav {
			SRAM(x) => SRAM.get_saved(x)
			EEPROM(y) => EEPROM.get_saved(y)
			FLASH(z) => FLASH.get_saved(z)
		}
	}

	mark_saved : Save, [None, Some({ time : U64, ecc : List(U8) })] -> Save
	mark_saved = |sav, given| {
		match sav {
			SRAM(x) => SRAM(SRAM.set_saved(x, given))
			EEPROM(y) => EEPROM(EEPROM.set_saved(y, given))
			FLASH(z) => FLASH(FLASH.set_saved(z, given))
		}
	}

	bytes_for_save : Save -> [None, Some(List(U8))]
	bytes_for_save = |sav| match sav {
		SRAM(s) => Some(SRAM.get_bytes(s))
		EEPROM(e) => EEPROM.bytes_for_save(e)
		FLASH(f) => Some(FLASH.get_bytes(f))
	}

	read_gamepak_ram8 : Save, U32 -> Try(U8, [OutOfBounds])
	read_gamepak_ram8 = |sav, offset| {
		match sav {
			SRAM(sram) => SRAM.read8(sram, offset)
			EEPROM(_) => Ok(0xFF) # Magic value, but NBA and mGBA does rtn this, so....
			FLASH(f) => FLASH.read8(f, offset)
		}
	}

	write_gamepak_ram8 : Save, U32, U8 -> Try(Save, [OutOfBounds])
	write_gamepak_ram8 = |sav, offset, byte| {
		match sav {
			SRAM(sram) => Ok(SRAM(SRAM.write8(sram, offset, byte)?))
			EEPROM(_) => Ok(sav) # No SRAM, no write.
			FLASH(f) => Ok(FLASH(FLASH.write8(f, offset, byte)?))
		}
	}
}
