#+feature using-stmt
package engine

import "core:log"
import wgl "WebGL"
import "base:runtime"
import hm "core:container/handle_map"
import "core:fmt"
import "core:math"
import la "core:math/linalg"
import rg "renderer"
import b2 "vendor:box2d"

import pvm "../vm"

BOX2D_DEBUG_DRAW :: false
SIM_GROUND_THICKNESS :: 200
SIM_MAX_DEPTH :: 8

ApplicationState :: struct {
	cumulative_time:          f64,
	window_width:             i32,
	window_height:            i32,
	dpr:                      f64,
	ortho_proj:               la.Matrix4f32,
	r:                        rg.Renderer_State,
	elements:                 ElementMap,
	root_element:             Handle,
	camera:                   rg.Camera,
	debug_rc:                 DebugRenderer_Context,
	physics_world:            b2.WorldId,
	physics_world_debug_draw: b2.DebugDraw,
	ctx:                      runtime.Context,
	ground:                   b2.BodyId,
	vm: 					  pvm.VM,
	loaded_program: 		  pvm.Program,
}

// TODO: @(private="file")
g_app_state: ApplicationState

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(opt = {
			.Level,
			.Terminal_Color,
			.Short_File_Path,
			.Line,
			.Procedure,
		})
	}

	app := &g_app_state

	app.ctx = context
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

	rg.init(&app.r, context.allocator)
	rc_initialize(&app.debug_rc)
	when BOX2D_DEBUG_DRAW {
		setup_box2d_debug_draw_vtable(app)
	}

	app.camera = rg.Camera {
		zoom = SIM_PIXELS_PER_METER,
	}

	{
		world_def := b2.DefaultWorldDef()
		world_def.gravity = {0, -9.81}
		world_def.enableSleep = false
		world_def.enableContinuous = false
		app.physics_world = b2.CreateWorld(world_def)
	}

	{
		box := b2.MakeBox(SIM_GROUND_THICKNESS / 2, SIM_GROUND_THICKNESS / 2)
		shape_def := b2.DefaultShapeDef()
		shape_def.filter.categoryBits = u64(Collision_Categories.Ground)
		body_def := b2.DefaultBodyDef()
		body_def.position = {0, -SIM_GROUND_THICKNESS / 2}
		body_def.type = .staticBody
		app.ground = b2.CreateBody(app.physics_world, body_def)
		_ = b2.CreatePolygonShape(app.ground, shape_def, box)
	}

	root := Sim_Element {
		color            = DARKGREEN,
		target_color     = DARKGREEN,
		growth_rate      = SIM_BASELINE_GROWTH_RATE,
		target_length    = 1,
		target_thickness = 0.4,
	}

	{
		shape_def := b2.DefaultShapeDef()
		shape_def.density = WOOD_TISSUE.density
		shape_def.filter.categoryBits = u64(Collision_Categories.Element)
		shape_def.filter.maskBits = u64(Collision_Categories.Ground)
		body_def := b2.DefaultBodyDef()
		body_def.type = .dynamicBody
		root.body = b2.CreateBody(app.physics_world, body_def)
		root.shape = b2.CreateCapsuleShape(root.body, shape_def, {})
	}

	{
		joint_def := b2.DefaultRevoluteJointDef()
		when BOX2D_DEBUG_DRAW do joint_def.drawSize = 0.08
		joint_def.bodyIdA = app.ground
		joint_def.bodyIdB = root.body
		joint_def.localAnchorA = {0, SIM_GROUND_THICKNESS / 2}
		joint_def.localAnchorB = 0
		joint_def.targetAngle = 0
		joint_def.enableSpring = true
		joint_def.hertz = WOOD_TISSUE.freq
		joint_def.dampingRatio = WOOD_TISSUE.damping
		joint_def.collideConnected = false
		root.joint = b2.CreateRevoluteJoint(app.physics_world, joint_def)
	}

	app.root_element = hm.add(&app.elements, root)

	context.logger.lowest_level = .Error
	source: string = #load("../vm/test_cases/plant_test_code.asm")
	assembler: pvm.Assembler
	pvm.asm_init(&assembler)
	prog, err := pvm.asm_assemble(&assembler, source)
	assert(err == nil)
	app.loaded_program = prog
	context.logger.lowest_level = .Debug

	pvm.init_vm(&app.vm, {
		get_entrypoint = vm_get_entrypoint,
		get_param = vm_get_param,
		set_param = vm_set_param,
		spawn_element = vm_spawn_element,
	})
}

@(export)
step :: proc(delta_time: f64) -> (keep_going: bool) {
	app := &g_app_state
	context = app.ctx
	free_all(context.temp_allocator)
	app.cumulative_time += delta_time
	// Reset after 1 hour (3600 seconds) to stay in high-precision range
	if app.cumulative_time > 3600 {
		app.cumulative_time = 0
	}

	center := window_center()

	sim_update(app, f32(delta_time))
	sim_render(app, f32(delta_time))

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

	debug_renderer_flush(&g_app_state.debug_rc, &g_app_state.r)

	return true
}

@(export)
window_resize :: proc(css_width, css_height, dpr: f64) {
	phys_w, phys_h := i32(css_width * dpr), i32(css_height * dpr)
	g_app_state.window_width = i32(phys_w)
	g_app_state.window_height = i32(phys_h)
	g_app_state.dpr = dpr

	g_app_state.ortho_proj = la.matrix_ortho3d_f32(0, f32(css_width), f32(css_height), 0, -1, 1)
	g_app_state.camera = rg.Camera {
		zoom   = SIM_PIXELS_PER_METER,
		offset = Vec2{f32(css_width), f32(css_height)} * 0.5,
	}

	wgl.Viewport(0, 0, phys_w, phys_h)
}

window_center :: proc() -> Vec2 {
	return Vec2{cast(f32)g_app_state.window_width, cast(f32)g_app_state.window_height} * 0.5
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

setup_box2d_debug_draw_vtable :: proc(app: ^ApplicationState) {
	dbg := &app.physics_world_debug_draw
	dbg^ = b2.DefaultDebugDraw()
	dbg.drawShapes = true
	dbg.drawJoints = false
	dbg.drawJointExtras = false
	dbg.userContext = app
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
