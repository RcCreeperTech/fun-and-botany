#+feature using-stmt
package web_testing

import "core:log"
import wgl "WebGL"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import la "core:math/linalg"
import rg "renderer"

SIM_MAX_DEPTH :: 10

// QUESTION: Should these be mapped into some memory allocated by the platform.
// This could enable hot reloads for the odin code. Which would be kind of sick.
ApplicationState :: struct {
	cumulative_time:       f64,
	window_width:          i32,
	window_height:         i32,
	dpr:                   f64,
	ortho_proj: la.Matrix4f32,
	r:                   rg.Renderer_State,
	num_substeps:          int `ui:"name='Substeps',min=0,max=10"`,
	seperation_compliance: f32 `ui:"name='Seperation Compliance',min=0,max=1"`,
	elements:              ElementMap,
	root_element:          Handle,
	camera:                rg.Camera,
	debug_rc: DebugRenderer_Context,
}

// TODO: @(private="file")
g_app_state: ApplicationState

main :: proc() {
	if !wgl.CreateCurrentContextById(
		"gl-canvas",
		{.desynchronized, .disableAlpha, .preserveDrawingBuffer},
	) {
		fmt.eprintln("Failed to create WebGL Context")
	}
	major, minor: i32
	wgl.GetWebGLVersion(&major, &minor)
	esmajor, esminor: i32
	wgl.GetESVersion(&esmajor, &esminor)
	fmt.printfln("Created graphics context: WebGL %d.%d ES %d.%d", major, minor, esmajor, esminor)

	rg.init(&g_app_state.r, context.allocator)
	rc_initialize(&g_app_state.debug_rc)

	g_app_state.camera = rg.Camera {
		zoom = 0.5,
	}

	g_app_state.seperation_compliance = 0.00008
	g_app_state.num_substeps = 8

	g_app_state.root_element = hm.add(
		&g_app_state.elements,
		Sim_Element {
			position = {0, 1},
			rest_angle = math.TAU / 4,
			color = DARKGREEN,
			target_color = DARKGREEN,
			debug_state = .Bud,
			joint_compliance = SIM_BASELINE_JOINT_COMPLIANCE,
			growth_rate = SIM_BASELINE_GROWTH_RATE,
			target_length = 80,
			target_thickness = 40,
		},
	)
}

@(export)
step :: proc(delta_time: f64) -> (keep_going: bool) {
	g_app_state.cumulative_time += delta_time
	// Reset after 1 hour (3600 seconds) to stay in high-precision range
	if g_app_state.cumulative_time > 3600 {
		g_app_state.cumulative_time = 0
	}

	center := window_center()

	sim_update(&g_app_state, f32(delta_time))
	sim_render(&g_app_state, f32(delta_time))

	debug_renderer_flush(&g_app_state.debug_rc, &g_app_state.r)

	return true
}

@(export)
window_resize :: proc(width, height, dpr: f64) {
	g_app_state.window_width = i32(width * dpr)
	g_app_state.window_height = i32(height * dpr)
	g_app_state.dpr = dpr
	w, h := g_app_state.window_width, g_app_state.window_height
	g_app_state.camera = rg.Camera {
		zoom   = 1,
		offset = Vec2{f32(w), f32(h)} * 0.5,
	}
	wgl.Viewport(0, 0, w, h)
	g_app_state.ortho_proj = la.matrix_ortho3d_f32(0, f32(w), f32(h), 0, -1, 1)
	fmt.println("Resized the window: ", w, h, dpr)
}

window_center :: proc() -> Vec2 {
	return Vec2{cast(f32)g_app_state.window_width, cast(f32)g_app_state.window_height} * 0.5
}

cmplx_length2 :: proc(z: complex64) -> f32 {
	return real(z) * real(z) + imag(z) * imag(z)
}
cmplx_normalize :: proc(z: complex64) -> complex64 {
	l2 := cmplx_length2(z)
	if l2 <= 0 do return z
	inv_len := 1 / math.sqrt(l2)
	return complex(real(z) * inv_len, imag(z) * inv_len)
}
