#+feature using-stmt
package web_testing

import wgl "WebGL"
import "core:math"

test_renderer_metaball_example :: proc(using app_state: ^SimulationState, center: Vec2) {
	a := center + {-200, -200}
	b := center + {-200, 200}

	c := center + {200, -200}
	d := center + {200, 200}

	rc_set_render_target(&rc, rt_metaballs)
	rc_set_mode(&rc, .soft)
	// Clear the off-screen buffer to transparent (required for compositing later)
	wgl.ClearColor(0, 0, 0, 0)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)

	rc_draw_soft_circle(&rc, center, 100)

	rc_draw_soft_capsule(&rc, a, b, 50)
	rc_draw_soft_rhombus(&rc, c, d, 50, 25)

	rc_set_render_target(&rc)
	rc_set_mode(&rc, .basic)

	rc_set_current_texture(&rc, rt_metaballs.tex)
	// wgl.UseProgram(rc.soft_composite_shader)
	rc_draw_rect(&rc, {0, cast(f32)window_height}, {f32(window_width), f32(-window_height)})
	// rc_flush(&rc) // gotta think more about this...
	// wgl.UseProgram(rc.basic_shader)
	rc_set_current_texture(&rc) // unset it

	rc_draw_circle(&rc, center, 100, color = BLUE)

	rc_draw_line(&rc, a, b, 50, BLUE)
	rc_draw_line(&rc, c, d, 50, BLUE)

	rc_flush(&rc)
}


test_renderer_layer_compositing :: proc(using app_state: ^SimulationState) {
	// Explicitly set the target to our off-screen buffer.
	// This automatically flushes any pending draw calls for the previous target.
	rc_set_render_target(&rc, rt_metaballs)

	// Clear the off-screen buffer to transparent (required for compositing later)
	wgl.ClearColor(0, 0, 0, 0)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)

	rc_set_mode(&rc, .basic)
	center := Vec2{cast(f32)window_width, cast(f32)window_height} * 0.5
	test_organic_tree(&rc, center, -math.TAU / 4, 150, 18, 6)

	// Switch back to the default "Screen" framebuffer (pass nil)
	rc_set_render_target(&rc, nil)

	rc_set_mode(&rc, .basic)
	test_draw_a_silly_pinwheel(app_state)

	rc_set_current_texture(&rc, rt_metaballs.tex)
	rc_draw_rect(&rc, {0, cast(f32)window_height}, {f32(window_width), f32(-window_height)})
	rc_set_current_texture(&rc) // unset it

	// Final flush to ensure everything is sent to the GPU
	rc_flush(&rc)
}

test_draw_a_silly_pinwheel :: proc(using app_state: ^SimulationState) {
	wgl.ClearColor(0.9, 0.6, 0.7, 1.0)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)

	center := Vec2{cast(f32)window_width, cast(f32)window_height} * 0.5
	bar_len: f32 = 100
	BARS :: 14
	phase_shift := math.TAU / BARS
	endpoints := make([dynamic]Vec2)
	for i in 0 ..< BARS {
		theta: f64 = cumulative_time + phase_shift * f64(i)
		p := Vec2{cast(f32)math.cos(theta), cast(f32)math.sin(theta)}
		p *= bar_len
		append(&endpoints, p)
	}

	for point in endpoints {
		rc_draw_line(&rc, center, center + point)
		rc_draw_circle(&rc, center + point, 15, color = YELLOW)
	}
	rc_flush(&rc)
}

test_organic_tree :: proc(
	ctx: ^DebugRenderer_Context,
	start: Vec2,
	angle: f32,
	length: f32,
	width: f32,
	depth: i32,
) {
	if depth <= 0 do return

	// Calculate end point
	end := start + Vec2{math.cos(angle), math.sin(angle)} * length

	// Use the Rhombus for tapered branches!
	tip_width := width * 0.7
	rc_draw_line(ctx, start, end, width)
	// draw_soft_rhombus(ctx, start, end, width, tip_width, {0.4, 0.2, 0.1, 1.0})

	// Recursive branches
	test_organic_tree(ctx, end, angle + 0.4, length * 0.8, tip_width, depth - 1)
	test_organic_tree(ctx, end, angle - 0.4, length * 0.8, tip_width, depth - 1)

	// Add a "Leaf" at the end
	if depth == 1 {
		// rc_draw_soft_circle(ctx, end, 15.0, {0.2, 0.8, 0.3, 1.0})
		rc_draw_circle(ctx, end, 15.0)
	}
}
