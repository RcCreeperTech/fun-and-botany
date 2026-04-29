#+private file
package compiler_web_worker

// ----------------------------------------------------------------------------
// FFI Memory Management for JS
// ----------------------------------------------------------------------------

import "base:runtime"
import "core:mem"

FFI_BUF_SIZE :: mem.Kilobyte
FFI :: struct {
	buf:       [FFI_BUF_SIZE]byte,
	arena:     mem.Arena,
	allocator: mem.Allocator,
}

g_ffi: FFI

@(init)
init_ffi :: proc "contextless" () {
	g_ffi.arena.data = g_ffi.buf[:]
	g_ffi.allocator = {
		procedure = mem.arena_allocator_proc,
		data      = &g_ffi.arena,
	}
}

@(private)
ffi_out_var :: proc($T: typeid) -> ^T {
	free_all(g_ffi.allocator)
	return new(T)
}

// Called by JS to allocate space for the source code string before writing to memory.
@(export)
ffi_alloc_buffer :: proc(size: int) -> rawptr {
	// Using standard allocator so the source buffer persists safely outside the ephemeral ffi_arena.
	ptr, _ := mem.alloc(size)
	return ptr
}

@(export)
ffi_free_buffer :: proc(ptr: rawptr) {
	mem.free(ptr)
}
