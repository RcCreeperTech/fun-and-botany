#+build !js
package webgl

import glm "core:math/linalg/glsl"

Enum :: distinct u32

Buffer :: distinct u32
Framebuffer :: distinct u32
Program :: distinct u32
Renderbuffer :: distinct u32
Shader :: distinct u32
Texture :: distinct u32

ContextAttribute :: enum u32 {
	disableAlpha                 = 0,
	disableAntialias             = 1,
	disableDepth                 = 2,
	failIfMajorPerformanceCaveat = 3,
	disablePremultipliedAlpha    = 4,
	preserveDrawingBuffer        = 5,
	stencil                      = 6,
	desynchronized               = 7,
}
ContextAttributes :: distinct bit_set[ContextAttribute;u32]

CreateCurrentContextById :: proc(name: string, attributes: ContextAttributes) -> bool {return {}}
SetCurrentContextById :: proc(name: string) -> bool {return {}}
GetCurrentContextAttributes :: proc() -> ContextAttributes {return {}}
DrawingBufferWidth :: proc() -> i32 {return 0}
DrawingBufferHeight :: proc() -> i32 {return 0}
GetWebGLVersion :: proc(major, minor: ^i32) {}
GetESVersion :: proc(major, minor: ^i32) {}
GetError :: proc() -> Enum {return {}}
IsExtensionSupported :: proc(name: string) -> bool {return {}}
ActiveTexture :: proc(x: Enum) {}
AttachShader :: proc(program: Program, shader: Shader) {}
BindAttribLocation :: proc(program: Program, index: i32, name: string) {}
BindBuffer :: proc(target: Enum, buffer: Buffer) {}
BindFramebuffer :: proc(target: Enum, framebuffer: Framebuffer) {}
BindTexture :: proc(target: Enum, texture: Texture) {}
BindRenderbuffer :: proc(target: Enum, renderbuffer: Renderbuffer) {}
BlendColor :: proc(red, green, blue, alpha: f32) {}
BlendEquation :: proc(mode: Enum) {}
BlendEquationSeparate :: proc(modeRGB: Enum, modeAlpha: Enum) {}
BlendFunc :: proc(sfactor, dfactor: Enum) {}
BlendFuncSeparate :: proc(srcRGB, dstRGB, srcAlpha, dstAlpha: Enum) {}
BufferData :: proc(target: Enum, size: i32, data: rawptr, usage: Enum) {}
BufferSubData :: proc(target: Enum, offset: uintptr, size: i32, data: rawptr) {}
Clear :: proc(bits: u32) {}
ClearColor :: proc(r, g, b, a: f32) {}
ClearDepth :: proc(x: f32) {}
ClearStencil :: proc(x: i32) {}
ColorMask :: proc(r, g, b, a: bool) {}
CompileShader :: proc(shader: Shader) {}
CompressedTexImage2D :: proc(
	target: Enum,
	level: i32,
	internalformat: Enum,
	width, height: i32,
	border: i32,
	imageSize: i32,
	data: rawptr,
) {}
CompressedTexSubImage2D :: proc(
	target: Enum,
	level: i32,
	xoffset, yoffset, width, height: i32,
	format: Enum,
	imageSize: i32,
	data: rawptr,
) {}
CopyTexImage2D :: proc(
	target: Enum,
	level: i32,
	internalformat: Enum,
	x, y, width, height: i32,
	border: i32,
) {}
CopyTexSubImage2D :: proc(
	target: Enum,
	level: i32,
	xoffset, yoffset, x, y: i32,
	width, height: i32,
) {}
CreateBuffer :: proc() -> Buffer {return {}}
CreateFramebuffer :: proc() -> Framebuffer {return {}}
CreateProgram :: proc() -> Program {return {}}
CreateRenderbuffer :: proc() -> Renderbuffer {return {}}
CreateShader :: proc(shaderType: Enum) -> Shader {return {}}
CreateTexture :: proc() -> Texture {return {}}
CullFace :: proc(mode: Enum) {}
DeleteBuffer :: proc(buffer: Buffer) {}
DeleteFramebuffer :: proc(framebuffer: Framebuffer) {}
DeleteProgram :: proc(program: Program) {}
DeleteRenderbuffer :: proc(renderbuffer: Renderbuffer) {}
DeleteShader :: proc(shader: Shader) {}
DeleteTexture :: proc(texture: Texture) {}
DepthFunc :: proc(func: Enum) {}
DepthMask :: proc(flag: bool) {}
DepthRange :: proc(zNear, zFar: f32) {}
DetachShader :: proc(program: Program, shader: Shader) {}
Disable :: proc(cap: Enum) {}
DisableVertexAttribArray :: proc(index: i32) {}
DrawArrays :: proc(mode: Enum, first, count: i32) {}
DrawElements :: proc(mode: Enum, count: i32, type: Enum, indices: rawptr) {}
Enable :: proc(cap: Enum) {}
EnableVertexAttribArray :: proc(index: i32) {}
Finish :: proc() {}
Flush :: proc() {}
FramebufferRenderbuffer :: proc(
	target, attachment, renderbufertarget: Enum,
	renderbuffer: Renderbuffer,
) {}
FramebufferTexture2D :: proc(target, attachment, textarget: Enum, texture: Texture, level: i32) {}
FrontFace :: proc(mode: Enum) {}
GenerateMipmap :: proc(target: Enum) {}
GetAttribLocation :: proc(program: Program, name: string) -> i32 {return {}}
GetUniformLocation :: proc(program: Program, name: string) -> i32 {return {}}
GetVertexAttribOffset :: proc(index: i32, pname: Enum) -> uintptr {return {}}
GetProgramParameter :: proc(program: Program, pname: Enum) -> i32 {return {}}
GetParameter :: proc(pname: Enum) -> i32 {return {}}
GetParameter4i :: proc(pname: Enum, v0, v1, v2, v4: ^i32) {}
Hint :: proc(target: Enum, mode: Enum) {}
IsBuffer :: proc(buffer: Buffer) -> bool {return {}}
IsEnabled :: proc(cap: Enum) -> bool {return {}}
IsFramebuffer :: proc(framebuffer: Framebuffer) -> bool {return {}}
IsProgram :: proc(program: Program) -> bool {return {}}
IsRenderbuffer :: proc(renderbuffer: Renderbuffer) -> bool {return {}}
IsShader :: proc(shader: Shader) -> bool {return {}}
IsTexture :: proc(texture: Texture) -> bool {return {}}
LineWidth :: proc(width: f32) {}
LinkProgram :: proc(program: Program) {}
PixelStorei :: proc(pname: Enum, param: i32) {}
PolygonOffset :: proc(factor: f32, units: f32) {}
ReadnPixels :: proc(
	x, y, width, height: i32,
	format: Enum,
	type: Enum,
	bufSize: i32,
	data: rawptr,
) {}
RenderbufferStorage :: proc(target: Enum, internalformat: Enum, width, height: i32) {}
SampleCoverage :: proc(value: f32, invert: bool) {}
Scissor :: proc(x, y, width, height: i32) {}
ShaderSource :: proc(shader: Shader, strings: []string) {}
StencilFunc :: proc(func: Enum, ref: i32, mask: u32) {}
StencilFuncSeparate :: proc(face, func: Enum, ref: i32, mask: u32) {}
StencilMask :: proc(mask: u32) {}
StencilMaskSeparate :: proc(face: Enum, mask: u32) {}
StencilOp :: proc(fail, zfail, zpass: Enum) {}
StencilOpSeparate :: proc(face, fail, zfail, zpass: Enum) {}
TexImage2D :: proc(
	target: Enum,
	level: i32,
	internalformat: Enum,
	width, height: i32,
	border: i32,
	format, type: Enum,
	size: i32,
	data: rawptr,
) {}
TexSubImage2D :: proc(
	target: Enum,
	level: i32,
	xoffset, yoffset, width, height: i32,
	format, type: Enum,
	size: i32,
	data: rawptr,
) {}
TexParameterf :: proc(target, pname: Enum, param: f32) {}
TexParameteri :: proc(target, pname: Enum, param: i32) {}
Uniform1f :: proc(location: i32, v0: f32) {}
Uniform2f :: proc(location: i32, v0, v1: f32) {}
Uniform3f :: proc(location: i32, v0, v1, v2: f32) {}
Uniform4f :: proc(location: i32, v0, v1, v2, v3: f32) {}
Uniform1i :: proc(location: i32, v0: i32) {}
Uniform2i :: proc(location: i32, v0, v1: i32) {}
Uniform3i :: proc(location: i32, v0, v1, v2: i32) {}
Uniform4i :: proc(location: i32, v0, v1, v2, v3: i32) {}
UseProgram :: proc(program: Program) {}
ValidateProgram :: proc(program: Program) {}
VertexAttrib1f :: proc(index: i32, x: f32) {}
VertexAttrib2f :: proc(index: i32, x, y: f32) {}
VertexAttrib3f :: proc(index: i32, x, y, z: f32) {}
VertexAttrib4f :: proc(index: i32, x, y, z, w: f32) {}
VertexAttribPointer :: proc(
	index: i32,
	size: i32,
	type: Enum,
	normalized: bool,
	stride: i32,
	ptr: uintptr,
) {}
Viewport :: proc(x, y, w, h: i32) {}


Uniform1fv :: proc "contextless" (location: i32, v: []f32) {}
Uniform2fv :: proc "contextless" (location: i32, v: []glm.vec2) {}
Uniform3fv :: proc "contextless" (location: i32, v: []glm.vec3) {}
Uniform4fv :: proc "contextless" (location: i32, v: []glm.vec4) {}
Uniform1iv :: proc "contextless" (location: i32, v: []i32) {}
Uniform2iv :: proc "contextless" (location: i32, v: []glm.ivec2) {}
Uniform3iv :: proc "contextless" (location: i32, v: []glm.ivec3) {}
Uniform4iv :: proc "contextless" (location: i32, v: []glm.ivec4) {}

VertexAttrib1fv :: proc "contextless" (index: i32, v: f32) {}
VertexAttrib2fv :: proc "contextless" (index: i32, v: glm.vec2) {}
VertexAttrib3fv :: proc "contextless" (index: i32, v: glm.vec3) {}
VertexAttrib4fv :: proc "contextless" (index: i32, v: glm.vec4) {}

UniformMatrix2fv :: proc "contextless" (location: i32, m: glm.mat2) {}
UniformMatrix3fv :: proc "contextless" (location: i32, m: glm.mat3) {}
UniformMatrix4fv :: proc "contextless" (location: i32, m: glm.mat4) {}

GetShaderiv :: proc "contextless" (shader: Shader, pname: Enum) -> (p: i32) {return {}}
GetProgramInfoLog :: proc "contextless" (program: Program, buf: []byte) -> string {return {}}
GetShaderInfoLog :: proc "contextless" (shader: Shader, buf: []byte) -> string {return {}}


BufferDataSlice :: proc "contextless" (target: Enum, slice: $S/[]$E, usage: Enum) {}
BufferSubDataSlice :: proc "contextless" (target: Enum, offset: uintptr, slice: $S/[]$E) {}
CompressedTexImage2DSlice :: proc "contextless" (
	target: Enum,
	level: i32,
	internalformat: Enum,
	width, height: i32,
	border: i32,
	slice: $S/[]$E,
) {}
CompressedTexSubImage2DSlice :: proc "contextless" (
	target: Enum,
	level: i32,
	xoffset, yoffset, width, height: i32,
	format: Enum,
	slice: $S/[]$E,
) {}

ReadPixelsSlice :: proc "contextless" (
	x, y, width, height: i32,
	format: Enum,
	type: Enum,
	slice: $S/[]$E,
) {}

TexImage2DSlice :: proc "contextless" (
	target: Enum,
	level: i32,
	internalformat: Enum,
	width, height: i32,
	border: i32,
	format, type: Enum,
	slice: $S/[]$E,
) {}
TexSubImage2DSlice :: proc "contextless" (
	target: Enum,
	level: i32,
	xoffset, yoffset, width, height: i32,
	format, type: Enum,
	slice: $S/[]$E,
) {}
