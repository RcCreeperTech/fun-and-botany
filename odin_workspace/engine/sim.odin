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

TissueMaterial :: struct {
	density, freq, damping: f32,
}

WOOD_TISSUE :: TissueMaterial{7, 28, 1}
STEM_TISSUE :: TissueMaterial{1.5, 5, 0.675}
LEAF_TISSUE :: TissueMaterial{0.2, 2, 0.5}
PETAL_TISSUE :: TissueMaterial{0.05, 1.25, 0.33}

Matrix3 :: la.Matrix3x3f32
Vec2 :: [2]f32
Vec3 :: [3]f32

Handle :: hm.Handle32
ElementMap :: hm.Static_Handle_Map(1024, Sim_Element, Handle)
ElementFlag :: enum {
	interpolate_colors
}
ElementFlags :: bit_set[ElementFlag]
Sim_Element :: struct {
	// Connnection Info
	handle:                  Handle,
	parent, left, right:     Handle,
	first_child, last_child: Handle,
	//
	flags:                   ElementFlags,
	target_thickness:        f32,
	target_length:           f32,
	target_color:            Color,
	target_stiffness:        f32,
	target_density:          f32,
	thickness:               f32,
	length:                  f32,
	color:                   Color,
	stiffness:               f32,
	density:                 f32,
	growth_rate:             f32,
	depth:                   u8,
	vm_entrypoint:           vm.Label,
	// Physics handles
	body:                    b2.BodyId,
	shape:                   b2.ShapeId,
	joint:                   b2.JointId,
}

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
}

sim_init :: proc(self: ^SimState, program: vm.Program) {
	{ 	// Create the physics world
		world_def := b2.DefaultWorldDef()
		world_def.gravity = {0, -9.81}
		world_def.enableSleep = false
		world_def.enableContinuous = false
		self.physics_world = b2.CreateWorld(world_def)
	}

	{ 	// Create the ground
		box := b2.MakeBox(SIM_GROUND_THICKNESS / 2, SIM_GROUND_THICKNESS / 2)
		shape_def := b2.DefaultShapeDef()
		shape_def.filter.categoryBits = u64(Collision_Categories.Ground)
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
	sim_execute_plant_bytecode(self, delta_time)
	sim_tick_cells(self, delta_time)
	b2.World_Step(self.physics_world, f32(delta_time), 4)
}

sim_tick_cells :: proc(self: ^SimState, dt: f32) {
	it := hm.iterator_make(&self.elements)
	for e, _ in hm.iterate(&it) {
		e.growth_rate = exp_decay(e.growth_rate, SIM_END_GROWTH_RATE, SIM_CELL_AGING_RATE, dt)
		e.thickness = exp_decay(e.thickness, e.target_thickness, e.growth_rate, dt)
		e.length = exp_decay(e.length, e.target_length, e.growth_rate, dt)
		e.color = exp_decay(e.color, e.target_color, SIM_DYE_RATE, dt)

		capsule := b2.Capsule{0, {0, e.length}, e.thickness}
		b2.Shape_SetCapsule(e.shape, capsule)
		b2.Body_ApplyMassFromShapes(e.body)

		if parent, ok := hm.get(&self.elements, e.parent); ok {
			b2.Joint_SetLocalAnchorA(e.joint, {0, parent.length})
		}
	}
}

sim_element_spawn :: proc(
	self: ^SimState,
	parent: ^Sim_Element,
	theta: f32 = 0,
	mass: f32 = 1,
	vm_entrypoint: vm.Label = vm.Label(0),
) -> Handle {
	parent_body: b2.BodyId
	parent_anchor, start_pos: Vec2
	start_rot: b2.Rot

	// Pre-fill fields common to both Root and Child elements
	child_elem := Sim_Element {
		length        = 0.01,
		thickness     = 0.01,
		growth_rate   = SIM_BASELINE_GROWTH_RATE,
		vm_entrypoint = vm_entrypoint,
	}

	// Calculate attachment points and inherited properties
	if parent != nil {
		parent_body = parent.body
		parent_anchor = {0, parent.length}
		parent_transform := b2.Body_GetTransform(parent.body)
		start_pos = b2.TransformPoint(parent_transform, parent_anchor)
		start_rot = b2.MulRot(b2.MakeRot(theta), b2.Body_GetRotation(parent.body))

		child_elem.parent = parent.handle
		child_elem.right = parent.first_child // link into head of sibling dll
		child_elem.depth = parent.depth + 1
		child_elem.target_length = parent.target_length * 0.95
		child_elem.target_thickness = parent.target_thickness * 0.8
		child_elem.target_color = parent.target_color
		child_elem.color = parent.color
		child_elem.flags = parent.flags
	} else {
		// Root element attaches to the ground
		parent_body = self.ground
		parent_anchor = {0, SIM_GROUND_THICKNESS / 2}
		start_pos = {0, 0}
		start_rot = b2.MakeRot(theta)

		child_elem.depth = 0
		child_elem.target_length = 1.0
		child_elem.target_thickness = 0.4
		child_elem.target_color = DARKGREEN
		child_elem.color = DARKGREEN
	}

	// Physics setup
	shape_def := b2.DefaultShapeDef()
	DENSITY_DECAY_FACTOR :: 0.3
	// TODO: make this a parameter
	shape_def.density = WOOD_TISSUE.density * math.pow_f32(1. - DENSITY_DECAY_FACTOR, f32(child_elem.depth))
	shape_def.filter.categoryBits = u64(Collision_Categories.Element)
	shape_def.filter.maskBits = u64(Collision_Categories.Ground)

	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = start_pos
	body_def.rotation = start_rot

	child_elem.body = b2.CreateBody(self.physics_world, body_def)
	child_elem.shape = b2.CreateCapsuleShape(child_elem.body, shape_def, {0, {0, 0.01}, 0.01})

	joint_def := b2.DefaultRevoluteJointDef()
	when BOX2D_DEBUG_DRAW do joint_def.drawSize = 0.08
	joint_def.bodyIdA = parent_body
	joint_def.bodyIdB = child_elem.body
	joint_def.localAnchorA = parent_anchor
	joint_def.localAnchorB = 0
	joint_def.targetAngle = theta
	joint_def.enableSpring = true
	joint_def.hertz = WOOD_TISSUE.freq // TODO: parameter
	joint_def.dampingRatio = WOOD_TISSUE.damping // TODO: Parameter
	joint_def.collideConnected = false
	child_elem.joint = b2.CreateRevoluteJoint(self.physics_world, joint_def)

	// Add to ECS / Handle Map
	child := hm.add(&self.elements, child_elem)

	// Link up the tree hierarchy if it's not the root
	if parent != nil {
		if first, ok := hm.get(&self.elements, parent.first_child); ok {
			first.left = child
			parent.first_child = child
		} else { 	// parent has no children yet
			parent.first_child, parent.last_child = child, child
		}
	}

	return child
}

sim_execute_plant_bytecode :: proc(self: ^SimState, dt: f32) {
	context.logger.lowest_level = .Error
	defer context.logger.lowest_level = .Debug
	it := hm.iterator_make(&self.elements)
	for element, h in hm.iterate(&it) {
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
		it := hm.iterator_make(&self.elements)
		for e, _ in hm.iterate(&it) {
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
		draw_plant(app, self, self.root_element)

		extent: Vec2 = SIM_GROUND_THICKNESS
		rg.draw_rect(r, 0 - {extent.x * 0.5, extent.y}, extent, color = {3, 58, 34, 255})
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
			prev_position: Vec2
			// Inject a dummy prev for the origin segment
			if prev == nil {
				dummy := Sim_Element {
					thickness = e.thickness * 1.2,
					color     = e.color,
				}
				prev = &dummy
			} else {
				prev_tip_local := Vec2{0, prev.length}
				prev_transform := b2.Body_GetTransform(prev.body)
				prev_position = b2.TransformPoint(prev_transform, prev_tip_local)
			}


			wedge_color: [4]Color = e.color if .interpolate_colors not_in e.flags else {prev.color, prev.color, e.color, e.color}

			rg.draw_wedge(r, prev_position, position, prev.thickness, e.thickness, wedge_color)

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
