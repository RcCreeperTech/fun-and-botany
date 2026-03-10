#+feature using-stmt
package web_testing

// TODO: Move all this behind the JS boundary and then remove the load bearing WebGL code

import wgl "WebGL"
import "core:fmt"
import rg "renderer"

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

DebugRenderer_Context :: struct {
	default_tex:                    wgl.Texture, // A 1x1 white pixel texture
	soft_vao:                       wgl.VertexArrayObject,
	soft_vbo:                       wgl.Buffer,
	soft_ibo:                       wgl.Buffer,
	soft_shader:                    wgl.Program,
	soft_composite_shader:          wgl.Program,
	soft_shader_projection_loc:     i32,
	soft_shader_radial_falloff_loc: i32,
	soft_radial_falloff_value:      f32,
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

	// Default texture
	default_tex = wgl.CreateTexture()
	wgl.BindTexture(wgl.TEXTURE_2D, default_tex)

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
			rg.COMMAND_MAX_VERTICES * size_of(Vertex2D),
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
			rg.COMMAND_MAX_INDICES * size_of(u16),
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
		total_instance_size := i32(rg.COMMAND_MAX_INSTANCES * size_of(SoftShape_InstanceData))
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

debug_renderer_flush :: proc(using ctx: ^DebugRenderer_Context, ren: ^rg.Renderer_State) {
	fmt.println("Flushing", ren)
	for pass in ren.passes {
		pass_commands := ren.commands[pass.commands_begin:pass.commands_end]

		if pass.attachment.target == rg.DEFAULT_FRAMEBUFFER {
			wgl.BindFramebuffer(wgl.FRAMEBUFFER, 0)
			wgl.Viewport(0, 0, i32(g_app_state.window_width), i32(g_app_state.window_height))
		} else {
			unimplemented("Need to define a mapping for buffers & textures")
			// wgl.BindFramebuffer(wgl.FRAMEBUFFER, target.fbo)
			// wgl.Viewport(0, 0, target.width, target.height)
		}

		if pass.attachment.clear {
			color := to_fcolor(pass.attachment.color)
			wgl.ClearColor(color.r, color.g, color.b, color.a)
			wgl.Clear(u32(wgl.COLOR_BUFFER_BIT))
		}

		if len(pass_commands) == 0 do continue

		switch pipeline in pass.pipeline {
		case rg.Pipeline_Basic:
			wgl.Disable(wgl.DEPTH_TEST)
			wgl.Enable(wgl.BLEND)
			wgl.BlendEquation(wgl.FUNC_ADD)
			wgl.BlendFunc(wgl.SRC_ALPHA, wgl.ONE_MINUS_SRC_ALPHA)

			wgl.UseProgram(basic_shader)
			wgl.UniformMatrix4fv(basic_shader_projection_loc, pipeline.projection)

			for command in pass_commands {
				cmd := command.(rg.Cmd_Draw_Basic)
				if len(cmd.vertices) == 0 do continue

				wgl.ActiveTexture(wgl.TEXTURE0)
				wgl.BindTexture(wgl.TEXTURE_2D, ctx.default_tex) // FIXME: HANDLE TEXTURES!

				sanitized := make([]Vertex2D, len(cmd.vertices), context.temp_allocator)
				for vert, i in cmd.vertices do sanitized[i] = {vert.pos, vert.uv, to_fcolor(vert.color)}

				wgl.BindBuffer(wgl.ARRAY_BUFFER, ctx.basic_vbo)
				wgl.BufferSubData(
					wgl.ARRAY_BUFFER,
					0,
					i32(len(cmd.vertices) * size_of(Vertex2D)),
					raw_data(sanitized),
				)

				wgl.BindBuffer(wgl.ELEMENT_ARRAY_BUFFER, basic_ibo)
				wgl.BufferSubData(
					wgl.ELEMENT_ARRAY_BUFFER,
					0,
					i32(len(cmd.indices) * size_of(u16)),
					raw_data(cmd.indices),
				)

				wgl.BindVertexArray(basic_vao)
				wgl.DrawElements(wgl.TRIANGLES, i32(len(cmd.indices)), wgl.UNSIGNED_SHORT, nil)
				wgl.BindVertexArray(0)
			}
		case rg.Pipeline_Soft_Shapes:
			wgl.Disable(wgl.DEPTH_TEST)
			wgl.Enable(wgl.BLEND)
			wgl.BlendEquation(wgl.FUNC_ADD)
			wgl.BlendFunc(wgl.ONE, wgl.ONE) // Pure Additive

			wgl.UseProgram(soft_shader)
			wgl.UniformMatrix4fv(soft_shader_projection_loc, pipeline.projection)
			wgl.Uniform1f(soft_shader_radial_falloff_loc, pipeline.radial_falloff)

			for command in pass_commands {
				cmd := command.(rg.Cmd_Draw_Soft)
				if len(cmd.instances) == 0 do continue

				wgl.BindBuffer(wgl.ARRAY_BUFFER, soft_vbo)

				twiddled := make(
					[]SoftShape_InstanceData,
					len(cmd.instances),
					context.temp_allocator,
				)
				for inst, i in cmd.instances {
					switch variant in inst.data {
					case rg.SoftCircle:
						twiddled[i] = SoftShape_InstanceData {
							color = to_fcolor(inst.color),
							radius = inst.radius,
							tag = f32(Soft_Primitive_Type.Circle),
							circle = {center = variant.center},
						}
					case rg.SoftCapsule:
						twiddled[i] = SoftShape_InstanceData {
							color = to_fcolor(inst.color),
							radius = inst.radius,
							tag = f32(Soft_Primitive_Type.Capsule),
							capsule = {start = variant.start, end = variant.end},
						}
					case rg.SoftRhombus:
						twiddled[i] = SoftShape_InstanceData {
							color = to_fcolor(inst.color),
							radius = inst.radius,
							tag = f32(Soft_Primitive_Type.Rhombus),
							rhombus = {start = variant.start, end = variant.end, radius_end = variant.radius_end}
						}
					case rg.SoftTriangle:
						twiddled[i] = SoftShape_InstanceData {
							color = to_fcolor(inst.color),
							radius = inst.radius,
							tag = f32(Soft_Primitive_Type.Triangle),
							triangle = { a = variant.a, b = variant.b, c = variant.c}
						}
					case rg.SoftBezier:
						twiddled[i] = SoftShape_InstanceData {
							color = to_fcolor(inst.color),
							radius = inst.radius,
							tag = f32(Soft_Primitive_Type.Bezier),
							bezier = {a = variant.a, b = variant.b, control = variant.control}
						}
					}
				}

				wgl.BufferSubData(
					wgl.ARRAY_BUFFER,
					0,
					i32(len(cmd.instances) * size_of(SoftShape_InstanceData)),
					raw_data(twiddled),
				)

				wgl.BindVertexArray(soft_vao)
				wgl.DrawElementsInstanced(
					wgl.TRIANGLES,
					6,
					wgl.UNSIGNED_SHORT,
					0,
					i32(len(cmd.instances)),
				)
				wgl.BindVertexArray(0)
			}
		case rg.Pipeline_Soft_Composite:
			unimplemented()
		}
	}
}
