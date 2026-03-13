#+feature using-stmt
package web_testing

import hm "core:container/handle_map"
import "core:math"
import la "core:math/linalg"
import "core:math/rand"
import rg "renderer"

SIM_DEBUG_RENDERING :: false
SIM_BASELINE_JOINT_COMPLIANCE :: 0.000001
SIM_DYE_RATE :: 1.7 // TODO: Per cell
SIM_BASELINE_GROWTH_RATE :: 0.5
SIM_END_GROWTH_RATE :: 0.01
SIM_CELL_AGING_RATE :: 0.7
SIM_PIXELS_PER_METER :: 100

E_WOOD :: f32(2_000_000) // 2 GPa in Pa
E_STEM :: f32(300_000) // 300 MPa
E_LEAF :: f32(50_000) // 50 MPa
E_PETAL :: f32(5_000) // 5 MPa

WOOD_DENSITY :: .80 // Kg/M^2
LEAF_DENSITY :: 600 // Kg/M^2
PETAL_DENSITY :: 200 // Kg/M^2

Matrix3 :: la.Matrix3x3f32
Vec2 :: [2]f32
Vec3 :: [3]f32

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
		ftarget := to_fcolor(target_color)
		fcolor := to_fcolor(color)
		for i in 0 ..< 4 {
			color[i] = u8(exp_decay(fcolor[i], ftarget[i], SIM_DYE_RATE, dt) * 255)
		}
		return
	}
}

// Run physics substeps for the simulated world
sim_step_physics :: proc(using app_state: ^ApplicationState, delta_time: f32) {
	dt: f32 = delta_time / f32(num_substeps)
	for _ in 0 ..< num_substeps {
		sim_integrate_bodies(&elements, dt)
		sim_solve_branch_constraints(&elements, root_element, dt)
		sim_solve_ground_constraint(app_state)
		sim_update_body_velocities(&elements, dt)
	}

	sim_integrate_bodies :: proc(elements: ^ElementMap, dt: f32) {
		it := hm.iterator_make(elements)
		for e, h in hm.iterate(&it) {
			if e.inv_mass == 0 do continue

			e.velocity.y -= 9.81 * dt
			e.old_position = e.position
			e.position += e.velocity * dt
		}
	}

	sim_update_body_velocities :: proc(elements: ^ElementMap, dt: f32) {
		it := hm.iterator_make(elements)
		damping_per_frame :: 0.85
		damping_per_substep := math.pow(damping_per_frame, 1.0 / f32(g_app_state.num_substeps)) // FIXME!!!!!!!!!!!!!!
		for e, h in hm.iterate(&it) {
			e.velocity = (e.position - e.old_position) / dt
			e.velocity *= damping_per_substep
		}
	}

	sim_solve_ground_constraint :: proc(using sim_state: ^ApplicationState) {
		it := hm.iterator_make(&elements)
		for e, h in hm.iterate(&it) {
			if h == root_element do continue

			error := e.position.y - e.thickness // negative = below ground
			if error >= 0 do continue
			e.position.y -= error // push up to y = thickness
		}
	}

	sim_back_propagate_ground_forces :: proc(elements: ^ElementMap, h: Handle) {
		e, ok := hm.get(elements, h)
		if !ok do return

		// Leaves first, then propagate upward on the way back
		it := e.first_child
		for {
			child := hm.get(elements, it) or_break
			sim_back_propagate_ground_forces(elements, child.handle)
			it = child.right
		}

		parent, ok2 := hm.get(elements, e.parent)
		if !ok2 || parent.inv_mass == 0 do return // don't move pinned root

		base_to_tip := e.position - parent.position
		current_length := la.length(base_to_tip)
		if current_length == 0 do return

		dir := base_to_tip / current_length
		error := e.length - current_length

		// Move parent only — rigid, no compliance needed here
		parent.position -= dir * error
	}

	sim_solve_branch_constraints :: proc(
		elements: ^ElementMap,
		h: Handle,
		dt: f32,
		parent: ^Sim_Element = nil,
		parent_angle: f32 = 0,
	) {
		self, ok := hm.get(elements, h)
		if !ok do return

		parent_position: Vec2 = 0 if parent == nil else parent.position
		parent_angle: f32 = math.τ / 4 if parent == nil else parent_angle

		target_angle := parent_angle + self.rest_angle
		s, c := math.sincos(target_angle)
		target_pos := parent_position + Vec2{c, s} * self.length

		correction := target_pos - self.position
		alpha := self.joint_compliance / (dt * dt)
		lambda := 1.0 / (self.inv_mass + alpha) // parent is anchor, inv_mass = 0
		self.position += correction * lambda * self.inv_mass

		base_to_tip := self.position - parent_position
		final_angle := math.atan2(base_to_tip.y, base_to_tip.x)

		it := self.first_child
		for {
			child := hm.get(elements, it) or_break
			sim_solve_branch_constraints(elements, child.handle, dt, self, final_angle)
			it = child.right
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
	rest_angle:              f32, // Relative to the parent's angle
	inv_mass:      f32,
	joint_compliance:        f32,
	length:                  f32,
	thickness:               f32,
	density: 				 f32,
	// Growth Parameters
	target_thickness:        f32,
	target_length:           f32,
	target_color:            Color,
	growth_rate:             f32,
	color:                   Color,
	// Other Data
	depth:                   u8,
	debug_state:             Sim_Debug_GrowthState, // TODO: Elements will be state machines with finite memory
}

element_spawn :: proc(elements: ^ElementMap, e: ^Sim_Element, theta: f32 = 0, mass: f32 = 1) {
	child := hm.add(
	elements,
	Sim_Element {
		parent           = e.handle, // point to the parent
		right            = e.first_child, // link into the head of the sibling dll
		position         = e.position,
		rest_angle       = theta,
		inv_mass         = 1 / mass if mass != 0 else 0,
		joint_compliance = SIM_BASELINE_JOINT_COMPLIANCE,
		growth_rate      = SIM_BASELINE_GROWTH_RATE,
		depth            = e.depth + 1,
		color            = e.color,
		target_color     = e.target_color,
		debug_state      = e.debug_state,
		target_thickness = e.target_thickness * 0.8,
		target_length    = e.target_length * 0.95,
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
element_dye :: proc(using self: ^Sim_Element, target: Color) {
	self.target_color = target
}


sim_execute_debug_plant_test_code :: proc(using app_state: ^ApplicationState, delta_time: f32) {
	it := hm.iterator_make(&g_app_state.elements)
	for element, h in hm.iterate(&it) {

		if element.depth == SIM_MAX_DEPTH {
			element.debug_state = .Petal
		}

		switch element.debug_state {
		case .Bud:
			if element.growth_rate <= SIM_END_GROWTH_RATE * 5 { 	// Only try to apply next state once growth slowed down sufficiently
				element.debug_state = .Node
			}
		case .Node:
			element.debug_state = .Bud
			element_spawn(&g_app_state.elements, element, -math.τ / 9)
			element_spawn(&g_app_state.elements, element, math.τ / 9)
			element.debug_state = .Stem
		case .Stem:
			// Terminal State
			// Todo: auxilary growth
			element_dye(element, BROWN)
			element.target_length += 0.00001
			element.target_thickness += 0.00005
		case .Petal:
			// Terminal state
			element_dye(element, PINK)
		}
	}
}

// Lerp that respects delta time
// Useful range approx. 1 to 25, from slow to fast
exp_decay :: proc(a, b: $T, decay, dt: f32) -> T {
	return b + (a - b) * math.exp(-decay * dt)
}

sim_render :: proc(using app_state: ^ApplicationState, dt: f32) {
	{
		lo, hi: Vec2 = math.INF_F32, -math.INF_F32
		it := hm.iterator_make(&elements)
		for e, _ in hm.iterate(&it) {
			lo.x = min(e.position.x, lo.x)
			lo.y = min(e.position.y, lo.y)
			hi.x = max(e.position.x, hi.x)
			hi.y = max(e.position.y, hi.y)
		}
		camera_target := (hi + lo) / 2
		camera.target = exp_decay(camera.target, camera_target, 5, dt)
	}
	rg.frame_begin(&r)

	rg.pass_begin(&r, {clear = true, color = BG_COLOR}, rg.Pipeline_Basic{projection = ortho_proj})
	if rg.camera_mode(&r, camera) {
		draw_plant(app_state, root_element)
		// TODO: add back the ground and calculate its world space
		// rc_draw_rect(
		// 	&rc,
		// 	{0, origin.y},
		// 	{f32(window_width), f32(window_height) * 0.05},
		// 	DARKGREEN,
		// )
	}
	rg.pass_end(&r)

	rg.frame_end(&r)


	draw_plant :: proc(using sim_state: ^ApplicationState, h: Handle, prev: ^Sim_Element = nil) {
		if e, ok := hm.get(&elements, h); ok {
			rg.draw_circle(&r, e.position, e.thickness, color = e.color)
			prev := prev
			// Inject a dummy prev for the origin segment
			if prev == nil {
				dummy := Sim_Element {
					thickness = e.thickness * 1.2,
					color     = e.color,
				}
				prev = &dummy
			}
			rg.draw_wedge(
				&r,
				prev.position,
				e.position,
				prev.thickness,
				e.thickness,
				{prev.color, prev.color, e.color, e.color},
			)

			when SIM_DEBUG_RENDERING {
				rc_draw_circle(&rc, prev.position, 5, color = RED)
				rc_draw_circle(&rc, e.position, 8, color = GREEN)
			}

			it := e.first_child
			for {
				child := hm.get(&elements, it) or_break
				draw_plant(sim_state, child.handle, e)
				it = child.right
			}
		}
	}

}
