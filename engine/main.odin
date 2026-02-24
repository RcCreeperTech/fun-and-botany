#+feature using-stmt
package web_testing

import wgl "WebGL"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import cx "core:math/cmplx"
import la "core:math/linalg"
import "core:math/rand"

UP :: -1i
SIM_MAX_DEPTH :: 10

// QUESTION: Should these be mapped into some memory allocated by the platform.
// This could enable hot reloads for the odin code. Which would be kind of sick.
ApplicationState :: struct {
	cumulative_time:       f64,
	window_width:          i32,
	window_height:         i32,
	dpr:                   f64,
	rt_metaballs:          DebugRenderer_RenderTarget,
	rc:                    DebugRenderer_Context,
	origin:                Vec2,
	num_substeps:          int `ui:"name='Substeps',min=0,max=10"`,
	seperation_compliance: f32 `ui:"name='Seperation Compliance',min=0,max=1"`,
	elements:              ElementMap,
	root_element:          Handle,
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
	rc_initialize(&g_app_state.rc)

	g_app_state.seperation_compliance = 0.00008
	g_app_state.num_substeps = 8

	g_app_state.root_element = hm.add(
		&g_app_state.elements,
		Sim_Element {
			rest_orientation = UP,
			orientation = UP,
			thickness = 2,
			color = DARKGREEN,
			debug_state = .Bud,
			joint_compliance = SIM_BASELINE_JOINT_COMPLIANCE,
			growth_rate = SIM_BASELINE_GROWTH_RATE,
			target_length = 1,
			target_thickness = 15,
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

	g_app_state.origin = Vec2 {
		cast(f32)g_app_state.window_width * 0.5,
		cast(f32)g_app_state.window_height * 0.95,
	}

	sim_update(&g_app_state, f32(delta_time))

	// Clear the off-screen buffer to transparent (required for compositing later)
	wgl.ClearColor(0.13, 0.13, 0.13, 0)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)

	when false { 	// render the elements
		it := hm.iterator_make(&g_app_state.elements)
		for e, h in hm.iterate(&it) {
			pos := g_app_state.origin + e.position
			p1 := Vec2{real(e.orientation), imag(e.orientation)}
			debug_color: Color
			switch e.debug_state {
			case .Bud:
				debug_color = GREEN
			case .Node:
				debug_color = RED
			case .Stem:
				debug_color = YELLOW
			case .Petal:
				debug_color = PINK
			}
			debug_color = color_alpha(debug_color, 0.23)
			rc_draw_circle(&g_app_state.rc, pos, e.thickness, color = debug_color)
			rc_draw_circle(&g_app_state.rc, pos, 5, color = RED)
			rc_draw_line(&g_app_state.rc, pos, pos + p1 * e.thickness * 0.8, 2)
		}
	}

	draw_skeleton(&g_app_state, g_app_state.root_element)
	draw_skeleton :: proc(
		using sim_state: ^ApplicationState,
		h: Handle,
		prev: ^Sim_Element = nil,
	) {
		if elem, ok := hm.get(&elements, h); ok {
			rc_draw_circle(&rc, origin + elem.position, elem.thickness, color = elem.color)
			if prev != nil {
				rc_draw_wedge(
					&rc,
					origin + prev.position,
					origin + elem.position,
					prev.thickness,
					elem.thickness,
					{prev.color, prev.color, elem.color, elem.color},
				)
			}

			it := elem.first_child
			for {
				child := hm.get(&elements, it) or_break
				draw_skeleton(sim_state, child.handle, elem)
				it = child.right
			}
		}
	}

	rc_draw_rect(
		&g_app_state.rc,
		{0, g_app_state.origin.y},
		{f32(g_app_state.window_width), f32(g_app_state.window_height) * 0.05},
		DARKGREEN,
	)

	rc_flush(&g_app_state.rc)

	return true
}

@(export)
window_resize :: proc(width, height, dpr: f64) {
	g_app_state.window_width = i32(width * dpr)
	g_app_state.window_height = i32(height * dpr)
	g_app_state.dpr = dpr
	w, h := g_app_state.window_width, g_app_state.window_height
	wgl.Viewport(0, 0, w, h)
	g_app_state.rc.ortho_proj = la.matrix_ortho3d_f32(0, f32(w), f32(h), 0, -1, 1)
	fmt.println("Resized the window: ", w, h, dpr)
	rc_destroy_render_target(g_app_state.rt_metaballs) // Idempotent
	g_app_state.rt_metaballs = rc_create_render_target(&g_app_state.rc, w, h)
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
