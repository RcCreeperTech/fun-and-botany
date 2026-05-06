package engine

import "../vm"
import hm "core:container/handle_map"
import "core:log"
import "core:math"
import la "core:math/linalg"
import rg "renderer"
import b2 "vendor:box2d"

BOX2D_DEBUG_DRAW :: false
SIM_GROUND_THICKNESS :: 200
SIM_MAX_DEPTH :: 8
SIM_DEBUG_RENDERING :: false
SIM_DYE_RATE :: 1.7 // TODO: Per cell
SIM_BASELINE_GROWTH_RATE :: 0.5
SIM_END_GROWTH_RATE :: 0.01
SIM_CELL_AGING_RATE :: 0.7
SIM_PIXELS_PER_METER :: 100
SIM_GRAVITY :: 1.6

TissueMaterial :: struct {
	density, freq, damping: f32,
}
WOOD_TISSUE :: TissueMaterial{7, 20, 1}
STEM_TISSUE :: TissueMaterial{0.9, 10, 1}
LEAF_TISSUE :: TissueMaterial{0.8, 5, 1}
PETAL_TISSUE :: TissueMaterial{0.1, 5, 1}

Handle :: hm.Handle32
ElementMap :: hm.Static_Handle_Map(1024, Sim_Element, Handle)
Collision_Categories :: enum u64 {
	Ground  = 0x00000001,
	Element = 0x00000002,
}

SimState :: struct {
	ready:                    bool,
	elements:                 ElementMap,
	root_element:             Handle,
	physics_world:            b2.WorldId,
	physics_world_debug_draw: b2.DebugDraw,
	ground:                   b2.BodyId,
	_vm:                      vm.VM,
	program:                  vm.Program,
	camera:                   rg.Camera,
	particles:                Particle_System,
}

sim_init :: proc(self: ^SimState, program: vm.Program) {
	particle_system_init(&self.particles)

	{ 	// Create the physics world
		world_def := b2.DefaultWorldDef()
		world_def.gravity = {0, -SIM_GRAVITY}
		world_def.enableSleep = false
		world_def.enableContinuous = false
		self.physics_world = b2.CreateWorld(world_def)
	}

	{ 	// Create the ground
		box := b2.MakeBox(SIM_GROUND_THICKNESS / 2, SIM_GROUND_THICKNESS / 2)
		shape_def := b2.DefaultShapeDef()
		shape_def.filter.categoryBits = u64(Collision_Categories.Ground)
		shape_def.enableContactEvents = true
		body_def := b2.DefaultBodyDef()
		body_def.position = {0, -SIM_GROUND_THICKNESS / 2}
		body_def.type = .staticBody
		self.ground = b2.CreateBody(self.physics_world, body_def)
		_ = b2.CreatePolygonShape(self.ground, shape_def, box)
	}

	self.root_element = sim_element_spawn(self, nil)

	self.program = program
	vm.init_vm(&self._vm, vm_interop_vtable)
	when BOX2D_DEBUG_DRAW do setup_box2d_debug_draw_vtable(app)

	self.camera = rg.Camera {
		zoom = SIM_PIXELS_PER_METER,
		offset = Vec2{ // TODO: PARAMETER
			f32(g_app_state.window_width),
			f32(g_app_state.window_height),
		} / f32(g_app_state.dpr) * 0.5,
 	}

	self.ready = true
}

sim_destroy :: proc(self: ^SimState) {
	b2.DestroyWorld(self.physics_world)
	self.ground = {}
	self.root_element = {}
	self.camera = {}
	hm.clear(&self.elements)
	vm.reset_vm(&self._vm)
	self.ready = false

	for block in self.program.blocks {
		delete(block)
	}
	delete(self.program.blocks)

}

sim_update :: proc(self: ^SimState, delta_time: f32) {
	if !self.ready do return
	particle_system_update(&self.particles, delta_time)
	sim_execute_plant_bytecode(self, delta_time)
	sim_tick_cells(self, delta_time)
	b2.World_Step(self.physics_world, f32(delta_time), 4)
	sim_process_contact_events(self)
}

sim_tick_cells :: proc(self: ^SimState, dt: f32) {
	for it := hm_iter(&self.elements); e, _ in hm.iterate(&it) {
		if .pruned in e.flags do continue
		e.growth_rate = exp_decay(e.growth_rate, SIM_END_GROWTH_RATE, SIM_CELL_AGING_RATE, dt)
		e.thickness = exp_decay(e.thickness, e.target_thickness, e.growth_rate, dt)
		e.length = exp_decay(e.length, e.target_length, e.growth_rate, dt)
		e.color = exp_decay(e.color, e.target_color, SIM_DYE_RATE, dt)

		tissue := sample_tissue_params(e.lignen)
		if e.lignen_changed {
			b2.Body_SetAngularDamping(e.body, tissue.damping)
			b2.Body_SetLinearDamping(e.body, tissue.damping)
			b2.Joint_SetConstraintTuning(e.joint, tissue.freq, tissue.damping)
			b2.Shape_SetDensity(e.shape, tissue.density, true)
			e.lignen_changed = false

			if e.lignen < 0.01 {
				b2.RevoluteJoint_EnableSpring(e.joint, false)
			} else {
				b2.RevoluteJoint_EnableSpring(e.joint, true)
				b2.Joint_SetConstraintTuning(e.joint, tissue.freq, tissue.damping)
			}
		}

		capsule := b2.Capsule{0, {0, e.length}, e.thickness}
		b2.Shape_SetCapsule(e.shape, capsule)
		b2.Body_ApplyMassFromShapes(e.body)

		if parent, ok := hm.get(&self.elements, e.parent); ok {
			b2.Joint_SetLocalAnchorA(e.joint, {0, parent.length})
		}
	}
}

sim_process_contact_events :: proc(self: ^SimState) {
	events := b2.World_GetContactEvents(self.physics_world)
	for event in events.beginEvents[:events.beginCount] {
		body_a := b2.Shape_GetBody(event.shapeIdA)
		body_b := b2.Shape_GetBody(event.shapeIdB)

		// Check if one of the bodies is the ground
		elem_body: b2.BodyId
		switch {
		case body_a == self.ground:
			elem_body = body_b
		case body_b == self.ground:
			elem_body = body_a
		case: continue
		}


		ud := b2.Body_GetUserData(elem_body)
		if ud == nil do continue

		handle := transmute(Handle)u32(uintptr(ud))
		e := hm.get(&self.elements, handle) or_continue
		if .pruned not_in e.flags do continue

		impact_point := event.manifold.points[0].point
		sim_spawn_burst(&self.particles, impact_point, e.color, amount = 15)

		sim_element_destroy(self, handle)
	}
}

sim_execute_plant_bytecode :: proc(self: ^SimState, dt: f32) {
	context.logger.lowest_level = .Error
	defer context.logger.lowest_level = .Debug
	for it := hm_iter(&self.elements); element, h in hm.iterate(&it) {
		if .pruned in element.flags do continue
		log.debugf("Cell %v is in state %v", h, element.vm_entrypoint)
		err := vm.run(&self._vm, self.program, element)
		if err != nil {
			log.errorf("VM Error: %v", err)
		}
	}
}

sim_render :: proc(app: ^ApplicationState, self: ^SimState, dt: f32) {
	if !self.ready do return
	r := &app.r
	{
		lo, hi: Vec2
		for it := hm_iter(&self.elements); e, _ in hm.iterate(&it) {
			tip_local := Vec2{0, e.length}
			transform := b2.Body_GetTransform(e.body)
			position := b2.TransformPoint(transform, tip_local)

			lo.x = min(position.x, lo.x)
			lo.y = min(position.y, lo.y)
			hi.x = max(position.x, hi.x)
			hi.y = max(position.y, hi.y)
		}
		camera_target := (hi + lo) / 2
		self.camera.target = exp_decay(self.camera.target, camera_target, 5, dt)

		padded_size := (hi - lo) * 1.15
		padded_size.x, padded_size.y = max(padded_size.x, 0.1), max(padded_size.y, 0.1)

		viewport:= Vec2{f32(app.window_width), f32(app.window_height)} / f32(app.dpr)

		zoom := viewport / padded_size

		target_zoom := min(zoom.x, zoom.y, SIM_PIXELS_PER_METER)

		self.camera.zoom = exp_decay(self.camera.zoom, target_zoom, 5, dt)

	}
	rg.frame_begin(r)

	rg.pass_begin(
		r,
		{clear = true, color = BG_COLOR},
		rg.Pipeline_Basic{projection = app.ortho_proj},
	)
	if rg.camera_mode(r, self.camera) {
		for it := hm_iter(&self.elements); e, h in hm.iterate(&it) {
			if e.parent == {} do draw_plant(app, self, h)
		}

		extent: Vec2 = SIM_GROUND_THICKNESS
		rg.draw_rect(r, 0 - {extent.x * 0.5, extent.y}, extent, color = {3, 58, 34, 255})

		particle_system_render(r, &self.particles)

		if app.is_pruning && app.mouse_down && app.cut_start != app.cut_current {
			rg.draw_line(r, app.cut_start, app.cut_current, 0.02, color = {255, 50, 50, 255})
		}
	}
	rg.pass_end(r)


	when BOX2D_DEBUG_DRAW {
		rg.pass_begin(
			&app.r,
			{clear = false, color = BG_COLOR},
			rg.Pipeline_Basic{projection = app.ortho_proj},
		)
		if rg.camera_mode(&app.r, app.camera) {
			b2.World_Draw(app.physics_world, &app.physics_world_debug_draw)
		}
		rg.pass_end(&app.r)
	}

	rg.frame_end(r)

	draw_plant :: proc(
		app: ^ApplicationState,
		self: ^SimState,
		h: Handle,
		prev: ^Sim_Element = nil,
	) {
		r := &app.r
		if e, ok := hm.get(&self.elements, h); ok {
			tip_local := Vec2{0, e.length}
			transform := b2.Body_GetTransform(e.body)
			position := b2.TransformPoint(transform, tip_local)

			rg.draw_circle(r, position, e.thickness, color = e.color)


			prev := prev
			// Inject a dummy prev for the origin segment
			if prev == nil {
				dummy := Sim_Element {
					thickness = e.thickness * 1.2,
					color     = e.color,
				}
				prev = &dummy
			}

			wedge_color: [4]Color = e.color if .interpolate_colors not_in e.flags else {prev.color, prev.color, e.color, e.color}

			rg.draw_wedge(r, transform.p, position, prev.thickness, e.thickness, wedge_color)

			when SIM_DEBUG_RENDERING {
				rc_draw_circle(&rc, prev.position, 5, color = RED)
				rc_draw_circle(&rc, e.position, 8, color = GREEN)
			}

			it := e.first_child
			for {
				child := hm.get(&self.elements, it) or_break
				draw_plant(app, self, child.handle, e)
				it = child.right
			}
		}
	}
}

setup_box2d_debug_draw_vtable :: proc(self: ^SimState) {
	dbg := &self.physics_world_debug_draw
	dbg^ = b2.DefaultDebugDraw()
	dbg.drawShapes = true
	dbg.drawJoints = false
	dbg.drawJointExtras = false
	dbg.userContext = self
	DEBUG_DRAW_OPACITY :: 0x1f
	dbg.DrawSolidPolygonFcn = proc "c" (
		transform: b2.Transform,
		vertices: [^]Vec2,
		vertexCount: i32,
		radius: f32,
		color: b2.HexColor,
		ctx: rawptr,
	) {
		app := cast(^ApplicationState)ctx
		context = app.ctx

		raw := u32(color)
		c: Color
		c.r = u8(raw >> 16)
		c.g = u8(raw >> 8)
		c.b = u8(raw >> 0)
		c.a = DEBUG_DRAW_OPACITY

		count := int(vertexCount)
		rg.encoder_ensure_space_basic(&app.r, count, (count - 2) * 3)

		// Pre-transform and upload all vertices once
		base := u16(len(app.r.vertices))
		for i in 0 ..< count {
			v := vertices[i]
			// Apply Box2D transform: rotate then translate
			rotated := Vec2 {
				transform.q.c * v.x - transform.q.s * v.y,
				transform.q.s * v.x + transform.q.c * v.y,
			}
			world := rotated + transform.p
			rg.append_vertex(&app.r, rg.Vertex2D{pos = world, color = c})
		}

		// Fan triangulation from vertex 0 — valid for Box2D's convex polygons
		for i in 1 ..< count - 1 {
			rg.append_index(&app.r, base)
			rg.append_index(&app.r, base + u16(i))
			rg.append_index(&app.r, base + u16(i + 1))
		}
	}
	dbg.DrawPolygonFcn = proc "c" (
		vertices: [^]Vec2,
		vertexCount: i32,
		color: b2.HexColor,
		ctx: rawptr,
	) {
		app := cast(^ApplicationState)ctx
		context = app.ctx
		raw := u32(color)
		c: Color
		c.r = u8(raw >> 16)
		c.g = u8(raw >> 8)
		c.b = u8(raw >> 0)
		c.a = DEBUG_DRAW_OPACITY

		for i in 0 ..< vertexCount {
			a := vertices[i]
			b := vertices[(i + 1) % vertexCount]
			rg.draw_line(&app.r, a, b, 1.0, c)
		}
	}
	dbg.DrawSolidCapsuleFcn = proc "c" (
		p1, p2: Vec2,
		radius: f32,
		color: b2.HexColor,
		ctx: rawptr,
	) {
		app := cast(^ApplicationState)ctx
		context = app.ctx
		raw := u32(color)
		c: Color
		c.r = u8(raw >> 16)
		c.g = u8(raw >> 8)
		c.b = u8(raw >> 0)
		c.a = DEBUG_DRAW_OPACITY
		rg.draw_wedge(&app.r, p1, p2, radius, radius, c)
		rg.draw_circle(&app.r, p1, radius, color = c)
		rg.draw_circle(&app.r, p2, radius, color = c)
	}
	dbg.DrawSegmentFcn = proc "c" (p1, p2: Vec2, color: b2.HexColor, ctx: rawptr) {
		app := cast(^ApplicationState)ctx
		context = app.ctx
		raw := u32(color)
		c: Color
		c.r = u8(raw >> 16)
		c.g = u8(raw >> 8)
		c.b = u8(raw >> 0)
		c.a = DEBUG_DRAW_OPACITY
		rg.draw_line(&app.r, p1, p2, 0.05, color = c)
	}
	dbg.DrawSolidCircleFcn = proc "c" (
		transform: b2.Transform,
		radius: f32,
		color: b2.HexColor,
		ctx: rawptr,
	) {
		app := cast(^ApplicationState)ctx
		context = app.ctx
		raw := u32(color)
		c: Color
		c.r = u8(raw >> 16)
		c.g = u8(raw >> 8)
		c.b = u8(raw >> 0)
		c.a = DEBUG_DRAW_OPACITY
		rg.draw_circle(&app.r, transform.p, radius, color = c)
	}
	dbg.DrawCircleFcn = proc "c" (center: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
		app := cast(^ApplicationState)ctx
		context = app.ctx
		raw := u32(color)
		c: Color
		c.r = u8(raw >> 16)
		c.g = u8(raw >> 8)
		c.b = u8(raw >> 0)
		c.a = DEBUG_DRAW_OPACITY
		rg.draw_circle(&app.r, center, radius, color = c)
	}
}

@(rodata)
tissue_lut := []TissueMaterial{
		PETAL_TISSUE,
		LEAF_TISSUE,
		STEM_TISSUE,
		WOOD_TISSUE,
}
sample_tissue_params :: proc(lignen: f32) -> TissueMaterial {
	N := len(tissue_lut)
	if N == 0 do return {}
	if N == 1 do return tissue_lut[0]

	sample := clamp(lignen, 0.0, 1.0)
	if sample == 1.0 {
		return tissue_lut[N - 1]
	}
	scaled_sample := sample * f32(N - 1)

	bin_idx := int(scaled_sample)
	if bin_idx >= N - 1 {
		return tissue_lut[N - 1]
	}

	t := scaled_sample - f32(bin_idx)

	mat_a := tissue_lut[bin_idx]
	mat_b := tissue_lut[bin_idx + 1]

	return TissueMaterial{
		density = math.lerp(mat_a.density, mat_b.density, t),
		freq    = math.lerp(mat_a.freq, mat_b.freq, t),
		damping = math.lerp(mat_a.damping, mat_b.damping, t),
	}

}


sim_execute_cut :: proc(self: ^SimState, p1, p2: Vec2) {
	CutHit :: struct { handle: Handle, t: f32 }
	hits: [dynamic]CutHit
	defer delete(hits)

	for it := hm_iter(&self.elements); e, h in hm.iterate(&it) {
		transform := b2.Body_GetTransform(e.body)
		p3 := transform.p
		p4 := b2.TransformPoint(transform, {0, e.length})

		if _, s, ok := segment_intersect(p1, p2, p3, p4); ok && s > 0.01 && s < 0.99 {
			safe_s := clamp(s, 0.05, 0.95)
			append(&hits, CutHit{h, s})
		}
	}

	for hit in hits do bisect_element(self, hit.handle, hit.t)
}

bisect_element :: proc(self: ^SimState, handle: Handle, t: f32) -> bool {
	e := hm.get(&self.elements, handle) or_return
	b2.Body_IsValid(e.body) or_return

	cut_length := e.length * t
	rem_length := e.length - cut_length
	transform := b2.Body_GetTransform(e.body)
	cut_world_pos := b2.TransformPoint(transform, {0, cut_length})

	if s_handle, s, ok := sim_element_clone(self, handle); ok {
		s.length = rem_length
		s.target_length = rem_length

		shape_def := make_element_shape_def(b2.Shape_GetDensity(e.shape), true)
		body_def := make_element_body_def(
			cut_world_pos, transform.q,
			b2.Body_GetLinearVelocity(e.body),
			b2.Body_GetAngularVelocity(e.body),
		)
		s.body = b2.CreateBody(self.physics_world, body_def)
		s.shape = b2.CreateCapsuleShape(s.body, shape_def, {0, {0, rem_length}, s.thickness})
		b2.Body_SetUserData(s.body, rawptr(uintptr(transmute(u32)s_handle)))

		s.first_child = e.first_child
		s.last_child = e.last_child

		subtree_add_flags(self, s_handle, {.pruned})

		child_it := s.first_child
		for child_it != {} {
			child := hm.get(&self.elements, child_it) or_break

			next_it := child.right

			child.parent = s_handle
			if b2.Joint_IsValid(child.joint) do b2.DestroyJoint(child.joint)

			c_rot, s_rot := b2.Body_GetRotation(child.body), b2.Body_GetRotation(s.body)
			theta := math.atan2(c_rot.s, c_rot.c) - math.atan2(s_rot.s, s_rot.c)

			tissue := sample_tissue_params(child.lignen)
			spring := child.lignen != 0
			j_def := make_element_joint_def(s.body, child.body, {0, rem_length}, theta, tissue, spring)
			child.joint = b2.CreateRevoluteJoint(self.physics_world, j_def)

			child_it = next_it
		}
	} else {

		subtree_add_flags(self, handle, {.pruned})
		e.flags -= {.pruned}
		child_it := e.first_child
		for child_it != {} {
			child := hm.get(&self.elements, child_it) or_break
			next_it := child.right

			child.parent = {}
			child.left = {}
			child.right = {}

			if b2.Joint_IsValid(child.joint) {
				b2.DestroyJoint(child.joint)
				child.joint = {}
			}

			child_it = next_it
		}
	}

	e.vm_entrypoint = 0 // Reset the trimmed bud to the initial state
	e.first_child = {}
	e.last_child = {}
	e.length = cut_length
	e.target_length = cut_length
	b2.Shape_SetCapsule(e.shape, b2.Capsule{0, {0, cut_length}, e.thickness})
	b2.Body_ApplyMassFromShapes(e.body)

	return true

	subtree_add_flags :: proc(self: ^SimState, elem: Handle, add_flags: ElementFlags) -> bool {
		e := hm.get(&self.elements, elem) or_return
		e.flags += add_flags
		it := e.first_child
		for it != {} {
			child := hm.get(&self.elements, it) or_break
			subtree_add_flags(self, it, add_flags)
			it = child.right
		}
		return true
	}
}
