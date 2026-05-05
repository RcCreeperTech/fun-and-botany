package engine

import "core:math"
import "../vm"
import b2 "vendor:box2d"
import hm "core:container/handle_map"

ElementFlag :: enum {
	interpolate_colors,
	pruned,
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
	thickness:               f32,
	length:                  f32,
	color:                   Color,
	lignen_changed:          bool,
	lignen:                  f32,
	growth_rate:             f32,
	depth:                   u8,
	vm_entrypoint:           vm.Label,
	// Physics handles
	body:                    b2.BodyId,
	shape:                   b2.ShapeId,
	joint:                   b2.JointId,
}

sim_element_spawn :: proc(
	self: ^SimState,
	parent: ^Sim_Element,
	theta: f32 = 0,
	mass: f32 = 1,
	vm_entrypoint: vm.Label = vm.Label(0),
) -> (Handle, bool) #optional_ok {
	if hm_full(self.elements) do return {}, false

	parent_body: b2.BodyId
	parent_anchor, start_pos: Vec2
	start_rot: b2.Rot

	elem := Sim_Element {
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

		elem.parent = parent.handle
		elem.right = parent.first_child // link into head of sibling dll
		elem.depth = parent.depth + 1
		elem.target_color = parent.target_color
		elem.color = parent.color
		elem.flags = parent.flags
		elem.lignen = parent.lignen
		elem.lignen_changed = true
	} else {
		// Root element attaches to the ground
		parent_body = self.ground
		parent_anchor = {0, SIM_GROUND_THICKNESS / 2}
		start_pos = {0, 0}
		start_rot = b2.MakeRot(theta)

		elem.target_color = DARKGREEN
		elem.color = DARKGREEN
		elem.lignen = 1
	}

	BASE_LENGTH :: 1
	BASE_THICKNESS :: 0.4
	LENGTH_DECAY_FACTOR :: 0.05
	THICKNESS_DECAY_FACTOR :: 0.20
	elem.target_length = BASE_LENGTH * math.pow_f32(1. - LENGTH_DECAY_FACTOR, f32(elem.depth))
	elem.target_thickness = BASE_THICKNESS * math.pow_f32(1. - THICKNESS_DECAY_FACTOR, f32(elem.depth))

	tissue := sample_tissue_params(elem.lignen)

	// Physics setup
	DENSITY_DECAY_FACTOR :: 0.3
	density := tissue.density * math.pow_f32(1. - DENSITY_DECAY_FACTOR, f32(elem.depth))

	shape_def := make_element_shape_def(density)
	body_def := make_element_body_def(start_pos, start_rot)

	elem.body = b2.CreateBody(self.physics_world, body_def)
	elem.shape = b2.CreateCapsuleShape(elem.body, shape_def, {0, {0, 0.01}, 0.01})

	joint_def := make_element_joint_def(parent_body, elem.body, parent_anchor, theta, tissue)
	elem.joint = b2.CreateRevoluteJoint(self.physics_world, joint_def)

	elem_handle := hm.add(&self.elements, elem)

	if e, ok := hm.get(&self.elements, elem_handle); ok {
		b2.Body_SetUserData(e.body, rawptr(uintptr(transmute(u32)elem_handle)))
	}

	// Link up the tree hierarchy if it's not the root
	if parent != nil {
		if first, ok := hm.get(&self.elements, parent.first_child); ok {
			first.left = elem_handle
			parent.first_child = elem_handle
		} else { 	// parent has no children yet
			parent.first_child, parent.last_child = elem_handle, elem_handle
		}
	}

	return elem_handle, true
}

sim_element_destroy :: proc(self: ^SimState, handle: Handle) {
	e, ok := hm.get(&self.elements, handle)
	if !ok do return

	// Unlink from parent's hierarchy
	if parent, p_ok := hm.get(&self.elements, e.parent); p_ok {
		if left, l_ok := hm.get(&self.elements, e.left); l_ok {
		 	left.right = e.right
		} else {
			parent.first_child = e.right
		}

		if right, r_ok := hm.get(&self.elements, e.right); r_ok {
		 	right.left = e.left
		} else {
			parent.last_child = e.left
		}
	}

	// Cannot do this in place so
	children := make([dynamic]^Sim_Element)
	defer delete(children)
	for it := e.first_child; true; {
		child := hm.get(&self.elements, it) or_break
		append(&children, child)
		it = child.right
	}
	// Unlink the children
	for child in children {
		child.parent = {}
		child.left = {}
		child.right = {}
	}

	if b2.Joint_IsValid(e.joint) do b2.DestroyJoint(e.joint)
	if b2.Body_IsValid(e.body) do b2.DestroyBody(e.body)
	hm.remove(&self.elements, handle)
}

// Clones biological parameters into a new ECS allocation.
// Safely zeroes out all physics IDs and hierarchy pointers to prevent aliasing.
sim_element_clone :: proc(self: ^SimState, src_handle: Handle) -> (Handle, ^Sim_Element, bool) {
	if hm_full(self.elements) do return {}, nil, false

	src, ok := hm.get(&self.elements, src_handle)
	if !ok do return {}, nil, false

	clone := src^

	clone.handle = {}
	clone.parent = {}
	clone.left = {}
	clone.right = {}
	clone.first_child = {}
	clone.last_child = {}

	clone.body = {}
	clone.shape = {}
	clone.joint = {}

	new_handle := hm.add(&self.elements, clone)
	new_ptr, new_ok := hm.get(&self.elements, new_handle)

	if new_ok {
		new_ptr.handle = new_handle
	}

	return new_handle, new_ptr, new_ok
}

// --- Box2D Initializer Helpers ---
make_element_shape_def :: proc(density: f32, contact_events := false) -> b2.ShapeDef {
	def := b2.DefaultShapeDef()
	def.density = density
	def.filter.categoryBits = u64(Collision_Categories.Element)
	def.filter.maskBits = u64(Collision_Categories.Ground)
	def.enableContactEvents = contact_events
	return def
}

make_element_body_def :: proc(
	position: Vec2,
	rotation: b2.Rot,
	lin_vel: Vec2 = {0, 0},
	ang_vel: f32 = 0,
) -> b2.BodyDef {
	def := b2.DefaultBodyDef()
	def.type = .dynamicBody
	def.position = position
	def.rotation = rotation
	def.linearVelocity = lin_vel
	def.angularVelocity = ang_vel

	return def
}

make_element_joint_def :: proc(
	body_a, body_b: b2.BodyId,
	anchor_a: Vec2,
	theta: f32,
	tissue: TissueMaterial,
) -> b2.RevoluteJointDef {
	def := b2.DefaultRevoluteJointDef()
	when BOX2D_DEBUG_DRAW do def.drawSize = 0.08

	def.bodyIdA = body_a
	def.bodyIdB = body_b
	def.localAnchorA = anchor_a
	def.localAnchorB = 0
	def.targetAngle = theta

	def.enableSpring = true
	def.collideConnected = false

	def.hertz = tissue.freq
	def.dampingRatio = tissue.damping

	return def
}
