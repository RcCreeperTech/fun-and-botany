#+feature using-stmt
package web_testing

import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import cx "core:math/cmplx"
import la "core:math/linalg"
import "core:math/rand"

SIM_BASELINE_JOINT_COMPLIANCE :: 0.001
SIM_BASELINE_GROWTH_RATE :: 1
SIM_END_GROWTH_RATE :: 0.1
SIM_CELL_AGING_RATE :: 3

sim_update :: proc(using app_state: ^ApplicationState, delta_time: f32) {
	// TODO: Inject resources into the root and set any global sim parameters
	sim_tick_cells(app_state, delta_time)
	sim_execute_debug_plant_test_code(app_state, delta_time)
	sim_step_physics(app_state, delta_time)
}

sim_tick_cells :: proc(using app_state: ^ApplicationState, delta_time: f32) {
	it := hm.iterator_make(&g_app_state.elements)
	for e, _ in hm.iterate(&it) do tick(e, delta_time)
	// TODO: gate growth by resource consumption
	tick :: proc(using self: ^Sim_Element, dt: f32) {
		growth_rate = exp_decay(growth_rate, SIM_END_GROWTH_RATE, SIM_CELL_AGING_RATE, dt)
		thickness = exp_decay(thickness, target_thickness, growth_rate, dt)
		length = exp_decay(length, target_length, growth_rate, dt)
		return
	}
}

sim_execute_debug_plant_test_code :: proc(using app_state: ^ApplicationState, delta_time: f32) {
	it := hm.iterator_make(&g_app_state.elements)
	for element, h in hm.iterate(&it) {

		if element.depth == SIM_MAX_DEPTH {
			element.debug_state = .Petal
		}

		switch element.debug_state {
		case .Bud:
			if element.growth_rate <= 1.5 * SIM_END_GROWTH_RATE { 	// Only try to apply next state once growth slowed down sufficiently
				if rand.float32() < 0.33 {
					element_spawn(&g_app_state.elements, element)
					element.debug_state = .Stem // should spawn do this automatically?
				} else {
					if rand.float32() < 0.95 {
						element.debug_state = .Node
					} else {
						element.debug_state = .Petal
					}
				}
			}
		case .Node:
			element.debug_state = .Bud
			if rand.float32() < 0.88 do element_spawn(&g_app_state.elements, element, -math.τ / 9)
			if rand.float32() < 0.77 do element_spawn(&g_app_state.elements, element, math.τ / 9)
			element.debug_state = .Stem
		case .Stem:
			// Terminal State
			// Todo: auxilary growth
			element_dye(element, BROWN, 0.1)
			element.target_length += 0.001
			element.target_thickness += 0.005
		case .Petal:
			// Terminal state
			element_dye(element, PINK)
		}
	}
}

// Run physics substeps for the simulated world
sim_step_physics :: proc(using app_state: ^ApplicationState, delta_time: f32) {
	dt: f32 = delta_time / f32(num_substeps)
	for _ in 0 ..< num_substeps {
		sim_integrate_bodies(&elements, dt)
		sim_solve_joint_constraints(&elements, root_element, dt)
		sim_solve_ground_constraint(app_state)
		sim_update_body_velocities(&elements, dt)
		sim_seperate_bodies_relaxed(app_state, dt)
	}

	sim_integrate_bodies :: proc(elements: ^ElementMap, dt: f32) {
		it := hm.iterator_make(elements)
		for e, h in hm.iterate(&it) {
			if e.inv_mass == 0 do continue
			// e.velocity.y += 9.81 / e.inv_mass
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

	sim_solve_ground_constraint :: proc(using sim_state: ^ApplicationState) {
		it := hm.iterator_make(&elements)
		for e, h in hm.iterate(&it) {
			if h == root_element do continue

			error := e.position.y + e.thickness
			if error <= 0 do continue

			e.position -= {0, error}
		}
	}

	sim_solve_joint_constraints :: proc(
		elements: ^ElementMap,
		h: Handle,
		dt: f32,
		prev: ^Sim_Element = nil,
	) {
		self, ok := hm.get(elements, h)
		if !ok do return

		if prev != nil {
			// Compute the target position for the element based on the orientation and distance constraints
			z_target_dir := prev.orientation * self.rest_orientation
			target_dir := Vec2{real(z_target_dir), imag(z_target_dir)}
			ideal_dist := (self.thickness + prev.thickness)
			// ok so here is what i want to do. delete the component of this
			// that handles distance based seperation and then make that a
			// seperate compliance factor that can be controlled seperately
			// from the orientation of the child limbs. The orientation
			// should still be a position based resolution so the math
			// should not get too complicated. But then if the sim ever
			// needs to handle torque that is isolated to this part of the
			// engine. What I want this to do is use the target dir and then
			// calc the current dist of the elem to the prev. Do not modify
			// that distance in this constraint only constrain the
			// orientation of the child.
			target_pos := prev.position + (target_dir * ideal_dist)
			compliance := prev.joint_compliance

			// NOTE: Masses cancel because the parent is unaffected by this constraint
			error := la.distance(target_pos, self.position)
			alpha := compliance / (dt * dt)
			lambda := error / alpha
			dir := la.normalize0(self.position - target_pos)
			self.position -= lambda * dir
		}

		it := self.first_child
		for {
			child := hm.get(elements, it) or_break
			sim_solve_joint_constraints(elements, child.handle, dt, self)
			it = child.right
		}
	}
	sim_seperate_bodies_relaxed :: proc(using sim_state: ^ApplicationState, dt: f32) {
		it := hm.iterator_make(&elements)
		for a, h_a in hm.iterate(&it) {
			jt := hm.iterator_make(&elements)
			for b, h_b in hm.iterate(&jt) {
				if h_a == h_b do continue
				ab := b.position - a.position
				d2 := la.length2(ab)
				r2 := (a.thickness + b.thickness) * (a.thickness + b.thickness)
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
}


Handle :: hm.Handle32
ElementMap :: hm.Static_Handle_Map(1024, Sim_Element, Handle)
Sim_Debug_GrowthState :: enum {
	Stem,
	Bud,
	Node,
	Petal,
}
Sim_Element :: struct {
	// Connnection Info
	handle:                  Handle,
	parent, left, right:     Handle,
	first_child, last_child: Handle,
	// Physics State
	old_position:            Vec2,
	position:                Vec2,
	velocity:                Vec2,
	rest_orientation:        complex64, // TODO: remove
	orientation:             complex64, // TODO: remove
	old_angle:               f32,
	angle:                   f32,
	angular_velocity:        f32,
	inv_mass:                f32,
	// Other Data
	thickness:               f32,
	length:                  f32,
	target_thickness:        f32,
	target_length:           f32,
	joint_compliance:        f32,
	growth_rate:             f32,
	color:                   Color,
	depth:                   u8,
	debug_state:             Sim_Debug_GrowthState, // TODO: Elements will be state machines with finite memory
}

element_spawn :: proc(elements: ^ElementMap, e: ^Sim_Element, theta: f32 = 0, mass: f32 = 1) {
	rotation := cx.rect_complex64(1, theta)

	child := hm.add(
	elements,
	Sim_Element {
		parent           = e.handle, // point to the parent
		right            = e.first_child, // link into the head of the sibling dll
		position         = e.position + {real(e.orientation), imag(e.orientation)} * e.thickness * 0.5,
		rest_orientation = rotation,
		orientation      = e.orientation * rotation,
		inv_mass         = 1 / mass if mass != 0 else 0,
		joint_compliance = SIM_BASELINE_JOINT_COMPLIANCE,
		growth_rate      = SIM_BASELINE_GROWTH_RATE,
		depth            = e.depth + 1,
		color            = e.color,
		debug_state      = e.debug_state,
		target_thickness = e.target_thickness * 0.8,
		target_length    = e.target_length * 0.8,
	},
	)

	if first, ok := hm.get(elements, e.first_child); ok {
		first.left = child
		e.first_child = child
	} else { 	// parent has no children
		e.first_child, e.last_child = child, child
	}
}

element_strengthen :: proc(
	using self: ^Sim_Element,
	app_state: ^ApplicationState,
	amount: f32,
	set_immovable := false,
) {
	unimplemented("TODO: joint strengthening")
}
element_dye :: proc(using self: ^Sim_Element, target: Color, t: f32 = 0.5) {
	t := clamp(t, 0, 1)
	a, b := to_fcolor(self.color), to_fcolor(target)
	new_color := la.lerp(a, b, t)
	self.color = to_color(new_color)
}

// Lerp that respects delta time
// Useful range approx. 1 to 25, from slow to fast
exp_decay :: proc(a, b: $T, decay, dt: f32) -> T {
	return b + (a - b) * math.exp(-decay * dt)
}
