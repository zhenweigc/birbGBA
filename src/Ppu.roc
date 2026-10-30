import Bits

Ppu :: { framebuffer : List(U16) }.{
	init : () -> Ppu
	init = || { framebuffer: List.repeat(0, 240 * 160) }

	get_framebuffer : Ppu -> List(U16)
	get_framebuffer = |ppu| ppu.framebuffer

	render_scanline : Ppu,
	U16,
	List(U8),
	List(U8),
	U64,
	{
		bg0 : { cnt : U16, hofs : U16, vofs : U16 },
		bg1 : { cnt : U16, hofs : U16, vofs : U16 },
		bg2 : { cnt : U16, hofs : U16, vofs : U16 },
		bg3 : { cnt : U16, hofs : U16, vofs : U16 },
	},
	{ pa : I32, pb : I32, pc : I32, pd : I32, x : I32, y : I32 },
	List(U8),
	{
		win0h : U16,
		win1h : U16,
		win0v : U16,
		win1v : U16,
		winin : U16,
		winout : U16,
		win0_y_active : Bool,
		win1_y_active : Bool,
	},
	U16,
	{ bldcnt : U16, bldalpha : U16, bldy : U16, green_swap : U16 } -> Try(
		Ppu,
		[
			InvalidScanline(U64),
			OutOfBounds,
			TempNotSupportedMode({ dispcnt : U16, row_num : U64 }),
			ProhibitedCode,
			TempNotSupportedObj,
		],
	)
	render_scanline = |
		ppu,
		dispcnt,
		vram,
		paletteram,
		row_num,
		bgs_text,
		bg2,
		oam,
		windows,
		mosaic,
		effects,
	| {
		if row_num >= 160 {
			Err(InvalidScanline(row_num))
		} else {
			var $new_fb = ppu.framebuffer
			starting_idx = 240 * row_num
			if Bits.get_ith_bit_u16_certain(dispcnt, 7) {
				# I cannot believe ROC does not have sublist replacing.
				var $i = 0.U64
				while $i < 240 {
					$new_fb = $new_fb.set(starting_idx.plus_wrap($i), 0x7FFF)?
					$i = $i + 1
				}
			} else {
				mode = Bits.get_seg_of_u16_certain(dispcnt, 0, 3)
				backdrop_color = read_rgb555(paletteram, 0)
				effect_mode = Bits.get_seg_of_u16_certain(effects.bldcnt, 6, 2)
				if Bits.get_seg_of_u16_certain(dispcnt, 8, 5) == 0
					and mode < 6 {
					# Backdrop mode
					# Color 0 of BG Palette 0 is used as backdrop color.
					var $i = 0.U64
					adjusted_backdrop_color = brightness_rgb555(backdrop_color?, effects.bldy, effect_mode == 2)
					while $i < 240 {
						layer_mask = select_windows_mask(dispcnt, windows, $i, False)
						$new_fb = $new_fb.set(
							starting_idx.plus_wrap($i),
							if (effect_mode >= 2 and Bits.get_ith_bit_u16_certain(layer_mask, 5)
								and Bits.get_ith_bit_u16_certain(effects.bldcnt, 5)) adjusted_backdrop_color else backdrop_color?,
						)?
						$i = $i + 1
					}
				} else if mode == 0 or mode == 3 {
					bgs = [bgs_text.bg0, bgs_text.bg1, bgs_text.bg2, bgs_text.bg3]
					objs = prepare_obj_line(oam, dispcnt, row_num)?
					mosaic_h = Bits.get_seg_of_u16_certain(mosaic, 0, 4).plus_wrap(1)
					mosaic_v = Bits.get_seg_of_u16_certain(mosaic, 4, 4).plus_wrap(1)
					mosaic_y = row_num.minus_wrap(row_num.mod_by(mosaic_v.to_u64()))
					obj_mosaic_h = Bits.get_seg_of_u16_certain(mosaic, 8, 4).plus_wrap(1)
					obj_mosaic_v = Bits.get_seg_of_u16_certain(mosaic, 12, 4).plus_wrap(1)
					obj_mosaic_dy = row_num.mod_by(obj_mosaic_v.to_u64())
					var $fixed_x : I32
					var $fixed_y : I32
					bg2_mosaic_on = Bits.get_ith_bit_u16_certain(bgs_text.bg2.cnt, 6)
					if bg2_mosaic_on {
						dy = row_num.to_i32_wrap().minus_wrap(mosaic_y.to_i32_wrap())
						$fixed_x = bg2.x.minus_wrap(bg2.pb.times_wrap(dy))
						$fixed_y = bg2.y.minus_wrap(bg2.pd.times_wrap(dy))
					} else {
						$fixed_x = bg2.x
						$fixed_y = bg2.y
					}
					var $obj_latch = {
						pixel: Transparent,
						priority: 4.U16,
						mosaic_on: False,
						obj_window: False,
						semi_transparent: False,
					}
					var $i = 0.U64
					while $i < 240 {
						mosaic_x = $i.minus_wrap($i.mod_by(mosaic_h.to_u64()))
						obj_layer = sample_obj_layer(vram, paletteram, dispcnt, objs, $i, row_num, obj_mosaic_dy)?
						if !obj_layer.mosaic_on
							or !$obj_latch.mosaic_on
							or obj_layer.priority < $obj_latch.priority
							or $i.mod_by(obj_mosaic_h.to_u64()) == 0 {
							$obj_latch = obj_layer
						}
						layer_mask = select_windows_mask(dispcnt, windows, $i, obj_layer.obj_window)
						var $intermediate = Transparent
						var $best_priority = 4.U16
						var $best_layer = 5.U8
						var $second = Transparent
						var $second_priority = 4.U16
						var $second_layer = 5.U8
						if mode == 0 {
							var $j = 0.U64
							while $j < 4 {
								if Bits.get_ith_bit_u16_certain(dispcnt, (8 + $j).to_u8_wrap())
									and Bits.get_ith_bit_u16_certain(layer_mask, $j.to_u8_wrap()) {
									bg = bgs.get($j)?
									tmp = if Bits.get_ith_bit_u16_certain(bg.cnt, 6) {
										sample_text_bg(vram, paletteram, bg, mosaic_x, mosaic_y)?
									} else {
										sample_text_bg(vram, paletteram, bg, $i, row_num)?
									}
									priority = Bits.get_seg_of_u16_certain(bg.cnt, 0, 2)
									if tmp != Transparent and priority < $best_priority {
										$second_priority = $best_priority
										$second_layer = $best_layer
										$second = $intermediate
										$best_priority = priority
										$intermediate = tmp
										$best_layer = $j.to_u8_wrap()
									} else if tmp != Transparent and priority < $second_priority {
										$second = tmp
										$second_priority = priority
										$second_layer = $j.to_u8_wrap()
									}
								}
								$j = $j + 1
							}
						} else {
							if Bits.get_ith_bit_u16_certain(dispcnt, 10) and Bits.get_ith_bit_u16_certain(layer_mask, 2) {
								(sample_fixed_x, sample_fixed_y) = if bg2_mosaic_on {
									dx = ($i - mosaic_x).to_i32_wrap()
									($fixed_x.minus_wrap(bg2.pa.times_wrap(dx)), $fixed_y.minus_wrap(bg2.pc.times_wrap(dx)))
								} else {
									($fixed_x, $fixed_y)
								}
								match sample_mode3_bg(vram, sample_fixed_x, sample_fixed_y)? {
									Color(c) => {
										$intermediate = Color(c)
										$best_priority = Bits.get_seg_of_u16_certain(bgs_text.bg2.cnt, 0, 2)
										$best_layer = 2
									}
									Transparent => {}
								}
							}
						}
						match $obj_latch.pixel {
							Color(c) if Bits.get_ith_bit_u16_certain(layer_mask, 4) => {
								if $obj_latch.priority <= $best_priority {
									$second = $intermediate
									$second_layer = $best_layer
									$intermediate = Color(c)
									$best_layer = 4
								} else if $obj_latch.priority <= $second_priority {
									$second = Color(c)
									$second_layer = 4
								}
							}
							_ => {}
						}
						color = match $intermediate {
							Transparent => backdrop_color?
							Color(c) => c
						}
						normal_alpha = effect_mode == 1 and Bits.get_ith_bit_u16_certain(layer_mask, 5)
							and Bits.get_ith_bit_u16_certain(effects.bldcnt, $best_layer)
						# In NBA a topmost semi-transparent OBJ can bypass normal SFX gates.
						force_alpha = $best_layer == 4 and $obj_latch.semi_transparent
						$new_fb = if $best_layer != 5
							and (force_alpha or normal_alpha)
							and Bits.get_ith_bit_u16_certain(effects.bldcnt, 8 + $second_layer) {
							second_color = match $second {
								Transparent => backdrop_color?
								Color(c) => c
							}
							$new_fb.set(
								starting_idx.plus_wrap($i),
								blend_rgb555(color, second_color, effects.bldalpha),
							)?
						} else if Bits.get_ith_bit_u16_certain(layer_mask, 5)
							and effect_mode >= 2
							and Bits.get_ith_bit_u16_certain(effects.bldcnt, $best_layer) {
							$new_fb.set(
								starting_idx.plus_wrap($i),
								brightness_rgb555(color, effects.bldy, effect_mode == 2),
							)?
						} else {
							$new_fb.set(starting_idx.plus_wrap($i), color)?
						}
						if mode == 3 {
							$fixed_x = $fixed_x.plus_wrap(bg2.pa)
							$fixed_y = $fixed_y.plus_wrap(bg2.pc)
						}
						$i = $i + 1
					}
				} else {
					return Err(TempNotSupportedMode({ dispcnt: dispcnt, row_num: row_num }))
				}
			}
			if Bits.get_ith_bit_u16_certain(effects.green_swap, 0) {
				var $idx = 0.U64
				green_mask = 0b0000_0011_1110_0000
				rb_mask = 0b0111_1100_0001_1111
				while $idx <= 238 {
					a = $new_fb.get(starting_idx + $idx)?
					b = $new_fb.get(starting_idx + $idx + 1)?
					new_a = a.bitwise_and(rb_mask).bitwise_or(b.bitwise_and(green_mask))
					new_b = b.bitwise_and(rb_mask).bitwise_or(a.bitwise_and(green_mask))
					$new_fb = $new_fb.set(starting_idx + $idx, new_a)?.set(starting_idx + $idx + 1, new_b)?
					$idx = $idx + 2
				}
			}
			Ok({ ..ppu, framebuffer: $new_fb })
		}
	}

	sample_text_bg : List(U8),
	List(U8),
	{ cnt : U16, hofs : U16, vofs : U16 },
	U64,
	U64 -> Try(
		[Transparent, Color(U16)],
		[OutOfBounds],
	)
	sample_text_bg = |vram, paletteram, bg, screen_x, screen_y| {
		is_8bpp = Bits.get_ith_bit_u16_certain(bg.cnt, 7)
		if (screen_x > 239 or screen_y > 159) return Err(OutOfBounds)
		tile_base = Bits.get_seg_of_u16_certain(bg.cnt, 2, 2) * (16 * 1024)
		map_base = Bits.get_seg_of_u16_certain(bg.cnt, 8, 5) * (2 * 1024)
		width = if (Bits.get_ith_bit_u16_certain(bg.cnt, 14)) 512 else 256
		height = if (Bits.get_ith_bit_u16_certain(bg.cnt, 15)) 512 else 256
		source_x = screen_x.plus_wrap(bg.hofs.to_u64()).mod_by(width)
		source_y = screen_y.plus_wrap(bg.vofs.to_u64()).mod_by(height)
		(tile_x, tile_y) = (source_x // 8, source_y // 8)
		(pixel_x, pixel_y) = (source_x.mod_by(8), source_y.mod_by(8))
		block = ((tile_y // 32).times_wrap(width // 256)).plus_wrap(tile_x // 32)
		within_block = tile_y.mod_by(32).times_wrap(32).plus_wrap(tile_x.mod_by(32))
		entry_offset = map_base.to_u64().plus_wrap(block.times_wrap(32 * 32 * 2)).plus_wrap(within_block.times_wrap(2))
		if (entry_offset.plus_wrap(1) >= 65536) return Err(OutOfBounds)
		entry = vram.get(entry_offset)?.to_u16() + vram.get(entry_offset.plus_wrap(1))?.to_u16().shl_wrap(8)
		tile_num = Bits.get_seg_of_u16_certain(entry, 0, 10)
		flip_x = Bits.get_ith_bit_u16_certain(entry, 10)
		flip_y = Bits.get_ith_bit_u16_certain(entry, 11)
		palette_num = Bits.get_seg_of_u16_certain(entry, 12, 4)
		sample_x = if (flip_x) 7 - pixel_x else pixel_x
		sample_y = if (flip_y) 7 - pixel_y else pixel_y
		pixel_index = tile_num.to_u64().times_wrap(64).plus_wrap(sample_y.times_wrap(8)).plus_wrap(sample_x)
		pixel_offset = if (is_8bpp) tile_base.to_u64().plus_wrap(pixel_index) else tile_base.to_u64().plus_wrap(pixel_index // 2)
		if (pixel_offset >= 65536) return Err(OutOfBounds)
		raw_idx = vram.get(pixel_offset)?
		final_idx = if is_8bpp {
			raw_idx
		} else {
			lsb = if (sample_x.mod_by(2) == 0) 0 else 4
			Bits.get_seg_of_u8_certain(raw_idx, lsb, 4)
		}
		if (final_idx == 0) return Ok(Transparent)
		p_idx = if is_8bpp {
			final_idx.to_u64()
		} else {
			palette_num.times_wrap(16).plus_wrap(final_idx.to_u16()).to_u64()
		}
		p_offset = p_idx.times_wrap(2)
		color = read_rgb555(paletteram, p_offset)?
		Ok(Color(color))
	}
}

read_rgb555 : List(U8), U64 -> Try(U16, [OutOfBounds])
read_rgb555 = |lst, idx| {
	Ok(
		List.get(lst, idx)?.to_u16()
			+ List.get(lst, idx.plus_wrap(1))?.bitwise_and(0b111_1111).to_u16().shl_wrap(8),
	)
}

decode_size : U16, U16 -> Try((U64, U64), [OutOfBounds, ProhibitedCode])
decode_size = |shape, size| {
	# P67, OBJ Size
	if (shape > 2 or size > 3) return Err(ProhibitedCode)
	sizes = [
		(8, 8),
		(16, 16),
		(32, 32),
		(64, 64),
		(16, 8),
		(32, 8),
		(32, 16),
		(64, 32),
		(8, 16),
		(8, 32),
		(16, 32),
		(32.U64, 64.U64),
	]
	sizes.get(shape.to_u64() * 4 + size.to_u64())
}

read_obj : List(U8),
U64 -> Try(
	{ attr0 : U16, attr1 : U16, attr2 : U16 },
	[OutOfBounds],
)
read_obj = |oam, obj_num| {
	if obj_num >= 128 {
		Err(OutOfBounds)
	} else {
		base = obj_num * 8
		Ok({
			attr0: List.get(oam, base)?.to_u16()
				+ List.get(oam, base.plus_wrap(1))?.to_u16().shl_wrap(8),
			attr1: List.get(oam, base.plus_wrap(2))?.to_u16()
				+ List.get(oam, base.plus_wrap(3))?.to_u16().shl_wrap(8),
			attr2: List.get(oam, base.plus_wrap(4))?.to_u16()
				+ List.get(oam, base.plus_wrap(5))?.to_u16().shl_wrap(8),
		})
	}
}

sample_obj_index : List(U8),
U16,
{
	attr0 : U16,
	attr1 : U16,
	attr2 : U16,
	affine : [None, Matrix({ pa : I32, pb : I32, pc : I32, pd : I32 })],
	width : U64,
	height : U64,
},
U64,
U64,
U64 -> Try(
	[Outside, Transparent, Index(U8)],
	[
		OutOfBounds,
		TempNotSupportedObj,
		ProhibitedCode,
	],
)
sample_obj_index = |vram, dispcnt, obj, screen_x, screen_y, obj_mosaic_dy| {
	if (screen_x >= 240 or screen_y >= 160) return Err(OutOfBounds)
	is_8bpp = Bits.get_ith_bit_u16_certain(obj.attr0, 13)
	is_2d = !Bits.get_ith_bit_u16_certain(dispcnt, 6)
	if (Bits.get_seg_of_u16_certain(obj.attr0, 8, 2) == 2) return Ok(Outside)
	obj_mode = Bits.get_seg_of_u16_certain(obj.attr0, 10, 2)
	if (obj_mode == 3) return Err(TempNotSupportedObj)
	mode = Bits.get_seg_of_u16_certain(dispcnt, 0, 3)
	obj_x = Bits.get_seg_of_u16_certain(obj.attr1, 0, 9)
	obj_y = Bits.get_seg_of_u16_certain(obj.attr0, 0, 8)
	shape = Bits.get_seg_of_u16_certain(obj.attr0, 14, 2)
	flip_x = Bits.get_ith_bit_u16_certain(obj.attr1, 12)
	flip_y = Bits.get_ith_bit_u16_certain(obj.attr1, 13)
	local_x = screen_x.plus_wrap(512).minus_wrap(obj_x.to_u64()).mod_by(512)
	local_y = screen_y.plus_wrap(256).minus_wrap(obj_y.to_u64()).mod_by(256)
	if (shape == 3) return Err(ProhibitedCode)
	(width, height) = (obj.width, obj.height)
	box_height = if (Bits.get_seg_of_u16_certain(obj.attr0, 8, 2) == 3) height * 2 else height
	box_width = if (Bits.get_seg_of_u16_certain(obj.attr0, 8, 2) == 3) width * 2 else width
	# Current screen pixel is outside this OBJ
	if (local_x >= box_width or local_y >= box_height) return Ok(Outside)
	adjusted_y = if (obj_mode != 2
		and Bits.get_ith_bit_u16_certain(obj.attr0, 12)) local_y.minus_wrap(local_y.min(obj_mosaic_dy)) else local_y
	(sample_x, sample_y) = match obj.affine {
		None => {
			x = if (flip_x) width.minus_wrap(1).minus_wrap(local_x) else local_x
			y = if (flip_y) height.minus_wrap(1).minus_wrap(adjusted_y) else adjusted_y
			(x, y)
		}
		Matrix(p) => {
			dx = local_x.to_i32_wrap().minus_wrap((box_width // 2).to_i32_wrap())
			dy = adjusted_y.to_i32_wrap().minus_wrap((box_height // 2).to_i32_wrap())
			fixed_x = p.pa * dx + p.pb * dy + width.to_i32_wrap() * 128
			fixed_y = p.pc * dx + p.pd * dy + height.to_i32_wrap() * 128
			if fixed_x < 0 or fixed_x >= (width * 256).to_i32_wrap()
				or fixed_y < 0 or fixed_y >= (height * 256).to_i32_wrap() {
				return Ok(Outside)
			} else {
				((fixed_x // 256).to_u64_wrap(), (fixed_y // 256).to_u64_wrap())
			}
		}
	}
	tile_x = sample_x // 8
	tile_y = sample_y // 8
	tile_units = if (is_8bpp) 2 else 1
	raw_tile_num = Bits.get_seg_of_u16_certain(obj.attr2, 0, 10).to_u64()
	if (mode > 2 and raw_tile_num < 512) return Ok(Outside)
	base_tile_num = if (is_8bpp and is_2d) raw_tile_num.bitwise_and(0b1111_1111_1111_1110) else raw_tile_num
	tile_num = if is_2d {
		column = (base_tile_num.mod_by(32).plus_wrap(tile_x.times_wrap(tile_units))).mod_by(32)
		row = (base_tile_num // 32).plus_wrap(tile_y).mod_by(32)
		row.times_wrap(32).plus_wrap(column)
	} else {
		tile_row_stride = (width // 8).times_wrap(tile_units)
		tile_offset_units = tile_y.times_wrap(tile_row_stride).plus_wrap(tile_x.times_wrap(tile_units))
		base_tile_num.plus_wrap(tile_offset_units).mod_by(1024)
	}
	tile_start = (0x10000.U64).plus_wrap(tile_num.times_wrap(32))
	pixel_x = sample_x.mod_by(8)
	pixel_y = sample_y.mod_by(8)
	byte_offset = if (is_8bpp) pixel_y.times_wrap(8).plus_wrap(pixel_x) else pixel_y.times_wrap(4).plus_wrap(pixel_x // 2)
	pixel_addr = (0x10000.U64).plus_wrap(tile_start.plus_wrap(byte_offset).mod_by(0x8000))
	pixel_byte = vram.get(pixel_addr)?
	final_idx = if is_8bpp {
		pixel_byte
	} else {
		lsb = if (pixel_x.mod_by(2) == 0) 0 else 4
		Bits.get_seg_of_u8_certain(pixel_byte, lsb, 4)
	}
	if (final_idx == 0) Ok(Transparent) else Ok(Index(final_idx))
}

sample_obj : List(U8),
List(U8),
U16,
{
	attr0 : U16,
	attr1 : U16,
	attr2 : U16,
	affine : [None, Matrix({ pa : I32, pb : I32, pc : I32, pd : I32 })],
	width : U64,
	height : U64,
},
U64,
U64,
U64 -> Try(
	[Outside, Transparent, Color(U16), ObjWindow],
	[
		OutOfBounds,
		TempNotSupportedObj,
		ProhibitedCode,
	],
)
sample_obj = |vram, paletteram, dispcnt, obj, screen_x, screen_y, obj_mosaic_dy| {
	match sample_obj_index(vram, dispcnt, obj, screen_x, screen_y, obj_mosaic_dy)? {
		Index(final_idx) => {
			obj_mode = Bits.get_seg_of_u16_certain(obj.attr0, 10, 2)
			# Impossible to have mode 3 here
			if obj_mode == 2 {
				Ok(ObjWindow)
			} else {
				is_8bpp = Bits.get_ith_bit_u16_certain(obj.attr0, 13)
				palette_num = Bits.get_seg_of_u16_certain(obj.attr2, 12, 4)
				p_idx = if is_8bpp {
					final_idx.to_u64()
				} else {
					palette_num.times_wrap(16).plus_wrap(final_idx.to_u16()).to_u64()
				}
				p_offset = p_idx.times_wrap(2) + 0x200
				color = read_rgb555(paletteram, p_offset)?
				Ok(Color(color))
			}
		}
		Outside => Ok(Outside)
		Transparent => Ok(Transparent)
	}
}

sample_obj_layer : List(U8),
List(U8),
U16,
List(
	{
		attr0 : U16,
		attr1 : U16,
		attr2 : U16,
		affine : [None, Matrix({ pa : I32, pb : I32, pc : I32, pd : I32 })],
		width : U64,
		height : U64,
	},
),
U64,
U64,
U64 -> Try(
	{
		pixel : [Transparent, Color(U16)],
		priority : U16,
		mosaic_on : Bool,
		obj_window : Bool,
		semi_transparent : Bool,
	},
	[OutOfBounds, TempNotSupportedObj, ProhibitedCode],
)
sample_obj_layer = |vram, paletteram, dispcnt, objs, screen_x, screen_y, obj_mosaic_dy| {
	if Bits.get_ith_bit_u16_certain(dispcnt, 12) {
		var $pixel = Transparent
		var $priority = 4.U16
		var $obj_window = False
		obj_count = objs.len()
		var $obj_idx = 0.U64
		var $mosaic_on = False
		var $semi_transparent = False
		while $obj_idx < obj_count {
			obj = objs.get($obj_idx)?
			obj_mode = Bits.get_seg_of_u16_certain(obj.attr0, 10, 2)
			cur_priority = Bits.get_seg_of_u16_certain(obj.attr2, 10, 2)
			cur_mosaic_on = obj_mode != 2 and Bits.get_ith_bit_u16_certain(obj.attr0, 12)
			sampled = sample_obj(vram, paletteram, dispcnt, obj, screen_x, screen_y, obj_mosaic_dy)?
			# Transparent OBJ texels may update priority/mosaic without replacing color or its alpha flag.
			if (sampled == Outside) {} else if sampled == Transparent {
				if cur_priority < $priority or $pixel == Transparent {
					$priority = cur_priority
					$mosaic_on = cur_mosaic_on
				}
			} else if sampled == ObjWindow {
				$obj_window = True
			} else {
				if cur_priority < $priority or $pixel == Transparent {
					$priority = cur_priority
					$pixel = sampled
					$mosaic_on = cur_mosaic_on
					$semi_transparent = obj_mode == 1
				}
			}
			$obj_idx = $obj_idx + 1
		}
		match $pixel {
			Color(c) => Ok({ pixel: Color(c), priority: $priority, mosaic_on: $mosaic_on, obj_window: $obj_window, semi_transparent: $semi_transparent })
			_ => Ok({ pixel: Transparent, priority: $priority, mosaic_on: $mosaic_on, obj_window: $obj_window, semi_transparent: $semi_transparent })
		}
	} else {
		Ok({ pixel: Transparent, priority: 4.U16, mosaic_on: False, obj_window: False, semi_transparent: False }) # again, 4 is a fake priority.
	}
}

prepare_obj_line : List(U8),
U16,
U64 -> Try(
	List(
		{
			attr0 : U16,
			attr1 : U16,
			attr2 : U16,
			affine : [
				None,
				Matrix(
					{ pa : I32, pb : I32, pc : I32, pd : I32 },
				),
			],
			width : U64,
			height : U64,
		},
	),
	[OutOfBounds, ProhibitedCode],
)
prepare_obj_line = |oam, dispcnt, row_num| {
	if !Bits.get_ith_bit_u16_certain(dispcnt, 12) {
		Ok([])
	} else if row_num >= 160 {
		Err(OutOfBounds)
	} else {
		var $objs = []
		var $i = 0.U64
		while $i < 128 {
			obj = read_obj(oam, $i)?
			if Bits.get_seg_of_u16_certain(obj.attr0, 8, 2) != 2 {
				shape = Bits.get_seg_of_u16_certain(obj.attr0, 14, 2)
				size = Bits.get_seg_of_u16_certain(obj.attr1, 14, 2)
				(width, height) = decode_size(shape, size)?
				box_height = if (Bits.get_seg_of_u16_certain(obj.attr0, 8, 2) == 3) height * 2 else height
				obj_y = Bits.get_seg_of_u16_certain(obj.attr0, 0, 8).to_u64()
				end_y = obj_y.plus_wrap(box_height).mod_by(256)
				# a wrapped OBJ end Y keeps only the top segment, stolen from NBA
				if (row_num >= obj_y or end_y < obj_y) and row_num < end_y {
					affine = if Bits.get_ith_bit_u16_certain(obj.attr0, 8) {
						matrix_idx = Bits.get_seg_of_u16_certain(obj.attr1, 9, 5).to_u64()
						Matrix(read_obj_affine(oam, matrix_idx)?)
					} else {
						None
					}
					$objs = $objs.append({
						attr0: obj.attr0,
						attr1: obj.attr1,
						attr2: obj.attr2,
						affine: affine,
						width: width,
						height: height,
					})
				}
			}
			$i = $i + 1
		}
		Ok($objs)
	}
}

window_x_contains : U16, U64 -> Bool
window_x_contains = |winh, screen_x| {
	left = Bits.get_seg_of_u16_certain(winh, 8, 8).to_u64()
	right = Bits.get_seg_of_u16_certain(winh, 0, 8).to_u64()
	if left < right {
		screen_x >= left and screen_x < right
	} else if left > right {
		screen_x >= left or screen_x < right
	} else False
}

select_windows_mask : U16,
{
	win0h : U16,
	win1h : U16,
	win0v : U16,
	win1v : U16,
	winin : U16,
	winout : U16,
	win0_y_active : Bool,
	win1_y_active : Bool,
},
U64,
Bool -> U16
select_windows_mask = |dispcnt, windows, screen_x, obj_window| {
	if Bits.get_seg_of_u16_certain(dispcnt, 13, 3) == 0 {
		# Effects Obj BG3 ... BG0, 1 -> Layer in the composition of this pixel
		0b11_1111.U16
	} else if windows.win0_y_active
		and Bits.get_ith_bit_u16_certain(dispcnt, 13)
		and window_x_contains(windows.win0h, screen_x) {
		Bits.get_seg_of_u16_certain(windows.winin, 0, 6)
	} else if windows.win1_y_active
		and Bits.get_ith_bit_u16_certain(dispcnt, 14)
		and window_x_contains(windows.win1h, screen_x) {
		Bits.get_seg_of_u16_certain(windows.winin, 8, 6)
	} else if obj_window and Bits.get_ith_bit_u16_certain(dispcnt, 15) {
		Bits.get_seg_of_u16_certain(windows.winout, 8, 6)
	} else {
		Bits.get_seg_of_u16_certain(windows.winout, 0, 6)
	}
}

sample_mode3_bg : List(U8), I32, I32 -> Try([Transparent, Color(U16)], [OutOfBounds])
sample_mode3_bg = |vram, fixed_x, fixed_y| {
	if fixed_x >= 240 * 256 or fixed_x < 0 or fixed_y >= 160 * 256 or fixed_y < 0 {
		Ok(Transparent)
	} else {
		(source_x, source_y) = (fixed_x // 256, fixed_y // 256)
		offset = 2 * (source_y * 240 + source_x)
		Ok(Color(read_rgb555(vram, offset.to_u64_wrap())?))
	}
}

read_obj_affine : List(U8),
U64 -> Try(
	{ pa : I32, pb : I32, pc : I32, pd : I32 },
	[OutOfBounds],
)
read_obj_affine = |oam, matrix_idx| {
	two_comp_transform_u16 = |x| if (Bits.get_ith_bit_u16_certain(x, 15)) x.to_i32().minus_wrap(65536) else x.to_i32()
	if matrix_idx >= 32 {
		Err(OutOfBounds)
	} else {
		base = matrix_idx * 32
		Ok({
			pa: two_comp_transform_u16(
				List.get(oam, base + 0x6)?.to_u16()
					+ List.get(oam, base + 0x7)?.to_u16().shl_wrap(8),
			),
			pb: two_comp_transform_u16(
				List.get(oam, base + 0xE)?.to_u16()
					+ List.get(oam, base + 0xF)?.to_u16().shl_wrap(8),
			),
			pc: two_comp_transform_u16(
				List.get(oam, base + 0x16)?.to_u16()
					+ List.get(oam, base + 0x17)?.to_u16().shl_wrap(8),
			),
			pd: two_comp_transform_u16(
				List.get(oam, base + 0x1E)?.to_u16()
					+ List.get(oam, base + 0x1F)?.to_u16().shl_wrap(8),
			),
		})
	}
}

blend_rgb555 : U16, U16, U16 -> U16
blend_rgb555 = |color_1, color_2, bldalpha| {
	# RGB555 policy: sum weighted channels before truncation, then saturate to 31.
	ev1 = Bits.get_seg_of_u16_certain(bldalpha, 0, 5).min(16)
	ev2 = Bits.get_seg_of_u16_certain(bldalpha, 8, 5).min(16)
	mixed_r = (31.U16).min(
		(Bits.get_seg_of_u16_certain(color_1, 0, 5) * ev1
			+ Bits.get_seg_of_u16_certain(color_2, 0, 5) * ev2) // 16,
	)
	mixed_g = (31.U16).min(
		(Bits.get_seg_of_u16_certain(color_1, 5, 5) * ev1
			+ Bits.get_seg_of_u16_certain(color_2, 5, 5) * ev2) // 16,
	)
	mixed_b = (31.U16).min(
		(Bits.get_seg_of_u16_certain(color_1, 10, 5) * ev1
			+ Bits.get_seg_of_u16_certain(color_2, 10, 5) * ev2) // 16,
	)
	mixed_r + mixed_g * 32 + mixed_b * 1024
}

brightness_rgb555 : U16, U16, Bool -> U16
brightness_rgb555 = |color, bldy, increase| {
	# Truncate the brightness adjustment before adding or subtracting it.
	evy = Bits.get_seg_of_u16_certain(bldy, 0, 5).min(16)
	r = Bits.get_seg_of_u16_certain(color, 0, 5)
	g = Bits.get_seg_of_u16_certain(color, 5, 5)
	b = Bits.get_seg_of_u16_certain(color, 10, 5)
	(r_adjusted, g_adjusted, b_adjusted) = if increase {
		(
			r + ((31 - r) * evy // 16),
			g + ((31 - g) * evy // 16),
			b + ((31 - b) * evy // 16),
		)
	} else {
		(
			r - (r * evy // 16),
			g - (g * evy // 16),
			b - (b * evy // 16),
		)
	}
	r_adjusted + g_adjusted * 32 + b_adjusted * 1024
}
