app [Model, program] { rr: platform "https://github.com/lukewilliamboswell/roc-ray/releases/download/0.11.1/4NWnSt7bKCyVx4xDFH89pV11ekYbiGQ43kdjfZ9NBJQn.tar.zst" }

import rr.App
import rr.Color
import rr.Draw
import rr.Texture
import rr.Assets

import src/Machine
import src/Cpu


Model : {
    machine : Machine,
    texture : Texture,
    next_vblank : U64,
}

Msg : []

program = { init!, update!, render! }

init! : App.Init(Model, _)
init! = App.init(
    App.default
        .with_title("birbGBA")
        .with_size({ width: 720, height: 480 })
        .with_frame_pacing(Capped(60))
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

        Ok({ machine, texture, next_vblank: 160 * 1232 })
    }
)

update! : Model, App.Input(Msg), App.Io => Try(Model, _)
update! = |model, _input, _io| {
    pressed = 0.U16 # Yes no pressing for now.
    m = Machine.set_pressed(model.machine, pressed)
    result = Machine.run_until(m, model.next_vblank, 50_000000)?
    next = { ..model, machine: result.machine }
    match result.reason {
        ReachedTarget => {
            pixels = Machine.get_framebuffer(result.machine).map(rgb555_to_rgba)
            Assets.update_texture!(model.texture, pixels)?

            Ok({
                ..next,
                next_vblank: model.next_vblank + 228 * 1232,
            })
        }
        BudgetExhausted => Ok(next)
        Stopped => Ok(next)
    }

}

render! : Model, Draw.Frame => Try({}, [Exit(I64)])
render! = |model, frame| {
    Draw.clear!(frame, Color.black)

    draw = Draw.texture_draw(model.texture)
    Draw.texture!(frame, {
        ..draw,
        dest: { x: 0, y: 0, width: 720, height: 480 },
    })

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