app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.12.0/79nt7eRxopFeMc2RcTHhPmjDxdRZjpNWLa9Na5xVGw9p.tar.zst" }

import rr.App
import rr.Color
import rr.Draw
import rr.Texture
import rr.Assets
import rr.Trace

import src/Machine
import src/Cpu

Model : {
	machine : Machine,
	texture : Texture,
	next_vblank : U64,
	speed_baseline : [None, Some({ host_ns : U64, gba_cycles : U64 })],
	pacing_baseline : [None, Some({ host_ns : U64, gba_cycles : U64 })],
	cycles_per_second : F64,
}

Msg : []

program = { init!, update!, render! }

init! : App.Init(Model, _)
init! = App.init(
	App.default
		.with_title("birbGBA")
		.with_size({ width: 720, height: 480 })
		.with_frame_pacing(Capped(240))
		.with_permission(WorkingDirectory(ReadOnly)),
	|io| {
		dir = io.files().working_directory_read!()?
		bios = dir.read_bytes!("bios.bin")?
		rom = dir.read_bytes!("game.gba")?
		machine = Machine.init(bios, rom)?

		texture = Assets.generate_color_texture!({
			width: 240,
			height: 160,
			color: Color.black,
		})?
		Assets.set_texture_filter!(texture, Point)

		Ok({ machine, texture, next_vblank: 160 * 1232, speed_baseline: None, pacing_baseline: None, cycles_per_second: 0 })
	},
)

update! : Model, App.Input(Msg), App.Io => Try(Model, _)
update! = |model, input, _io| {
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

	pressed = 0.U16 # Yes no pressing for now.
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

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
	Draw.clear!(frame, Color.black)

	draw = Draw.texture_draw(model.texture)
	Draw.texture!(
		frame,
		{
			..draw,
			dest: { x: 0, y: 0, width: 720, height: 480 },
		},
	)

	speed_percent = model.cycles_per_second / 16_777_216 * 100

	Draw.debug_text!(
		frame,
		{
			pos: { x: 10, y: 10 },
			text: "Speed: ${speed_percent.to_str()}%",
			size: 20,
			color: Color.red,
		},
	)

	Ok({})
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
