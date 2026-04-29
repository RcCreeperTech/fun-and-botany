package engine

import "../vm"
import "core:log"
import "base:intrinsics"
import hm "core:container/handle_map"
import "core:math"
import la "core:math/linalg"
import rg "renderer"
import b2 "vendor:box2d"

SIM_DEBUG_RENDERING :: false
SIM_DYE_RATE :: 1.7 // TODO: Per cell
SIM_BASELINE_GROWTH_RATE :: 0.5
SIM_END_GROWTH_RATE :: 0.01
SIM_CELL_AGING_RATE :: 0.7
SIM_PIXELS_PER_METER :: 100

TissueMaterial :: struct {
	density, freq, damping: f32
}

WOOD_TISSUE :: TissueMaterial {7, 28, 1}
STEM_TISSUE :: TissueMaterial {1.5, 5, 0.675}
LEAF_TISSUE :: TissueMaterial {0.2, 2, 0.5}
PETAL_TISSUE :: TissueMaterial {0.05, 1.25, 0.33}

Matrix3 :: la.Matrix3x3f32
Vec2 :: [2]f32
Vec3 :: [3]f32

Collision_Categories :: enum u64 {
	Ground  = 0x00000001,
	Element = 0x00000002,
}

sim_update :: proc(app: ^ApplicationState, delta_time: f32) {
	sim_execute_plant_bytecode(app, delta_time)
	sim_tick_cells(app, delta_time)
	b2.World_Step(app.physics_world, f32(delta_time), 4)
}

sim_tick_cells :: proc(app: ^ApplicationState, dt: f32) {
	it := hm.iterator_make(&app.elements)
	for e, _ in hm.iterate(&it) {
		e.growth_rate = exp_decay(e.growth_rate, SIM_END_GROWTH_RATE, SIM_CELL_AGING_RATE, dt)
		e.thickness = exp_decay(e.thickness, e.target_thickness, e.growth_rate, dt)
		e.length = exp_decay(e.length, e.target_length, e.growth_rate, dt)
		e.color = exp_decay(e.color, e.target_color, SIM_DYE_RATE, dt)

		capsule := b2.Capsule{0, {0, e.length}, e.thickness}
		b2.Shape_SetCapsule(e.shape, capsule)
		b2.Body_ApplyMassFromShapes(e.body)

		if parent, ok := hm.get(&app.elements, e.parent); ok {
			b2.Joint_SetLocalAnchorA(e.joint, {0, parent.length})
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
	//
	target_thickness:        f32,
	target_length:           f32,
	target_color:            Color,
	target_stiffness:		 f32,
	target_density:		     f32,
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

sim_element_spawn :: proc(
	app: ^ApplicationState,
	parent: ^Sim_Element,
	theta: f32 = 0,
	mass: f32 = 1,
	vm_entrypoint: vm.Label = vm.Label(0),
) {
	parent_tip_local := Vec2{0, parent.length}
	parent_transform := b2.Body_GetTransform(parent.body)

	shape_def := b2.DefaultShapeDef()
	shape_def.density = WOOD_TISSUE.density // TODO make this a parameter
	shape_def.filter.categoryBits = u64(Collision_Categories.Element)
	shape_def.filter.maskBits = u64(Collision_Categories.Ground)
	body_def := b2.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = b2.TransformPoint(parent_transform, parent_tip_local)
	orientation := b2.MulRot(b2.MakeRot(theta), b2.Body_GetRotation(parent.body))
	body_def.rotation = orientation
	body := b2.CreateBody(app.physics_world, body_def)
	shape := b2.CreateCapsuleShape(body, shape_def, {0, {0, 0.01}, 0.01})

	joint_def := b2.DefaultRevoluteJointDef()
	when BOX2D_DEBUG_DRAW do joint_def.drawSize = 0.08
	joint_def.bodyIdA = parent.body
	joint_def.bodyIdB = body
	joint_def.localAnchorA = parent_tip_local
	joint_def.localAnchorB = 0
	joint_def.targetAngle = theta
	joint_def.enableSpring = true
	joint_def.hertz = WOOD_TISSUE.freq // TODO: parameter
	joint_def.dampingRatio = WOOD_TISSUE.damping // TODO: Parameter
	joint_def.collideConnected = false
	joint := b2.CreateRevoluteJoint(app.physics_world, joint_def)

	child := hm.add(
	&app.elements,
	Sim_Element {
		parent           = parent.handle, // point to the parent
		right            = parent.first_child, // link into the head of the sibling dll
		target_length    = parent.target_length * 0.95,
		length           = 0.01,
		target_thickness = parent.target_thickness * 0.8,
		thickness        = 0.01,
		target_color     = parent.target_color,
		color            = parent.color,
		growth_rate      = SIM_BASELINE_GROWTH_RATE,
		depth            = parent.depth + 1,
		vm_entrypoint    = vm_entrypoint,
		body             = body,
		shape            = shape,
		joint            = joint,
	},
	)

	if first, ok := hm.get(&app.elements, parent.first_child); ok {
		first.left = child
		parent.first_child = child
	} else { 	// parent has no children
		parent.first_child, parent.last_child = child, child
	}
}

sim_execute_plant_bytecode :: proc(app: ^ApplicationState, dt: f32) {
	it := hm.iterator_make(&app.elements)
	for element, h in hm.iterate(&it) {
		log.debugf("Cell %v is in state %v", h, element.vm_entrypoint)
		err := vm.run(&app.vm, app.loaded_program, element)
		if err != nil {
			log.errorf("VM Error: %v", err)
		}
	}
}

@(private)
IS_FLOAT :: intrinsics.type_is_float
@(private)
ELEM_TYPE :: intrinsics.type_elem_type
@(private)
IS_ARRAY :: intrinsics.type_is_array

exp_decay :: proc {
	exp_decay_float,
	exp_decay_color,
}
// Lerp that respects delta time
// Useful range approx. 1 to 25, from slow to fast
exp_decay_float :: proc(a, b: $T, decay, dt: f32) -> (out: T) where IS_FLOAT(ELEM_TYPE(T)) {
	when IS_ARRAY(T) {
		for i in 0 ..< len(T) {
			out[i] = b[i] + (a[i] - b[i]) * math.exp(-decay * dt)
		}
	} else {
		out = b + (a - b) * math.exp(-decay * dt)
	}
	return
}
exp_decay_color :: proc(a, b: Color, decay, dt: f32) -> (color: Color) {
	fa, fb := to_fcolor(a), to_fcolor(b)
	for i in 0 ..< 4 {
		color[i] = u8(exp_decay_float(fa[i], fb[i], decay, dt) * 255)
	}
	return
}

sim_render :: proc(app: ^ApplicationState, dt: f32) {
	{
		lo, hi: Vec2 = math.INF_F32, -math.INF_F32
		it := hm.iterator_make(&app.elements)
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
		app.camera.target = exp_decay(app.camera.target, camera_target, 5, dt)
	}
	rg.frame_begin(&app.r)

	rg.pass_begin(
		&app.r,
		{clear = true, color = BG_COLOR},
		rg.Pipeline_Basic{projection = app.ortho_proj},
	)
	if rg.camera_mode(&app.r, app.camera) {
		draw_plant(app, app.root_element)

		extent: Vec2 = SIM_GROUND_THICKNESS
		rg.draw_rect(&app.r, 0 - {extent.x*0.5, extent.y}, extent, color = {3, 58, 34, 255})
	}
	rg.pass_end(&app.r)

	rg.frame_end(&app.r)

	draw_plant :: proc(app: ^ApplicationState, h: Handle, prev: ^Sim_Element = nil) {
		if e, ok := hm.get(&app.elements, h); ok {
			tip_local := Vec2{0, e.length}
			transform := b2.Body_GetTransform(e.body)
			position := b2.TransformPoint(transform, tip_local)

			rg.draw_circle(&app.r, position, e.thickness, color = e.color)


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


			rg.draw_wedge(
				&app.r,
				prev_position,
				position,
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
				child := hm.get(&app.elements, it) or_break
				draw_plant(app, child.handle, e)
				it = child.right
			}
		}
	}
}
