package engine

import "core:fmt"
import "core:encoding/json"
import "../vm"
import "core:log"
import wgl "WebGL"
import "base:runtime"
import "core:math"
import la "core:math/linalg"
import rg "renderer"

ApplicationState :: struct {
	cumulative_time: f64,
	accumulator:     f32,
	window_width:    i32,
	window_height:   i32,
	dpr:             f64,
	ortho_proj:      la.Matrix4f32,
	r:               rg.Renderer_State,
	debug_rc:        DebugRenderer_Context,
	ctx:             runtime.Context,
	sim:             SimState,
}

g_app_state: ApplicationState

main :: proc() {
		context.logger = log.create_console_logger(opt = {
			.Level,
			.Terminal_Color,
			.Short_File_Path,
			.Line,
			.Procedure,
		})

	app := &g_app_state
	app.ctx = context

	if !wgl.CreateCurrentContextById(
		"gl-canvas",
		{.desynchronized, .disableAlpha, .preserveDrawingBuffer},
	) {
		log.error("Failed to create WebGL Context")
	}
	major, minor: i32
	wgl.GetWebGLVersion(&major, &minor)
	esmajor, esminor: i32
	wgl.GetESVersion(&esmajor, &esminor)
	log.info("Created graphics context: WebGL %d.%d ES %d.%d", major, minor, esmajor, esminor)

	rg.init(&app.r, context.allocator)
	rc_initialize(&app.debug_rc)

	vm.init_json_encoders()


}

@(export)
step :: proc(delta_time: f64) -> (keep_going: bool) {
	app := &g_app_state
	context = app.ctx
	free_all(context.temp_allocator)
	app.cumulative_time += delta_time
	// Reset after 1 hour (3600 seconds) to stay in high-precision range
	if app.cumulative_time > 3600 {
		app.cumulative_time = 0
	}


	center := window_center()

	frame_dt := min(f32(delta_time), 0.25) // Cap max framerate
	app.accumulator += frame_dt
	SIM_TIMESTEP :: 1.0 / 60.0
	for app.accumulator >= SIM_TIMESTEP {
		sim_update(&app.sim, SIM_TIMESTEP)
		app.accumulator -= SIM_TIMESTEP
	}

	sim_render(app, &app.sim, frame_dt)

	debug_renderer_flush(&g_app_state.debug_rc, &g_app_state.r)

	return true
}

@(export)
window_resize :: proc(css_width, css_height, dpr: f64) {
	context = g_app_state.ctx

	phys_w, phys_h := i32(css_width * dpr), i32(css_height * dpr)
	g_app_state.window_width = i32(phys_w)
	g_app_state.window_height = i32(phys_h)
	g_app_state.dpr = dpr

	g_app_state.ortho_proj = la.matrix_ortho3d_f32(0, f32(css_width), f32(css_height), 0, -1, 1)
	g_app_state.sim.camera = rg.Camera {
		zoom   = SIM_PIXELS_PER_METER,
		offset = Vec2{f32(css_width), f32(css_height)} * 0.5,
	}

	wgl.Viewport(0, 0, phys_w, phys_h)
}

window_center :: proc() -> Vec2 {
	return Vec2{cast(f32)g_app_state.window_width, cast(f32)g_app_state.window_height} * 0.5
}


@(export)
load_program_and_restart :: proc(ptr: [^]byte, len: int) {
	context = g_app_state.ctx
	app := &g_app_state
	data := ptr[:len]

	program: vm.Program
	if err := json.unmarshal(data, &program, .JSON); err != nil {
		log.error("Unable to unmarshal program", err, "\nGot data:\n", string(data))
		return
	}

	vm.dump_program(program)

	sim_destroy(&app.sim)
	sim_init(&app.sim, program)
}
