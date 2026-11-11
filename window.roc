app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.12.1/EtDK2uhnAG7oAzez8RX5YV9wohQzzuSfHmzBM19hCdWw.tar.zst" }

import rr.App
import rr.Keys
import rr.Color
import rr.Draw
import rr.Texture
import rr.Assets
import rr.Trace
import rr.Files
import rr.Task

import src/Machine
import src/SRAM
import src/Bus
import src/Bits

Binding : { host : Keys.Key, mask : U16 }

KeyLayout : { name : Str, bindings : List(Binding) }

wasd = [KeyK, KeyJ, KeyBackspace, KeyEnter, KeyD, KeyA, KeyW, KeyS, KeySemicolon, KeyL]

arrows = [KeyX, KeyZ, KeyBackspace, KeyEnter, KeyRight, KeyLeft, KeyUp, KeyDown, KeyS, KeyA]

make_bindings : List(Keys.Key) -> List(Binding)
make_bindings = |keys| List.map_with_index(
	keys,
	|host, i| {
		{ host, mask: (1.U16).shl_wrap(i.to_u8_wrap()) }
	},
)

default_key_layouts : List(KeyLayout)
default_key_layouts = [
	{
		name: "Arrows",
		bindings: make_bindings(arrows),
	},
	{
		name: "Wasd",
		bindings: make_bindings(wasd),
	},
]

Model : {
	machine : Machine,
	texture : Texture,
	next_vblank : U64,
	speed_baseline : [None, Some({ host_ns : U64, gba_cycles : U64 })],
	pacing_baseline : [None, Some({ host_ns : U64, gba_cycles : U64 })],
	cycles_per_second : F64,
	paused : Bool,
	layout_pick : U64,
	save_dir : Files.Dir,
	save_status : [Idle, Saving, Failed(Files.WriteError)],
	last_save_attempt_ns : U64,
	closing : Bool,
}

Msg : [
	SaveFinished(Try({ time : U64, ecc : List(U8) }, Files.WriteError)),
]

program = { init!, update!, render! }

init! : App.Init(Model, _)
init! = App.init(
	App.default
		.with_title("birbGBA")
		.with_size({ width: 960, height: 640 })
		.with_frame_pacing(Capped(240))
		.with_permission(WorkingDirectory(ReadWrite))
		.with_close_request(Deliver)
		.with_exit_key(NoExitKey),
	|io| {
		dir = io.files().working_directory!()?
		bios = dir.read_bytes!("bios.bin")?
		rom = dir.read_bytes!("game.gba")?
		save = load_save!(dir)?
		machine = Machine.init(bios, rom, save)?

		texture = Assets.generate_color_texture!({
			width: 240,
			height: 160,
			color: Color.black,
		})?
		Assets.set_texture_filter!(texture, Point)

		Ok({
			machine,
			texture,
			next_vblank: 160 * 1232,
			speed_baseline: None,
			pacing_baseline: None,
			cycles_per_second: 0,
			paused: False,
			layout_pick: 0,
			save_dir: dir,
			save_status: Idle,
			last_save_attempt_ns: 0,
			closing: False,
		})
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, _)
update! = |old_model, input, _io| {
	received = input.messages.fold(old_model, apply_save_message)
	nxt = if (input.window.close_requested or input.devices.key_pressed(KeyEscape)) { ..received, closing: True } else received
	if (nxt.closing) return finish_close!(nxt, input)

	model = if (save_due(nxt, input.time.monotonic_nanos)) start_save!(nxt, input)? else nxt
	if input.devices.key_pressed(KeyP) {
		new_pause = !model.paused
		Ok({
			..model,
			paused: new_pause,
			speed_baseline: None,
			pacing_baseline: None,
			cycles_per_second: 0,
		})
	} else if input.devices.key_pressed(KeyLeftAlt) or input.devices.key_pressed(KeyRightAlt) {
		Ok({ ..model, layout_pick: model.layout_pick.plus_wrap(1).mod_by(default_key_layouts.len()) })
	} else {
		if (model.paused) return Ok(model)
		host_ns = input.time.monotonic_nanos
		gba_cycles = Machine.get_time(model.machine)
		pacing = match model.pacing_baseline {
			None => { host_ns, gba_cycles }
			Some(x) => {
				if host_ns < x.host_ns or gba_cycles < x.gba_cycles {
					{ host_ns, gba_cycles }
				} else {
					x
				}
			}
		}

		elapsed_ns = host_ns - pacing.host_ns
		elapsed_cycles = (elapsed_ns.to_u128() * 16_777_216 // 1_000_000_000).to_u64_wrap()

		target_cycles = pacing.gba_cycles + elapsed_cycles

		layout = default_key_layouts.get(model.layout_pick)?
		held
			=List.keep_if(layout.bindings, (|binding| input.devices.key_down(binding.host)))
		masks = List.map(held, (|binding| binding.mask))
		pressed = List.fold(masks, 0, U16.bitwise_or)
		m = Machine.set_pressed(model.machine, pressed)
		(new_baseline, new_cps) = match model.speed_baseline {
			None => (Some({ host_ns, gba_cycles }), model.cycles_per_second)
			Some(x) => {
				if host_ns < x.host_ns or gba_cycles < x.gba_cycles {
					# I do not think this is ever possible though
					# what kind of people play an emulator and wraps around entire U64?
					(Some({ host_ns, gba_cycles }), 0.F64)
				}
				else {
					(diff_ns, diff_cycles) = (host_ns - x.host_ns, gba_cycles - x.gba_cycles)
					if diff_ns >= 1_000_000_000 {
						cps = diff_cycles.to_f64() * 1_000_000_000 / diff_ns.to_f64()
						(Some({ host_ns, gba_cycles }), cps)
					} else {
						(model.speed_baseline, model.cycles_per_second)
					}
				}
			}
		}
		next = {
			..model,
			machine: m,
			speed_baseline: new_baseline,
			cycles_per_second: new_cps,
			pacing_baseline: Some(pacing),
		}
		advance_due!(next, target_cycles, 3)
	}
}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	Draw.clear!(frame, Color.black)

	draw = Draw.texture_draw(model.texture)
	Draw.texture!(
		frame,
		{
			..draw,
			dest: { x: 0, y: 0, width: 960, height: 640 },
		},
	)

	speed_percent = model.cycles_per_second / 16_777_216 * 100

	if model.paused {
		frame.text_at!({ pos: { x: 10, y: 10 }, text: "Paused", size: 20, color: Color.red })
	} else {
		Draw.debug_text!(
			frame,
			{
				pos: { x: 10, y: 10 },
				text: "Speed: ${speed_percent.to_str()}%",
				size: 20,
				color: Color.red,
			},
		)
	}
	match model.save_status {
		Failed(_) => Draw.debug_text!(
			frame,
			{
				pos: { x: 10, y: 40 },
				text: "Save failed; retrying...",
				size: 20,
				color: Color.red,
			},
		)
		_ => {}
	}
	if (model.closing) Draw.debug_text!(
		frame,
		{
			pos: { x: 10, y: 40 },
			text: "Saving before exit...",
			size: 20,
			color: Color.red,
		},
	)
	Ok({})
}

load_save! : Files.Dir => Try(SRAM, _)
load_save! = |dir| {
	match dir.read_bytes!("game.sav") {
		Err(NotFound) => Ok(SRAM.init())
		Err(e) => Err(e)
		Ok(save) => {
			match dir.read_bytes!("game.sav.meta") {
				Err(NotFound) => Ok(SRAM.from_save(save)?)
				Err(e) => Err(e)
				Ok(meta) => {
					ecc = decode_save_meta(meta)?
					SRAM.from_save(
						SRAM.repair_save(
							save,
							ecc,
							Bits.golay_init_corrections()?,
						)?,
					)
				}
			}
		}
	}
}

write_save! : Files.Dir,
{
	save : List(U8),
	pending_meta : List(U8),
	complete_meta : List(U8),
} => Try({}, Files.WriteError)
write_save! = |dir, cxt| {
	dir.write_bytes!("game.sav.meta", cxt.pending_meta)?
	dir.write_bytes!("game.sav", cxt.save)?
	dir.write_bytes!("game.sav.meta", cxt.complete_meta)
}

start_save! : Model, App.Input(Msg) => Try(Model, [InvalidEccLength])
start_save! = |model, input| {
	if (model.save_status == Saving) return Ok(model)
	sram = model.machine.get_sram()
	bytes = sram.get_bytes()
	saved = sram.get_saved()
	new_ecc = SRAM.gen_ecc_of_save(bytes)
	match (model.save_status, saved) {
		(Idle, Some(info)) if info.ecc == new_ecc => {
			return Ok({
				..model,
				machine: Machine.mark_sram_saved(model.machine, { ..info, time: input.time.monotonic_nanos }),
			})
		}
		_ => {}
	}
	cxt = {
		save: bytes,
		pending_meta: encode_save_meta(new_ecc, Pending)?,
		complete_meta: encode_save_meta(new_ecc, Complete)?,
	}
	Task.spawn!(
		input,
		|| SaveFinished(
			write_save!(model.save_dir, cxt)
				.map_ok(|_| { time: input.time.monotonic_nanos, ecc: new_ecc }),
		),
	)
	Ok({
		..model,
		save_status: Saving,
		last_save_attempt_ns: input.time.monotonic_nanos,
	})
}

finish_close! : Model, App.Input(Msg) => Try(Model, [InvalidEccLength, Exit(I64)])
finish_close! = |model, input| {
	match model.save_status {
		Saving => Ok(model)
		Failed(_) if !save_due(model, input.time.monotonic_nanos) => Ok(model)
		_ => {
			m = start_save!(model, input)?
			if (m.save_status == Idle) Err(Exit(0)) else Ok(m)
		}
	}
}

advance_due! : Model, U64, U8 => Try(Model, _)
advance_due! = |model, target_cycles, frames_left| {
	if frames_left == 0 or model.next_vblank > target_cycles {
		return Ok(model)
	}
	zone_run = Trace.begin!("machine.run_until")
	pending = Machine.run_until(model.machine, model.next_vblank, 50_000000)
	Trace.end!(zone_run)
	result = pending?
	advanced = { ..model, machine: result.machine }
	match result.reason {
		ReachedTarget => {
			zone_pixels = Trace.begin!("framebuffer.rgba")
			pixels = Machine.get_framebuffer(result.machine).map(rgb555_to_rgba)
			Trace.end!(zone_pixels)

			zone_upload = Trace.begin!("texture.upload")
			uploaded = Assets.update_texture!(model.texture, pixels)
			Trace.end!(zone_upload)
			uploaded?
			next = {
				..advanced,
				next_vblank: model.next_vblank + 228 * 1232,
			}
			advance_due!(next, target_cycles, frames_left - 1)
		}
		BudgetExhausted => Ok(advanced)
		Stopped => Ok(advanced)
	}
}

rgb555_to_rgba : U16 -> Color.Rgba
rgb555_to_rgba = |pixel| {
	# https://computergraphics.stackexchange.com/questions/8173/why-replicating-the-higher-bits-of-rgb565-when-converting-to-rgba8888
	# black magic
	channel5_to8 : U16 -> U8
	channel5_to8 = |v| v.shl_wrap(3).bitwise_or(v.shr_wrap(2)).to_u8_wrap()

	r = channel5_to8(pixel.bitwise_and(0b1_1111))
	g = channel5_to8(pixel.shr_wrap(5).bitwise_and(0b1_1111))
	b = channel5_to8(pixel.shr_wrap(10).bitwise_and(0b1_1111))

	Color.rgba(r, g, b, 255)
}

apply_save_message : Model, Msg -> Model
apply_save_message = |model, msg| {
	match msg {
		SaveFinished(Ok(info)) => {
			..model,
			save_status: Idle,
			machine: Machine.mark_sram_saved(model.machine, info),
		}
		SaveFinished(Err(e)) => { ..model, save_status: Failed(e) }
	}
}

encode_save_meta : List(U8), [Pending, Complete] -> Try(List(U8), [InvalidEccLength])
encode_save_meta = |ecc, state| {
	if (ecc.len() != 32769) return Err(InvalidEccLength)
	header = "BGSV".to_utf8().append(1).append(if (state == Pending) 0 else 1)
	Ok(header.concat(ecc))
}

decode_save_meta : List(U8) -> Try(
	List(U8),
	[
		InvalidMetaLength,
		InvalidMetaMagic,
		UnsupportedMetaVersion,
		InvalidMetaState,
		IncompleteSave,
		OutOfBounds,
	],
)
decode_save_meta = |meta| {
	if (meta.len() != 32775) return Err(InvalidMetaLength)
	if (meta.take_first(4) != "BGSV".to_utf8()) return Err(InvalidMetaMagic)
	if (meta.get(4)? != 1) return Err(UnsupportedMetaVersion)
	if (meta.get(5)? == 0) return Err(IncompleteSave)
	if (meta.get(5)? > 1) return Err(InvalidMetaState)
	Ok(meta.drop_first(6))
}

save_due : Model, U64 -> Bool
save_due = |model, time| {
	match model.save_status {
		Saving => False
		Failed(_) => time - model.last_save_attempt_ns >= 1_000_000_000
		Idle => match model.machine.get_sram().get_saved() {
			None => True
			Some(info) => time - info.time >= 1_000_000_000
		}
	}
}
