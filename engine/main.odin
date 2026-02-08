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

Handle :: hm.Handle32
ElementMap :: hm.Static_Handle_Map(4096, Simulation_Element, Handle)

// QUESTION: Should these be mapped into some memory allocated by the platform.
// This could enable hot reloads for the odin code. Which would be kind of sick.
SimulationState :: struct {
	cumulative_time: f64,
	window_width:    i32,
	window_height:   i32,
	dpr:             f64,
	rt_metaballs:    DebugRenderer_RenderTarget,
	rc:              DebugRenderer_Context,
	origin:          Vec2,
	elements:        ElementMap,
	root_element:    Handle,
}

Simulation_Element :: struct {
	handle:                  Handle,
	parent, left, right:     Handle,
	first_child, last_child: Handle,
	position:                Vec2,
	velocity:                Vec2,
	rest_orientation:        complex64,
	target_orientation:      complex64,
	orientation:             complex64,
	angular_velocity:        f32,
	color:                   Color,
	radius:                  f32,
	age:                     f32,
	debug_alive:             bool,
}
element_spawn_child :: proc(
	elements: ^ElementMap,
	e: ^Simulation_Element,
	rotation: complex64 = 1,
) {
	child := hm.add(
	elements,
	Simulation_Element {
		position           = e.position + {real(e.orientation), imag(e.orientation)} * e.radius,
		rest_orientation   = rotation,
		target_orientation = e.orientation * rotation,
		orientation        = e.orientation * rotation,
		radius             = e.radius * 0.2,
		color              = e.color,
		debug_alive        = true,
		parent             = e.handle, // point to the parent
		right              = e.first_child, // link into the head of the sibling dll
	},
	)

	if first, ok := hm.get(elements, e.first_child); ok {
		first.left = child
		e.first_child = child
	} else { 	// parent has no children
		e.first_child, e.last_child = child, child
	}
}

g_sim: SimulationState

main :: proc() {
	using g_sim
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
	rc_initialize(&rc)

	g_sim.root_element = hm.add(
		&g_sim.elements,
		Simulation_Element {
			rest_orientation = UP,
			target_orientation = UP,
			orientation = UP,
			radius = 30,
			color = color_alpha(BLUE, 0.23),
			debug_alive = true,
		},
	)
}

@(export)
step :: proc(delta_time: f64) -> (keep_going: bool) {
	g_sim.cumulative_time += delta_time
	// Reset after 1 hour (3600 seconds) to stay in high-precision range
	if g_sim.cumulative_time > 3600 {
		g_sim.cumulative_time = 0
	}

	center := window_center()
	g_sim.origin = center // + {0, center.y * 0.95}

	{ 	// Tick the elements
		// Debug code
		it := hm.iterator_make(&g_sim.elements)
		for element, h in hm.iterate(&it) {
			element.age += f32(delta_time)
			left_rotation := cx.rect_complex64(1, -math.τ / 11)
			right_rotation := cx.rect_complex64(1, math.τ / 11)
			growth := 0.6 / max(element.age, 1)
			element.radius += 0.2 * growth

			if element.debug_alive && growth <= 0.3 {
				element.debug_alive = false
				// element_spawn_child(&g_sim.elements, element, rotation = right_rotation)
				if rand.float32() < 0.88 do element_spawn_child(&g_sim.elements, element, rotation = right_rotation)
				if rand.float32() < 0.33 do element_spawn_child(&g_sim.elements, element, rotation = left_rotation)
			}
		}
	}

	{ 	// Physics Step Bodies
		it := hm.iterator_make(&g_sim.elements)
		for e, h in hm.iterate(&it) {
			e.position += e.velocity * f32(delta_time)
			// This sim is only first order so velocity is actually just an
			// accumulator for kinematic impulse
			e.velocity = 0
		}
	}

	{ 	// Seperate Physics Bodies
		it := hm.iterator_make(&g_sim.elements)
		for a, h_a in hm.iterate(&it) {
			jt := hm.iterator_make(&g_sim.elements)
			for b, h_b in hm.iterate(&jt) {
				if h_a == h_b do continue
				ab := b.position - a.position
				d2 := la.length2(ab)
				r2 := (a.radius + b.radius) * (a.radius + b.radius)
				if d2 > r2 do continue

				overlap := math.sqrt(r2 - d2)
				dir := la.normalize0(ab)
				// Drastically tone down the seperation to make the simulation
				// less rigid, allowing branches to overlap.
				seperation := dir * overlap / 100
				a.position -= seperation
				b.position += seperation
				// this is purely vibes based
				a.velocity -= seperation
				b.velocity += seperation
			}
		}
	}

	solve_joint_constraints(&g_sim, g_sim.root_element)
	solve_joint_constraints :: proc(
		using sim_state: ^SimulationState,
		h: Handle,
		prev: ^Simulation_Element = nil,
	) {
		if elem, ok := hm.get(&elements, h); ok {
			if prev != nil {
				z_target_dir := prev.orientation * elem.rest_orientation
				target_dir := Vec2{real(z_target_dir), imag(z_target_dir)}
				ideal_dist := elem.radius + prev.radius
				target_pos := prev.position + (target_dir * ideal_dist)

				age := max(1, (elem.age + prev.age) / 2)
				stiffness := clamp(age, 3, 10)

				error := target_pos - elem.position
				force := error * stiffness * 0.5

				elem.velocity += force
				prev.velocity -= force
			}

			it := elem.first_child
			for {
				child := hm.get(&elements, it) or_break
				solve_joint_constraints(sim_state, child.handle, elem)
				it = child.right
			}
		}
	}

	// Clear the off-screen buffer to transparent (required for compositing later)
	wgl.ClearColor(0.13, 0.13, 0.13, 0)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)

	{ 	// render the elements
		it := hm.iterator_make(&g_sim.elements)
		counter := 0
		for e, h in hm.iterate(&it) {
			counter += 1
			pos := g_sim.origin + e.position
			p1 := Vec2{real(e.orientation), imag(e.orientation)}
			rc_draw_circle(&g_sim.rc, pos, e.radius, color = e.color)
			rc_draw_circle(&g_sim.rc, pos, 5, color = RED)
			rc_draw_line(&g_sim.rc, pos, pos + p1 * e.radius * 0.8, 2)
		}
	}

	draw_skeleton(&g_sim, g_sim.root_element)
	draw_skeleton :: proc(
		using sim_state: ^SimulationState,
		h: Handle,
		prev: ^Simulation_Element = nil,
	) {
		if elem, ok := hm.get(&elements, h); ok {
			if prev != nil {
				rc_draw_line(&rc, origin + prev.position, origin + elem.position, 4, PINK)
			}

			it := elem.first_child
			for {
				child := hm.get(&elements, it) or_break
				draw_skeleton(sim_state, child.handle, elem)
				it = child.right
			}
		}
	}

	rc_flush(&g_sim.rc)

	return true
}

@(export)
window_resize :: proc(width, height, dpr: f64) {
	g_sim.window_width = i32(width * dpr)
	g_sim.window_height = i32(height * dpr)
	g_sim.dpr = dpr
	using g_sim
	wgl.Viewport(0, 0, window_width, window_height)
	rc.ortho_proj = la.matrix_ortho3d_f32(0, f32(window_width), f32(window_height), 0, -1, 1)
	fmt.println("Resized the window: ", window_width, window_height, dpr)
	rc_destroy_render_target(rt_metaballs) // Idempotent
	rt_metaballs = rc_create_render_target(&rc, window_width, window_height)
}

window_center :: proc() -> Vec2 {
	return Vec2{cast(f32)g_sim.window_width, cast(f32)g_sim.window_height} * 0.5
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
