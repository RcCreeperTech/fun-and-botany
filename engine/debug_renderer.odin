#+feature using-stmt
package web_testing

// Question: Should we strip out the implementation here and just export a command buffer for js to fiddle with?
// This will make the API more portable and support the library module approach.
// It will also allow us to nuke the webgpu bindings.
// It might make the implementation slower for native targets if it is forced to
// interact with the command buffer but that is what the sim is speaking right
// now anyways so that code would all need to be rewritten if there is ever some
// magically faster way to do graphicsy stuff...

import wgl "WebGL"
import sm "core:container/small_array"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

Matrix3 :: la.Matrix3x3f32
Vec2 :: [2]f32
Vec3 :: [3]f32

Vertex2D :: struct {
	pos:   Vec2,
	uv:    Vec2,
	color: FColor,
}

Soft_Primitive_Type :: enum u32 {
	Circle   = 0,
	Capsule  = 1,
	Rhombus  = 2, // Tapered Capsule
	Triangle = 3,
	Bezier   = 4,
}

#assert(size_of(SoftShape_InstanceData) == 64)
// NOTE: Remeber to update soft_shapes_instanced shader if this changes
SoftShape_InstanceData :: struct #packed {
	color:         [4]f32,
	tag:           f32, //Soft_Primitive_Type: God I hate glsl shaders. This is a horrible hack
	radius:        f32,
	using variant: struct #raw_union {
		circle:   struct #packed {
			center: Vec2,
		},
		capsule:  struct #packed {
			start, end: Vec2,
		},
		rhombus:  struct #packed {
			start, end: Vec2,
			radius_end: f32,
		},
		triangle: struct #packed {
			a, b, c: Vec2,
		},
		bezier:   struct #packed {
			a, b, control: Vec2,
		},
		raw:      [10]f32,
	},
}

DebugRenderer_RenderTarget :: struct {
	fbo:    wgl.Framebuffer,
	tex:    wgl.Texture,
	width:  i32,
	height: i32,
}

rc_create_render_target :: proc(
	using ctx: ^DebugRenderer_Context,
	width, height: i32,
) -> DebugRenderer_RenderTarget {
	// Create and configure the backing texture
	tex := wgl.CreateTexture()
	{
		wgl.BindTexture(wgl.TEXTURE_2D, tex)
		defer wgl.BindTexture(wgl.TEXTURE_2D, current_tex)
		// Allocate the memory (RGBA, unsigned byte)
		wgl.TexImage2D(
			wgl.TEXTURE_2D,
			0,
			wgl.RGBA,
			width,
			height,
			0,
			wgl.RGBA,
			wgl.UNSIGNED_BYTE,
			0,
			nil,
		)
		// Set filters. LINEAR is needed for the metaball thresholding to look smooth.
		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_MIN_FILTER, i32(wgl.LINEAR))
		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_MAG_FILTER, i32(wgl.LINEAR))
		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_WRAP_S, i32(wgl.CLAMP_TO_EDGE))
		wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_WRAP_T, i32(wgl.CLAMP_TO_EDGE))
	}
	// Create the Framebuffer and attach the texture
	fbo := wgl.CreateFramebuffer()
	{
		wgl.BindFramebuffer(wgl.FRAMEBUFFER, fbo)
		defer wgl.BindFramebuffer(wgl.FRAMEBUFFER, 0)
		wgl.FramebufferTexture2D(wgl.FRAMEBUFFER, wgl.COLOR_ATTACHMENT0, wgl.TEXTURE_2D, tex, 0)
	}

	return {fbo, tex, width, height}
}

rc_destroy_render_target :: proc(using target: DebugRenderer_RenderTarget) {
	if tex == 0 || fbo == 0 do return
	wgl.DeleteTexture(tex)
	wgl.DeleteFramebuffer(fbo)
}

DebugRenderer_Mode :: enum {
	basic,
	soft,
}

MAX_BATCH_VERTICES :: 16384
MAX_BATCH_INDICES :: MAX_BATCH_VERTICES * 2
MAX_BATCH_INSTANCES :: 4096
DebugRenderer_Context :: struct {
	mode:                           DebugRenderer_Mode,
	current_transform:              Matrix3,
	transform_stack:                [dynamic]Matrix3,
	white_tex:                      wgl.Texture, // A 1x1 white pixel texture
	current_tex:                    wgl.Texture,
	ortho_proj:                     la.Matrix4f32,
	soft_shapes:                    sm.Small_Array(MAX_BATCH_INDICES, SoftShape_InstanceData),
	soft_vao:                       wgl.VertexArrayObject,
	soft_vbo:                       wgl.Buffer,
	soft_ibo:                       wgl.Buffer,
	soft_shader:                    wgl.Program,
	soft_composite_shader:          wgl.Program,
	soft_shader_projection_loc:     i32,
	soft_shader_radial_falloff_loc: i32,
	soft_radial_falloff_value:      f32 `ui:"name='Radial Falloff',min=0,max=50"`,
	basic_vertices:                 sm.Small_Array(MAX_BATCH_VERTICES, Vertex2D),
	basic_indices:                  sm.Small_Array(MAX_BATCH_INDICES, u16),
	basic_vao:                      wgl.VertexArrayObject,
	basic_vbo:                      wgl.Buffer,
	basic_ibo:                      wgl.Buffer,
	basic_shader:                   wgl.Program,
	basic_shader_projection_loc:    i32,
}

@(rodata)
BASIC_VERT := #load("./shaders/basic.vert", string)
@(rodata)
BASIC_FRAG := #load("./shaders/basic.frag", string)
@(rodata)
SOFT_SHAPES_INSTANCED_VERT := #load("./shaders/soft_shapes_instanced.vert", string)
@(rodata)
SOFT_SHAPES_INSTANCED_FRAG := #load("./shaders/soft_shapes_instanced.frag", string)
@(rodata)
SOFT_SHAPES_COMPOSITE_FRAG := #load("./shaders/soft_shapes_composite.frag", string)

rc_initialize :: proc(using ctx: ^DebugRenderer_Context) {
	if !init_basic_pipeline(ctx) do fmt.eprintfln("Unable to setup basic pipeline")
	if !init_soft_pipeline(ctx) do fmt.eprintfln("Unable to setup soft pipeline")
	// TODO: new pipeline?
	if s, ok := wgl.CreateProgramFromStrings({BASIC_VERT}, {SOFT_SHAPES_COMPOSITE_FRAG}); ok {
		soft_composite_shader = s
	}

	ctx.current_transform = 1

	// Default texture
	white_tex = wgl.CreateTexture()
	wgl.BindTexture(wgl.TEXTURE_2D, white_tex)

	white_pixel: [4]u8 = 255
	wgl.TexImage2D(
		wgl.TEXTURE_2D,
		0,
		wgl.RGBA,
		1,
		1,
		0,
		wgl.RGBA,
		wgl.UNSIGNED_BYTE,
		4,
		&white_pixel,
	)

	wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_MIN_FILTER, i32(wgl.NEAREST))
	wgl.TexParameteri(wgl.TEXTURE_2D, wgl.TEXTURE_MAG_FILTER, i32(wgl.NEAREST))

	rc_set_mode(ctx, .basic)
	current_tex = white_tex

	init_basic_pipeline :: proc(using ctx: ^DebugRenderer_Context) -> bool {
		basic_shader = wgl.CreateProgramFromStrings({BASIC_VERT}, {BASIC_FRAG}) or_return
		basic_shader_projection_loc = wgl.GetUniformLocation(basic_shader, "u_projection")

		basic_vao = wgl.CreateVertexArray()
		wgl.BindVertexArray(basic_vao)

		// Vertex buffer
		basic_vbo = wgl.CreateBuffer()
		wgl.BindBuffer(wgl.ARRAY_BUFFER, basic_vbo)
		wgl.BufferData(
			wgl.ARRAY_BUFFER,
			MAX_BATCH_VERTICES * size_of(Vertex2D),
			nil,
			wgl.DYNAMIC_DRAW,
		)

		wgl.EnableVertexAttribArray(0)
		wgl.VertexAttribPointer(
			0,
			2,
			wgl.FLOAT,
			false,
			size_of(Vertex2D),
			offset_of(Vertex2D, pos),
		)
		wgl.EnableVertexAttribArray(1)
		wgl.VertexAttribPointer(1, 2, wgl.FLOAT, false, size_of(Vertex2D), offset_of(Vertex2D, uv))
		wgl.EnableVertexAttribArray(2)
		wgl.VertexAttribPointer(
			2,
			4,
			wgl.FLOAT,
			false,
			size_of(Vertex2D),
			offset_of(Vertex2D, color),
		)

		// Index buffer
		basic_ibo = wgl.CreateBuffer()
		wgl.BindBuffer(wgl.ELEMENT_ARRAY_BUFFER, basic_ibo)
		wgl.BufferData(
			wgl.ELEMENT_ARRAY_BUFFER,
			MAX_BATCH_INDICES * size_of(u16),
			nil,
			wgl.DYNAMIC_DRAW,
		)

		wgl.BindVertexArray(0)
		wgl.BindBuffer(wgl.ELEMENT_ARRAY_BUFFER, 0)
		wgl.BindBuffer(wgl.ARRAY_BUFFER, 0)
		return true
	}

	init_soft_pipeline :: proc(using ctx: ^DebugRenderer_Context) -> bool {
		// Setup shader
		//
		soft_shader = wgl.CreateProgramFromStrings(
			{SOFT_SHAPES_INSTANCED_VERT},
			{SOFT_SHAPES_INSTANCED_FRAG},
		) or_return
		soft_shader_projection_loc = wgl.GetUniformLocation(soft_shader, "u_projection")
		soft_shader_radial_falloff_loc = wgl.GetUniformLocation(soft_shader, "u_radial_falloff")
		soft_radial_falloff_value = 10 // Default value

		soft_vao = wgl.CreateVertexArray()
		wgl.BindVertexArray(soft_vao)
		// Push static quad buffers
		unit_quad_verts := [4]Vec2{{-0.5, -0.5}, {0.5, -0.5}, {0.5, 0.5}, {-0.5, 0.5}}
		quad_vbo := wgl.CreateBuffer()
		wgl.BindBuffer(wgl.ARRAY_BUFFER, quad_vbo)
		wgl.BufferData(
			wgl.ARRAY_BUFFER,
			size_of(unit_quad_verts),
			&unit_quad_verts,
			wgl.STATIC_DRAW,
		)
		// Attribute Location 0: a_unit_pos
		wgl.EnableVertexAttribArray(0)
		wgl.VertexAttribPointer(0, 2, wgl.FLOAT, false, 0, 0)
		// Setup Static Indices
		unit_quad_indices := [6]u16{0, 1, 2, 0, 2, 3}
		soft_ibo = wgl.CreateBuffer()
		wgl.BindBuffer(wgl.ELEMENT_ARRAY_BUFFER, soft_ibo)
		wgl.BufferData(
			wgl.ELEMENT_ARRAY_BUFFER,
			size_of(unit_quad_indices),
			&unit_quad_indices,
			wgl.STATIC_DRAW,
		)

		// Setup the Instance VBO (Dynamic Data)
		soft_vbo = wgl.CreateBuffer()
		wgl.BindBuffer(wgl.ARRAY_BUFFER, soft_vbo)

		// Pre-allocate the GPU buffer with enough space for MAX_INSTANCES
		total_instance_size := i32(MAX_BATCH_INSTANCES * size_of(SoftShape_InstanceData))
		wgl.BufferData(wgl.ARRAY_BUFFER, total_instance_size, nil, wgl.DYNAMIC_DRAW)

		// Configure Instanced Attribute Pointers
		stride := i32(size_of(SoftShape_InstanceData))
		for i in 1 ..= 4 {
			wgl.EnableVertexAttribArray(i32(i))
			wgl.VertexAttribPointer(i32(i), 4, wgl.FLOAT, false, stride, uintptr(16 * (i - 1)))
			wgl.VertexAttribDivisor(u32(i), 1) // 1 means update per instance
		}

		wgl.BindVertexArray(0)
		wgl.BindBuffer(wgl.ELEMENT_ARRAY_BUFFER, 0)
		wgl.BindBuffer(wgl.ARRAY_BUFFER, 0)
		return true
	}
}

rc_set_render_target :: proc(
	using ctx: ^DebugRenderer_Context,
	target: Maybe(DebugRenderer_RenderTarget) = nil,
) {
	rc_flush(ctx) // Flush anything that was using the old render target
	if target, ok := target.?; ok {
		wgl.BindFramebuffer(wgl.FRAMEBUFFER, target.fbo)
		wgl.Viewport(0, 0, target.width, target.height)
	} else {
		wgl.BindFramebuffer(wgl.FRAMEBUFFER, 0)
		wgl.Viewport(0, 0, g_app_state.window_width, g_app_state.window_height)
	}
}

rc_set_current_texture :: proc(
	using ctx: ^DebugRenderer_Context,
	texture: Maybe(wgl.Texture) = nil,
) {
	rc_flush(ctx) // Flush anything that was using the old texture
	current_tex = texture.? or_else white_tex
}

rc_set_mode :: proc(using ctx: ^DebugRenderer_Context, new_mode: DebugRenderer_Mode = .basic) {
	rc_flush(ctx) // Flush anything that was using the mode
	mode = new_mode
	switch mode {
	case .soft:
		wgl.Disable(wgl.DEPTH_TEST)
		wgl.Enable(wgl.BLEND)
		wgl.BlendEquation(wgl.FUNC_ADD)
		wgl.BlendFunc(wgl.ONE, wgl.ONE) // Pure Additive
		wgl.UseProgram(soft_shader)
	case .basic:
		wgl.Disable(wgl.DEPTH_TEST)
		wgl.Enable(wgl.BLEND)
		wgl.BlendEquation(wgl.FUNC_ADD)
		wgl.BlendFunc(wgl.SRC_ALPHA, wgl.ONE_MINUS_SRC_ALPHA)
		wgl.UseProgram(basic_shader)
	}
}

rc_clear :: proc(_: ^DebugRenderer_Context, color: Color) {
	fc := to_fcolor(color)
	wgl.ClearColor(fc.r, fc.g, fc.b, fc.a)
	wgl.Clear(auto_cast wgl.COLOR_BUFFER_BIT)
}

rc_flush :: proc(using ctx: ^DebugRenderer_Context) {
	switch mode {
	case .basic:
		if basic_vertices.len == 0 do return

		wgl.BindBuffer(wgl.ARRAY_BUFFER, basic_vbo)
		wgl.BufferSubData(
			wgl.ARRAY_BUFFER,
			0,
			i32(basic_vertices.len * size_of(Vertex2D)),
			&basic_vertices.data,
		)

		wgl.BindBuffer(wgl.ELEMENT_ARRAY_BUFFER, basic_ibo)
		wgl.BufferSubData(
			wgl.ELEMENT_ARRAY_BUFFER,
			0,
			i32(basic_indices.len * size_of(u16)),
			&basic_indices.data,
		)

		wgl.UniformMatrix4fv(basic_shader_projection_loc, ortho_proj)

		wgl.ActiveTexture(wgl.TEXTURE0)
		wgl.BindTexture(wgl.TEXTURE_2D, current_tex)

		wgl.BindVertexArray(basic_vao)
		wgl.DrawElements(wgl.TRIANGLES, i32(basic_indices.len), wgl.UNSIGNED_SHORT, nil)
		wgl.BindVertexArray(0)


		sm.clear(&basic_vertices)
		sm.clear(&basic_indices)

	case .soft:
		if soft_shapes.len == 0 do return

		wgl.UniformMatrix4fv(soft_shader_projection_loc, ortho_proj)
		wgl.Uniform1f(soft_shader_radial_falloff_loc, soft_radial_falloff_value)

		wgl.BindBuffer(wgl.ARRAY_BUFFER, soft_vbo)
		wgl.BufferSubData(
			wgl.ARRAY_BUFFER,
			0,
			i32(soft_shapes.len * size_of(SoftShape_InstanceData)),
			&soft_shapes.data,
		)

		wgl.BindVertexArray(soft_vao)
		wgl.DrawElementsInstanced(wgl.TRIANGLES, 6, wgl.UNSIGNED_SHORT, 0, i32(soft_shapes.len))
		wgl.BindVertexArray(0)

		sm.clear(&soft_shapes)
	}

}

rc_ensure_space :: proc(using ctx: ^DebugRenderer_Context, vertices, indices: int) {
	vertex_overflow := sm.len(basic_vertices) + vertices >= MAX_BATCH_VERTICES
	index_overflow := sm.len(basic_indices) + indices >= MAX_BATCH_INDICES
	if vertex_overflow || index_overflow {
		rc_flush(ctx)
	}
}

rc_append_vertex :: proc(using ctx: ^DebugRenderer_Context, vert: Vertex2D) -> u16 {
	assert(
		mode == .basic,
		"Drawing basic primitive shapes requires the renderer to be in basic mode",
	)
	idx := basic_vertices.len
	vert := vert
	vert.pos = (ctx.current_transform * Vec3{vert.pos.x, vert.pos.y, 1}).xy
	if !sm.append(&basic_vertices, vert) {
		fmt.eprintfln("Failed to append to vertex buffer!")
	}
	return u16(idx)
}

rc_append_index :: proc(using ctx: ^DebugRenderer_Context, idx: u16) {
	assert(
		mode == .basic,
		"Drawing basic primitive shapes requires the renderer to be in basic mode",
	)
	if !sm.append(&basic_indices, idx) {
		fmt.eprintfln("Failed to append to index buffer!")
	}
}

rc_append_instance :: proc(using ctx: ^DebugRenderer_Context, data: SoftShape_InstanceData) {
	assert(mode == .soft, "Drawing soft shapes requires the renderer to be in soft mode")
	if !sm.append(&soft_shapes, data) {
		rc_flush(ctx)
		sm.append(&soft_shapes, data)
	}
}

rc_append :: proc {
	rc_append_vertex,
	rc_append_index,
	rc_append_instance,
}

rc_draw_line :: proc(
	using ctx: ^DebugRenderer_Context,
	start, end: Vec2,
	thickness: f32 = 10.0,
	color := WHITE,
) {
	rc_ensure_space(ctx, 4, 6)
	// Calculate perpendicular vector for thickness
	dir := end - start
	perp := la.normalize0(la.orthogonal(dir)) * thickness * 0.5

	// 4 corners of the line segment
	color := to_fcolor(color)
	p1 := rc_append(ctx, Vertex2D{pos = start - perp, uv = {0, 0}, color = color})
	p2 := rc_append(ctx, Vertex2D{pos = start + perp, uv = {1, 0}, color = color})
	p3 := rc_append(ctx, Vertex2D{pos = end - perp, uv = {0, 1}, color = color})
	p4 := rc_append(ctx, Vertex2D{pos = end + perp, uv = {1, 1}, color = color})

	// Push 2 triangles to the batch
	rc_append(ctx, p1)
	rc_append(ctx, p2)
	rc_append(ctx, p4)
	rc_append(ctx, p1)
	rc_append(ctx, p4)
	rc_append(ctx, p3)
}

rc_draw_wedge :: proc(
	using ctx: ^DebugRenderer_Context,
	start, end: Vec2,
	r1, r2: f32,
	color: [4]Color = WHITE,
) {
	rc_ensure_space(ctx, 4, 6)
	fcolors: [4]FColor
	for c, i in color do fcolors[i] = to_fcolor(c)

	ab := la.normalize0(end - start)
	perp := Vec2{-ab.y, ab.x}

	p1 := rc_append(ctx, Vertex2D{pos = start - perp * r1, uv = {0, 0}, color = fcolors[0]})
	p2 := rc_append(ctx, Vertex2D{pos = start + perp * r1, uv = {1, 0}, color = fcolors[1]})
	p3 := rc_append(ctx, Vertex2D{pos = end + perp * r2, uv = {1, 1}, color = fcolors[2]})
	p4 := rc_append(ctx, Vertex2D{pos = end - perp * r2, uv = {0, 1}, color = fcolors[3]})

	// Indices for two triangles
	rc_append(ctx, p1)
	rc_append(ctx, p2)
	rc_append(ctx, p3)
	rc_append(ctx, p1)
	rc_append(ctx, p3)
	rc_append(ctx, p4)
}

rc_draw_rect :: proc(using ctx: ^DebugRenderer_Context, pos, size: Vec2, color := WHITE) {
	rc_ensure_space(ctx, 4, 6)
	color := to_fcolor(color)
	p1 := rc_append(ctx, Vertex2D{pos = pos, uv = {0, 0}, color = color})
	p2 := rc_append(ctx, Vertex2D{pos = {pos.x + size.x, pos.y}, uv = {1, 0}, color = color})
	p3 := rc_append(ctx, Vertex2D{pos = pos + size, uv = {1, 1}, color = color})
	p4 := rc_append(ctx, Vertex2D{pos = {pos.x, pos.y + size.y}, uv = {0, 1}, color = color})

	// Indices for two triangles
	rc_append(ctx, p1)
	rc_append(ctx, p2)
	rc_append(ctx, p3)
	rc_append(ctx, p1)
	rc_append(ctx, p3)
	rc_append(ctx, p4)
}

rc_draw_rect_outline :: proc(
	using ctx: ^DebugRenderer_Context,
	pos, size: Vec2,
	thickness: f32 = 1.0,
	color := WHITE,
) {
	tr := Vec2{pos.x + size.x, pos.y}
	bl := Vec2{pos.x, pos.y + size.y}
	br := pos + size

	rc_draw_line(ctx, pos, tr, thickness, color) // Top
	rc_draw_line(ctx, tr, br, thickness, color) // Right
	rc_draw_line(ctx, br, bl, thickness, color) // Bottom
	rc_draw_line(ctx, bl, pos, thickness, color) // Left
}

rc_draw_circle :: proc(
	using ctx: ^DebugRenderer_Context,
	center: Vec2,
	radius: f32,
	segments: int = 32,
	color := WHITE,
) {
	rc_ensure_space(ctx, segments + 1, segments * 3)
	color := to_fcolor(color)
	center_idx := rc_append(ctx, Vertex2D{pos = center, uv = {0.5, 0.5}, color = color})

	first_outer_idx: u16
	prev_idx: u16

	for i in 0 ..= segments {
		theta := 2.0 * la.PI * f32(i) / f32(segments)
		pos := center + Vec2{la.cos(theta), la.sin(theta)} * radius
		curr_idx := rc_append(ctx, Vertex2D{pos = pos, uv = {0, 0}, color = color})

		if i == 0 {
			first_outer_idx = curr_idx
		} else {
			rc_append(ctx, center_idx)
			rc_append(ctx, prev_idx)
			rc_append(ctx, curr_idx)
		}
		prev_idx = curr_idx
	}
}

rc_draw_soft_circle :: proc(
	ctx: ^DebugRenderer_Context,
	center: Vec2,
	radius: f32,
	color := WHITE,
) {
	color := to_fcolor(color)
	inst := SoftShape_InstanceData {
		color  = color,
		tag    = f32(Soft_Primitive_Type.Circle),
		radius = radius,
		circle = {center},
	}
	rc_append(ctx, inst)
}

rc_draw_soft_capsule :: proc(
	ctx: ^DebugRenderer_Context,
	start, end: Vec2,
	radius: f32,
	color := WHITE,
) {
	color := to_fcolor(color)
	inst := SoftShape_InstanceData {
		color   = color,
		tag     = f32(Soft_Primitive_Type.Capsule),
		radius  = radius,
		capsule = {start, end},
	}
	rc_append(ctx, inst)
}

rc_draw_soft_rhombus :: proc(
	ctx: ^DebugRenderer_Context,
	start, end: Vec2,
	r_start, r_end: f32,
	color := WHITE,
) {
	color := to_fcolor(color)
	inst := SoftShape_InstanceData {
		color   = color,
		tag     = f32(Soft_Primitive_Type.Rhombus),
		radius  = r_start,
		rhombus = {start, end, r_end},
	}
	rc_append(ctx, inst)
}

rc_draw_soft_triangle :: proc(
	ctx: ^DebugRenderer_Context,
	a, b, c: Vec2,
	rounding: f32,
	color: [4]f32,
) {
	inst := SoftShape_InstanceData {
		color    = color,
		tag      = f32(Soft_Primitive_Type.Triangle),
		radius   = rounding,
		triangle = {a, b, c},
	}
	rc_append(ctx, inst)
}

draw_soft_bezier :: proc(
	ctx: ^DebugRenderer_Context,
	start, control, end: Vec2,
	radius: f32,
	color: [4]f32,
) {
	inst := SoftShape_InstanceData {
		color  = color,
		tag    = f32(Soft_Primitive_Type.Bezier),
		radius = radius,
		bezier = {start, end, control},
	}
	rc_append(ctx, inst)
}

rc_push_transform :: proc(using ctx: ^DebugRenderer_Context) {
	append(&transform_stack, current_transform)
}
rc_pop_transform :: proc(using ctx: ^DebugRenderer_Context) {
	if transform, ok := pop_safe(&transform_stack); ok {
		current_transform = transform
	}
}

Camera :: struct {
	target:      Vec2,
	orientation: f32,
	offset:      Vec2,
	zoom:        f32,
}

camera_screen_to_world :: proc(using camera: Camera, pos: Vec2) -> (out: Vec2) {
	t := la.inverse(camera_transform(camera))
	return (t * Vec3{pos.x, pos.y, 1}).xy
}

camera_transform :: proc(using camera: Camera) -> (t: Matrix3) {
	y_flip: Vec2 = {1, -1}
	t =
		translate(offset) *
		rotate(orientation) *
		scale(auto_cast g_app_state.dpr) *
		scale(zoom) *
		scale(y_flip) *
		translate(-target)
	return
}

// NOTE: This style of function allows us to treat this as a scoped function.
@(deferred_none = rc_end_camera_mode)
rc_camera_mode :: proc(using camera: Camera) -> (dummy := true) {
	rc_push_transform(&g_app_state.rc)
	g_app_state.rc.current_transform *= camera_transform(camera)
	return
}

rc_end_camera_mode :: proc() {
	rc_pop_transform(&g_app_state.rc)
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
