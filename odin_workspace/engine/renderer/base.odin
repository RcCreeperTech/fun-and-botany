package renderer

import "core:fmt"
import "core:log"
import "core:math"
import la "core:math/linalg"
import "core:mem"

Matrix3 :: la.Matrix3x3f32
Vec2 :: [2]f32
Vec3 :: [3]f32
Color :: [4]u8

WHITE :: Color{255, 255, 255, 255}

// Opaque handle to a texture resource on the GPU
// INVALID_HANDLE = default 1x1 white pixel
Texture_Handle :: distinct u32
// Only persistent GPU resources get handles — things the platform allocates
// once and reuses across frames. Dynamic geometry lives in staging memory and
// is uploaded+drawn in a single platform step, no handle needed.
Framebuffer_Handle :: distinct u32

DEFAULT_TEXTURE :: Texture_Handle(0)
DEFAULT_FRAMEBUFFER :: Framebuffer_Handle(0)

// Dynamic geometry is passed as slices pointing into `Frame_State`'s staging
// arrays. The platform uploads and draws in one step — there is no separate
// upload command because geometry changes every frame anyway.
//
// Slice data is valid only until `frame_begin` is called for the next
// frame. The platform must not hold references across frames.
Render_Command :: union {
	Cmd_Draw_Basic,
	Cmd_Draw_Soft,
}

// Draw a batch of indexed triangles using the basic pipeline.
// Vertices and indices are slices into the frame staging arrays and are
// valid only for the duration of the frame. The platform uploads and draws
// in a single step — indices are local to the vertex slice, not global.
Cmd_Draw_Basic :: struct {
	texture:  Texture_Handle,
	vertices: []Vertex2D,
	indices:  []u16,
}

Vertex2D :: struct {
	pos:   Vec2,
	uv:    Vec2,
	color: Color,
}

// Draw a batch of soft shape instances using the instanced pipeline.
// Each instance is a self-contained shape description — instances do not
// reference shared vertex data and carry no indices. The platform is
// responsible for providing the unit quad geometry these are rendered onto.
Cmd_Draw_Soft :: struct {
	instances: []SoftInstance,
}

SoftInstance :: struct {
	color:  Color,
	radius: f32,
	data:   union {
		SoftCircle,
		SoftCapsule,
		SoftRhombus,
		SoftTriangle,
		SoftBezier,
	},
}

SoftCircle :: struct {
	center: Vec2,
}
SoftCapsule :: struct {
	start, end: Vec2,
}
SoftTriangle :: struct {
	a, b, c: Vec2,
}
SoftBezier :: struct {
	a, b, control: Vec2,
}
SoftRhombus :: struct {
	start, end: Vec2,
	radius_end: f32,
}

// Describes the output target and clear behavior for a render pass.
// A pass renders to either an offscreen framebuffer or the default screen
// framebuffer when target is INVALID_HANDLE. All commands within the pass
// write to this target.
Pass_Attachment :: struct {
	target:        Framebuffer_Handle, // INVALID_HANDLE = default framebuffer
	width, height: i32,
	clear:         bool,
	color:         Color,
}

Pipeline :: union {
	Pipeline_Basic,
	Pipeline_Soft_Shapes,
	Pipeline_Soft_Composite,
}

Pipeline_Basic :: struct {
	projection: la.Matrix4f32,
}
Pipeline_Soft_Shapes :: struct {
	projection:     la.Matrix4f32,
	radial_falloff: f32,
}
Pipeline_Soft_Composite :: struct {
	projection: la.Matrix4f32,
}

// Owns a contiguous range of the command list and declares its output
// attachment upfront. The platform binds the framebuffer once per pass then
// dispatches all commands within it.
Render_Pass :: struct {
	attachment:     Pass_Attachment,
	pipeline:       Pipeline,
	commands_begin: int,
	commands_end:   int,
}


// Filled by the application during a frame via `draw_(...)` calls.
// The platform consumes it via `platform_execute_frame`.
Renderer_State :: struct {
	passes:        [dynamic]Render_Pass,
	commands:      [dynamic]Render_Command,
	frame_arena:   mem.Dynamic_Arena,
	frame_alloc:   mem.Allocator,
	using encoder: Command_Encoder,
}

COMMAND_MAX_VERTICES :: 16384
COMMAND_MAX_INDICES :: COMMAND_MAX_VERTICES * 2
COMMAND_MAX_INSTANCES :: 4096
// This is a struct that can encode any pass. Not all fields are used at the
// same time. Currently pipeline holds the tag that is used for determining the
// encoder variant. This could be optimized by making this a union and embedding
// the Pipeline_ variants in each subtype.
Command_Encoder :: struct {
	pipeline:          Pipeline,
	vertices:          [dynamic]Vertex2D,
	indices:           [dynamic]u16,
	soft_instances:    [dynamic]SoftInstance,
	transform_stack:   [dynamic]Matrix3,
	current_transform: Matrix3,
	current_texture:   Texture_Handle,
}

encoder_expect :: #force_inline proc(encoder: ^Command_Encoder, $T: typeid) {
	if _, ok := encoder.pipeline.(T); !ok {
		log.panicf("Encoder must be in state %v to perform this operation", typeid_of(T))
	}
}

encoder_flush :: proc(self: ^Renderer_State) {
	pass := _get_pass(self)
	switch pipeline in pass.pipeline {
	case Pipeline_Basic:
		encoder_expect(self, Pipeline_Basic)
		encoded: Cmd_Draw_Basic

		encoded.texture = self.current_texture

		encoded.vertices = make([]Vertex2D, len(self.vertices), self.frame_alloc)
		copy(encoded.vertices, self.vertices[:])
		clear(&self.vertices)

		encoded.indices = make([]u16, len(self.indices), self.frame_alloc)
		copy(encoded.indices, self.indices[:])
		clear(&self.indices)

		append(&self.commands, encoded)

	case Pipeline_Soft_Shapes:
		encoder_expect(self, Pipeline_Soft_Shapes)
		encoded: Cmd_Draw_Soft

		encoded.instances = make([]SoftInstance, len(self.soft_instances), self.frame_alloc)
		copy(encoded.instances, self.soft_instances[:])
		clear(&self.soft_instances)

		append(&self.commands, encoded)

	case Pipeline_Soft_Composite:
		encoder_expect(&self.encoder, Pipeline_Soft_Composite)
		unimplemented()
	}
}

encoder_ensure_space_basic :: proc(
	self: ^Renderer_State,
	required_vertices, required_indices: int,
) {
	encoder_expect(self, Pipeline_Basic)
	vertex_overflow := len(self.vertices) + required_vertices > COMMAND_MAX_VERTICES
	index_overflow := len(self.indices) + required_indices > COMMAND_MAX_INDICES
	if vertex_overflow || index_overflow {
		encoder_flush(self)
	}
}

encoder_ensure_space_soft :: proc(
	self: ^Renderer_State,
	required_vertices, required_indices: int,
) {
	encoder_expect(self, Pipeline_Soft_Shapes)
	overflow := len(self.vertices) + required_vertices > COMMAND_MAX_INSTANCES
	if overflow {
		encoder_flush(self)
	}
}

init :: proc(self: ^Renderer_State, allocator := context.allocator) {
	mem.dynamic_arena_init(&self.frame_arena, allocator)
	self.frame_alloc = mem.dynamic_arena_allocator(&self.frame_arena)
	return
}

frame_begin :: proc(self: ^Renderer_State) {
	clear(&self.passes)
	clear(&self.commands)
	mem.dynamic_arena_reset(&self.frame_arena)
}

frame_end :: proc(self: ^Renderer_State) {
	assert(self.encoder.pipeline == nil)
}

pass_begin :: proc(self: ^Renderer_State, attachment: Pass_Attachment, pipeline: Pipeline) {
	switch _ in pipeline {
	case Pipeline_Basic:
		self.pipeline = pipeline
	case Pipeline_Soft_Shapes:
		self.pipeline = pipeline
	case Pipeline_Soft_Composite:
		self.pipeline = pipeline
	case nil:
		panic("nil is not a valid pipeline")
	}
	append(
		&self.passes,
		Render_Pass {
			attachment = attachment,
			pipeline = pipeline,
			commands_begin = len(self.commands),
			commands_end = len(self.commands),
		},
	)
}

pass_end :: proc(self: ^Renderer_State) {
	assert(len(self.passes) != 0, "There is no pass to end!")

	encoder_flush(self)

	clear(&self.transform_stack)
	self.current_transform = 1
	self.current_texture = DEFAULT_TEXTURE

	pass := _get_pass(self)
	// Update the end index
	pass.commands_end = len(self.commands)
	// For saftey checks
	self.encoder.pipeline = nil
}

set_current_texture :: proc(self: ^Renderer_State, texture: Texture_Handle = DEFAULT_TEXTURE) {
	if self.current_texture != texture {
		encoder_flush(self)
		self.current_texture = texture
	}
}

@(private = "file")
_get_pass :: proc(self: ^Renderer_State) -> ^Render_Pass {
	return &self.passes[len(self.passes) - 1]
}


append_vertex :: proc(self: ^Renderer_State, vert: Vertex2D) -> u16 {
	idx := len(self.vertices)
	vert := vert
	vert.pos = (self.current_transform * Vec3{vert.pos.x, vert.pos.y, 1}).xy
	append(&self.vertices, vert)
	return u16(idx)
}


append_index :: proc(self: ^Renderer_State, idx: u16) {
	append(&self.indices, idx)
}


append_soft_instance :: proc(self: ^Renderer_State, data: SoftInstance) {
	append(&self.soft_instances, data)
}

draw_line :: proc(self: ^Renderer_State, start, end: Vec2, thickness: f32 = 10.0, color := WHITE) {
	encoder_ensure_space_basic(self, 4, 6)
	// Calculate perpendicular vector for thickness
	dir := end - start
	perp := la.normalize0(la.orthogonal(dir)) * thickness * 0.5

	// 4 corners of the line segment
	p1 := append_vertex(self, Vertex2D{pos = start - perp, uv = {0, 0}, color = color})
	p2 := append_vertex(self, Vertex2D{pos = start + perp, uv = {1, 0}, color = color})
	p3 := append_vertex(self, Vertex2D{pos = end - perp, uv = {0, 1}, color = color})
	p4 := append_vertex(self, Vertex2D{pos = end + perp, uv = {1, 1}, color = color})

	// Push 2 triangles to the batch
	append_index(self, p1)
	append_index(self, p2)
	append_index(self, p4)
	append_index(self, p1)
	append_index(self, p4)
	append_index(self, p3)
}

draw_wedge :: proc(self: ^Renderer_State, start, end: Vec2, r1, r2: f32, color: [4]Color = WHITE) {
	encoder_ensure_space_basic(self, 4, 6)

	ab := la.normalize0(end - start)
	perp := Vec2{-ab.y, ab.x}

	p1 := append_vertex(self, Vertex2D{pos = start - perp * r1, uv = {0, 0}, color = color[0]})
	p2 := append_vertex(self, Vertex2D{pos = start + perp * r1, uv = {1, 0}, color = color[1]})
	p3 := append_vertex(self, Vertex2D{pos = end + perp * r2, uv = {1, 1}, color = color[2]})
	p4 := append_vertex(self, Vertex2D{pos = end - perp * r2, uv = {0, 1}, color = color[3]})

	// Indices for two triangles
	append_index(self, p1)
	append_index(self, p2)
	append_index(self, p3)
	append_index(self, p1)
	append_index(self, p3)
	append_index(self, p4)
}

draw_rect :: proc(self: ^Renderer_State, pos, size: Vec2, color := WHITE) {
	encoder_ensure_space_basic(self, 4, 6)
	p1 := append_vertex(self, Vertex2D{pos = pos, uv = {0, 0}, color = color})
	p2 := append_vertex(self, Vertex2D{pos = {pos.x + size.x, pos.y}, uv = {1, 0}, color = color})
	p3 := append_vertex(self, Vertex2D{pos = pos + size, uv = {1, 1}, color = color})
	p4 := append_vertex(self, Vertex2D{pos = {pos.x, pos.y + size.y}, uv = {0, 1}, color = color})

	// Indices for two triangles
	append_index(self, p1)
	append_index(self, p2)
	append_index(self, p3)
	append_index(self, p1)
	append_index(self, p3)
	append_index(self, p4)
}


draw_rect_outline :: proc(
	self: ^Renderer_State,
	pos, size: Vec2,
	thickness: f32 = 1.0,
	color := WHITE,
) {
	tr := Vec2{pos.x + size.x, pos.y}
	bl := Vec2{pos.x, pos.y + size.y}
	br := pos + size

	draw_line(self, pos, tr, thickness, color) // Top
	draw_line(self, tr, br, thickness, color) // Right
	draw_line(self, br, bl, thickness, color) // Bottom
	draw_line(self, bl, pos, thickness, color) // Left
}


draw_circle :: proc(
	self: ^Renderer_State,
	center: Vec2,
	radius: f32,
	segments: int = 32,
	color := WHITE,
) {
	encoder_ensure_space_basic(self, segments + 1, segments * 3)
	center_idx := append_vertex(self, Vertex2D{pos = center, uv = {0.5, 0.5}, color = color})

	first_outer_idx: u16
	prev_idx: u16

	for i in 0 ..= segments {
		theta := 2.0 * la.PI * f32(i) / f32(segments)
		pos := center + Vec2{la.cos(theta), la.sin(theta)} * radius
		curr_idx := append_vertex(self, Vertex2D{pos = pos, uv = {0, 0}, color = color})

		if i == 0 {
			first_outer_idx = curr_idx
		} else {
			append_index(self, center_idx)
			append_index(self, prev_idx)
			append_index(self, curr_idx)
		}
		prev_idx = curr_idx
	}
}

draw_soft_circle :: proc(
	self: ^Renderer_State,
	center: Vec2,
	radius: f32,
	color := WHITE,
) {
	inst := SoftInstance {
		color  = color,
		radius = radius,
		data = SoftCircle{ center }
	}
	append_soft_instance(self, inst)
}

draw_soft_capsule :: proc(
	self: ^Renderer_State,
	start, end: Vec2,
	radius: f32,
	color := WHITE,
) {
	inst := SoftInstance {
		color   = color,
		radius  = radius,
		data = SoftCapsule { start, end }
	}
	append_soft_instance(self, inst)
}

draw_soft_rhombus :: proc(
	self: ^Renderer_State,
	start, end: Vec2,
	r_start, r_end: f32,
	color := WHITE,
) {
	inst := SoftInstance {
		color   = color,
		radius  = r_start,
		data = SoftRhombus{start, end, r_end},
	}
	append_soft_instance(self, inst)
}

draw_soft_triangle :: proc(
	self: ^Renderer_State,
	a, b, c: Vec2,
	rounding: f32,
	color := WHITE,
) {
	inst := SoftInstance {
		color    = color,
		radius   = rounding,
		data = SoftTriangle{a, b, c},
	}
	append_soft_instance(self, inst)
}

draw_soft_bezier :: proc(
	self: ^Renderer_State,
	start, control, end: Vec2,
	radius: f32,
	color: Color,
) {
	inst := SoftInstance {
		color  = color,
		radius = radius,
		data = SoftBezier{start, end, control},
	}
	append_soft_instance(self, inst)
}

push_transform :: proc(self: ^Renderer_State, t: Matrix3) {
	append(&self.transform_stack, self.current_transform)
	self.current_transform *= t
}

pop_transform :: proc(self: ^Renderer_State) {
	if transform, ok := pop_safe(&self.transform_stack); ok {
		self.current_transform = transform
	}
}

Camera :: struct {
	target:      Vec2,
	orientation: f32,
	offset:      Vec2,
	zoom:        f32,
}

camera_screen_to_world :: proc(camera: Camera, pos: Vec2) -> (out: Vec2) {
	t := la.inverse(camera_transform(camera))
	return (t * Vec3{pos.x, pos.y, 1}).xy
}

camera_transform :: proc(camera: Camera) -> (t: Matrix3) {
	y_flip: Vec2 = {1, -1}
	t =
		translate(camera.offset) *
		rotate(camera.orientation) *
		scale(camera.zoom) *
		scale(y_flip) *
		translate(-camera.target)
	return
}

// NOTE: This style of function allows us to treat this as a scoped function.
@(deferred_in = rc_end_camera_mode)
camera_mode :: proc(self: ^Renderer_State, camera: Camera) -> (dummy := true) {
	push_transform(self, camera_transform(camera))
	return
}

rc_end_camera_mode :: proc(self: ^Renderer_State, _: Camera) {
	pop_transform(self)
}

translate :: proc(t: Vec2) -> (m: Matrix3) {
	// odinfmt: disable
	return {
		1,  0,  t.x,
		0,  1,  t.y,
		0,  0,  1
	}
	// odinfmt: enable
}
rotate :: proc(theta: f32) -> Matrix3 {
	s, c := math.sincos(theta)
	// odinfmt: disable
	return {
		c, -s,  0,
		s,  c,  0,
		0,  0,  1
	}
	// odinfmt: enable
}
scale :: proc(s: Vec2) -> Matrix3 {
	// odinfmt: disable
	return {
		s.x, 0,   0,
		0,   s.y, 0,
		0,   0,   1,
	}
	// odinfmt: enable
}

// TODO:
// rc_create_render_target :: proc(
// 	using ctx: ^DebugRenderer_Context,
// 	width, height: i32,
// ) -> DebugRenderer_RenderTarget {
// 	// Create and configure the backing texture
// 	tex := wgl.CreateTexture()
// 	{
// 		wgl.BindTexture(wgl.TEXTURE_2D, tex)
// 		defer wgl.BindTexture(wgl.TEXTURE_2D, current_tex)
// 		// Allocate the memory (RGBA, unsigned byte)
// 		wgl.TexImage2D(
// 			wgl.TEXTURE_2D,
// 			0,
// 			wgl.RGBA,
// 			width,
// 			height,
// 			0,
// 			wgl.RGBA,
// 			wgl.UNSIGNED_BYTE,
// 			0,
// 			nil,
// 		)
// 		// Set filters. LINEAR is needed for the metaball thresholding to look smooth.
// 		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_MIN_FILTER, i32(wgl.LINEAR))
// 		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_MAG_FILTER, i32(wgl.LINEAR))
// 		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_WRAP_S, i32(wgl.CLAMP_TO_EDGE))
// 		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_WRAP_T, i32(wgl.CLAMP_TO_EDGE))
// 	}
// 	// Create the Framebuffer and attach the texture
// 	fbo := wgl.CreateFramebuffer()
// 	{
// 		wgl.BindFramebuffer(wgl.FRAMEBUFFER, fbo)
// 		defer wgl.BindFramebuffer(wgl.FRAMEBUFFER, 0)
// 		wgl.FramebufferTexture2D(wgl.FRAMEBUFFER, wgl.COLOR_ATTACHMENT0, wgl.TEXTURE_2D, tex, 0)
// 	}

// 	return {fbo, tex, width, height}
// }
// rc_destroy_render_target :: proc(using target: DebugRenderer_RenderTarget) {
// 	if tex == 0 || fbo == 0 do return
// 	wgl.DeleteTexture(tex)
// 	wgl.DeleteFramebuffer(fbo)
// }
