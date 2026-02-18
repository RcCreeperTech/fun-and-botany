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

Handle :: hm.Handle32
ElementMap :: hm.Static_Handle_Map(1024, Simulation_Element, Handle)

// QUESTION: Should these be mapped into some memory allocated by the platform.
// This could enable hot reloads for the odin code. Which would be kind of sick.
SimulationState :: struct {
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

Simulation_Element :: struct {
	handle:                  Handle,
	parent, left, right:     Handle,
	first_child, last_child: Handle,
	old_position:            Vec2,
	position:                Vec2,
	velocity:                Vec2,
	rest_orientation:        complex64,
	target_orientation:      complex64,
	orientation:             complex64,
	angular_velocity:        f32,
	inv_mass:                f32,
	magic_soup_of_life:      f32,
	color:                   Color,
	radius:                  f32,
	age:                     f32,
	depth:                   u8,
	debug_alive:             bool,
}
element_spawn_child :: proc(
	elements: ^ElementMap,
	e: ^Simulation_Element,
	rotation: complex64 = 1,
	mass: f32 = 1,
) {
	child := hm.add(
	elements,
	Simulation_Element {
		position           = e.position + {real(e.orientation), imag(e.orientation)} * e.radius * 0.5,
		rest_orientation   = rotation,
		target_orientation = e.orientation * rotation,
		orientation        = e.orientation * rotation,
		radius             = 0,
		depth              = e.depth + 1,
		color              = e.color,
		debug_alive        = true,
		parent             = e.handle, // point to the parent
		right              = e.first_child, // link into the head of the sibling dll
		inv_mass           = 1 / mass if mass != 0 else 0,
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

	g_sim.seperation_compliance = 0.0001
	g_sim.num_substeps = 8

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

	g_sim.origin = Vec2{cast(f32)g_sim.window_width * 0.5, cast(f32)g_sim.window_height * 0.95}

	debug_plant_test_code: {
		it := hm.iterator_make(&g_sim.elements)
		for element, h in hm.iterate(&it) {
			element.age += f32(delta_time)
			left_rotation := cx.rect_complex64(1, -math.τ / 9)
			right_rotation := cx.rect_complex64(1, math.τ / 9)
			growth := 0.6 / max(element.age, 1)
			// growth := max(math.exp(-element.age), 0.01)
			element.radius += 0.2 * growth

			if element.debug_alive && growth <= 0.3 && element.depth < SIM_MAX_DEPTH {
				element.debug_alive = false
				if rand.float32() < 0.33 {
					element_spawn_child(&g_sim.elements, element)
				} else {
					if rand.float32() < 0.88 do element_spawn_child(&g_sim.elements, element, rotation = right_rotation)
					if rand.float32() < 0.77 do element_spawn_child(&g_sim.elements, element, rotation = left_rotation)
				}
			}
		}
	}

	dt: f32 = f32(delta_time) / f32(g_sim.num_substeps)
	for _ in 0 ..< g_sim.num_substeps {
		sim_integrate_bodies(&g_sim.elements, dt)
		sim_solve_joint_constraints(&g_sim.elements, g_sim.root_element, dt)
		sim_solve_ground_constraint(&g_sim)
		sim_update_body_velocities(&g_sim.elements, dt)
		sim_seperate_bodies_relaxed(&g_sim, dt)
	}

	sim_integrate_bodies :: proc(elements: ^ElementMap, dt: f32) {
		it := hm.iterator_make(elements)
		for e, h in hm.iterate(&it) {
			// TODO: impulse would apply here e.g. Gravity
			e.old_position = e.position
			e.position += e.velocity * dt
		}
	}

	sim_update_body_velocities :: proc(elements: ^ElementMap, dt: f32) {
		it := hm.iterator_make(elements)
		for e, h in hm.iterate(&it) {
			e.velocity = (e.position - e.old_position) / dt
			e.velocity *= 0.9
		}
	}

	sim_solve_ground_constraint :: proc(using sim_state: ^SimulationState) {
		it := hm.iterator_make(&elements)
		for e, h in hm.iterate(&it) {
			if h == root_element do continue

			error := e.position.y + e.radius
			if error <= 0 do continue

			e.position -= {0, error}
		}
	}

	sim_solve_joint_constraints :: proc(
		elements: ^ElementMap,
		h: Handle,
		dt: f32,
		prev: ^Simulation_Element = nil,
	) {
		if elem, ok := hm.get(elements, h); ok {
			if prev != nil {
				// Compute the target position for the element based on the orientation and distance constraints
				z_target_dir := prev.orientation * elem.rest_orientation
				target_dir := Vec2{real(z_target_dir), imag(z_target_dir)}
				ideal_dist := (elem.radius + prev.radius)
				target_pos := prev.position + (target_dir * ideal_dist)

				age := max(1, (elem.age + prev.age) / 2)
				stiffness := clamp(age, 300, 800)
				compliance := 1 / stiffness // TODO: Do this better here

				// NOTE: Masses cancel because the parent is unaffected by this constraint
				error := la.distance(target_pos, elem.position)
				alpha := compliance / (dt * dt)
				lambda := error / alpha
				dir := la.normalize0(elem.position - target_pos)
				elem.position -= lambda * dir
			}

			it := elem.first_child
			for {
				child := hm.get(elements, it) or_break
				sim_solve_joint_constraints(elements, child.handle, dt, elem)
				it = child.right
			}
		}
	}
	sim_seperate_bodies_relaxed :: proc(using sim_state: ^SimulationState, dt: f32) {
		it := hm.iterator_make(&elements)
		for a, h_a in hm.iterate(&it) {
			jt := hm.iterator_make(&elements)
			for b, h_b in hm.iterate(&jt) {
				if h_a == h_b do continue
				ab := b.position - a.position
				d2 := la.length2(ab)
				r2 := (a.radius + b.radius) * (a.radius + b.radius)
				if d2 > r2 do continue

				error := math.sqrt(r2 - d2)
				alpha := seperation_compliance / (dt * dt)
				lambda := error / (a.inv_mass + b.inv_mass + alpha)
				dir := la.normalize0(ab)
				a.velocity -= lambda * a.inv_mass * dir
				b.velocity += lambda * b.inv_mass * dir
			}
		}
	}

	// Clear the off-screen buffer to transparent (required for compositing later)
	wgl.ClearColor(0.13, 0.13, 0.13, 0)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)

	{ 	// render the elements
		it := hm.iterator_make(&g_sim.elements)
		for e, h in hm.iterate(&it) {
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
				rc_draw_line(
					&rc,
					origin + prev.position,
					origin + elem.position,
					2 * f32(SIM_MAX_DEPTH - prev.depth),
					PINK,
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
		&g_sim.rc,
		{0, g_sim.origin.y},
		{f32(g_sim.window_width), f32(g_sim.window_height) * 0.05},
		GREEN,
	)

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
