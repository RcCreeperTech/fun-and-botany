#+build !js
package webgl

import glm "core:math/linalg/glsl"

Query :: distinct u32
Sampler :: distinct u32
Sync :: distinct u32
TransformFeedback :: distinct u32
VertexArrayObject :: distinct u32

IsWebGL2Supported :: proc "contextless" () -> bool {return {}}

/* Buffer objects */
CopyBufferSubData :: proc(
	readTarget, writeTarget: Enum,
	readOffset, writeOffset: i32,
	size: i32,
) {}
GetBufferSubData :: proc(
	target: Enum,
	srcByteOffset: i32,
	dst_buffer: []byte,
	dstOffset: i32 = 0,
	length: i32 = 0,
) {}

/* Framebuffer objects */
BlitFramebuffer :: proc(
	srcX0, srcY0, srcX1, srcY1, dstX0, dstY0, dstX1, dstY1: i32,
	mask: u32,
	filter: Enum,
) {}
FramebufferTextureLayer :: proc(
	target: Enum,
	attachment: Enum,
	texture: Texture,
	level: i32,
	layer: i32,
) {}
InvalidateFramebuffer :: proc(target: Enum, attachments: []Enum) {}
InvalidateSubFramebuffer :: proc(target: Enum, attachments: []Enum, x, y, width, height: i32) {}
ReadBuffer :: proc(src: Enum) {}

/* Renderbuffer objects */
RenderbufferStorageMultisample :: proc(
	target: Enum,
	samples: i32,
	internalformat: Enum,
	width, height: i32,
) {}

/* Texture objects */
TexStorage3D :: proc(target: Enum, levels: i32, internalformat: Enum, width, height, depth: i32) {}
TexImage3D :: proc(
	target: Enum,
	level: i32,
	internalformat: Enum,
	width, height, depth: i32,
	border: i32,
	format, type: Enum,
	size: i32,
	data: rawptr,
) {}
TexSubImage3D :: proc(
	target: Enum,
	level: i32,
	xoffset, yoffset, zoffset, width, height, depth: i32,
	format, type: Enum,
	size: i32,
	data: rawptr,
) {}
CompressedTexImage3D :: proc(
	target: Enum,
	level: i32,
	internalformat: Enum,
	width, height, depth: i32,
	border: i32,
	imageSize: i32,
	data: rawptr,
) {}
CompressedTexSubImage3D :: proc(
	target: Enum,
	level: i32,
	xoffset, yoffset: i32,
	width, height, depth: i32,
	format: Enum,
	imageSize: i32,
	data: rawptr,
) {}
CopyTexSubImage3D :: proc(
	target: Enum,
	level: i32,
	xoffset, yoffset, zoffset: i32,
	x, y, width, height: i32,
) {}

/* Programs and shaders */
GetFragDataLocation :: proc(program: Program, name: string) -> i32 {return {}}

/* Uniforms */
Uniform1ui :: proc(location: i32, v0: u32) {}
Uniform2ui :: proc(location: i32, v0: u32, v1: u32) {}
Uniform3ui :: proc(location: i32, v0: u32, v1: u32, v2: u32) {}
Uniform4ui :: proc(location: i32, v0: u32, v1: u32, v2: u32, v3: u32) {}

/* Vertex attribs */
VertexAttribI4i :: proc(index: i32, x, y, z, w: i32) {}
VertexAttribI4ui :: proc(index: i32, x, y, z, w: u32) {}
VertexAttribIPointer :: proc(index: i32, size: i32, type: Enum, stride: i32, offset: uintptr) {}

/* Writing to the drawing buffer */
VertexAttribDivisor :: proc(index: u32, divisor: u32) {}
DrawArraysInstanced :: proc(mode: Enum, first, count: i32, instanceCount: i32) {}
DrawElementsInstanced :: proc(
	mode: Enum,
	count: i32,
	type: Enum,
	offset: i32,
	instanceCount: i32,
) {}
DrawRangeElements :: proc(mode: Enum, start, end, count: i32, type: Enum, offset: i32) {}

/* Multiple Render Targets */
DrawBuffers :: proc(buffers: []Enum) {}
ClearBufferfv :: proc(buffer: Enum, drawbuffer: i32, values: []f32) {}
ClearBufferiv :: proc(buffer: Enum, drawbuffer: i32, values: []i32) {}
ClearBufferuiv :: proc(buffer: Enum, drawbuffer: i32, values: []u32) {}
ClearBufferfi :: proc(buffer: Enum, drawbuffer: i32, depth: f32, stencil: i32) {}

CreateQuery :: proc() -> Query {return {}}
DeleteQuery :: proc(query: Query) {}
IsQuery :: proc(query: Query) -> bool {return {}}
BeginQuery :: proc(target: Enum, query: Query) {}
EndQuery :: proc(target: Enum) {}
GetQuery :: proc(target, pname: Enum) {}

CreateSampler :: proc() -> Sampler {return {}}
DeleteSampler :: proc(sampler: Sampler) {}
IsSampler :: proc(sampler: Sampler) -> bool {return {}}
BindSampler :: proc(unit: Enum, sampler: Sampler) {}
SamplerParameteri :: proc(sampler: Sampler, pname: Enum, param: i32) {}
SamplerParameterf :: proc(sampler: Sampler, pname: Enum, param: f32) {}

FenceSync :: proc(condition: Enum, flags: u32) -> Sync {return {}}
IsSync :: proc(sync: Sync) -> bool {return {}}
DeleteSync :: proc(sync: Sync) {}
ClientWaitSync :: proc(sync: Sync, flags: u32, timeout: u64) {}
WaitSync :: proc(sync: Sync, flags: u32, timeout: i64) {}

CreateTransformFeedback :: proc() -> TransformFeedback {return {}}
DeleteTransformFeedback :: proc(tf: TransformFeedback) {}
IsTransformFeedback :: proc(tf: TransformFeedback) -> bool {return {}}
BindTransformFeedback :: proc(target: Enum, tf: TransformFeedback) {}
BeginTransformFeedback :: proc(primitiveMode: Enum) {}
EndTransformFeedback :: proc() {}
TransformFeedbackVaryings :: proc(program: Program, varyings: []string, bufferMode: Enum) {}
PauseTransformFeedback :: proc() {}
ResumeTransformFeedback :: proc() {}

BindBufferBase :: proc(target: Enum, index: i32, buffer: Buffer) {}
BindBufferRange :: proc(target: Enum, index: i32, buffer: Buffer, offset: i32, size: i32) {}
GetUniformBlockIndex :: proc(program: Program, uniformBlockName: string) -> i32 {return {}}
UniformBlockBinding :: proc(program: Program, uniformBlockIndex: i32, uniformBlockBinding: i32) {}

CreateVertexArray :: proc() -> VertexArrayObject {return {}}
DeleteVertexArray :: proc(vertexArray: VertexArrayObject) {}
IsVertexArray :: proc(vertexArray: VertexArrayObject) -> bool {return {}}
BindVertexArray :: proc(vertexArray: VertexArrayObject) {}

GetActiveUniformBlockName :: proc(
	program: Program,
	uniformBlockIndex: i32,
	buf: []byte,
) -> string {
	return {}
}


Uniform1uiv :: proc "contextless" (location: i32, v: u32) {}
Uniform2uiv :: proc "contextless" (location: i32, v: glm.uvec2) {}
Uniform3uiv :: proc "contextless" (location: i32, v: glm.uvec3) {}
Uniform4uiv :: proc "contextless" (location: i32, v: glm.uvec4) {}

UniformMatrix3x2fv :: proc "contextless" (location: i32, m: glm.mat3x2) {}
UniformMatrix4x2fv :: proc "contextless" (location: i32, m: glm.mat4x2) {}
UniformMatrix2x3fv :: proc "contextless" (location: i32, m: glm.mat2x3) {}
UniformMatrix4x3fv :: proc "contextless" (location: i32, m: glm.mat4x3) {}
UniformMatrix2x4fv :: proc "contextless" (location: i32, m: glm.mat2x4) {}
UniformMatrix3x4fv :: proc "contextless" (location: i32, m: glm.mat3x4) {}

VertexAttribI4iv :: proc "contextless" (index: i32, v: glm.ivec4) {}
VertexAttribI4uiv :: proc "contextless" (index: i32, v: glm.uvec4) {}
