package compiler
// THIS IS A Temporary fix until upstream figures out its problems
import "base:runtime"
import "core:mem"

/*
Default block size for dynamic arena.
*/
DYNAMIC_ARENA_BLOCK_SIZE_DEFAULT :: 65536

/*
Default out-band size of the dynamic arena.
*/
DYNAMIC_ARENA_OUT_OF_BAND_SIZE_DEFAULT :: 6554

/*
Dynamic arena allocator data.
*/
Dynamic_Arena :: struct {
	block_size:           int,
	out_band_size:        int,
	unused_blocks:        [dynamic]rawptr,
	used_blocks:          [dynamic]rawptr,
	out_band_allocations: [dynamic]rawptr,
	current_block:        rawptr,
	current_pos:          rawptr,
	bytes_left:           int,
	block_allocator:      mem.Allocator,
}

/*
Initialize a dynamic arena.

This procedure initializes a dynamic arena. The specified `block_allocator`
will be used to allocate arena blocks, and `array_allocator` to allocate
arrays of blocks and out-band blocks. The blocks have the default size of
`block_size` and out-band threshold will be `out_band_size`. All allocations
will be aligned to a boundary specified by `alignment`.
*/
dynamic_arena_init :: proc(
	arena: ^Dynamic_Arena,
	block_allocator := context.allocator,
	array_allocator := context.allocator,
	block_size      := DYNAMIC_ARENA_BLOCK_SIZE_DEFAULT,
	out_band_size   := DYNAMIC_ARENA_OUT_OF_BAND_SIZE_DEFAULT,
) {
	arena.block_size                     = block_size
	arena.out_band_size                  = out_band_size
	arena.block_allocator                = block_allocator
	arena.out_band_allocations.allocator = array_allocator
	arena.unused_blocks.allocator        = array_allocator
	arena.used_blocks.allocator          = array_allocator
}

/*
Dynamic arena allocator.

The dynamic arena allocator uses blocks of a specific size, allocated on-demand
using the block allocator. This allocator acts similarly to `Arena`. All
allocations in a block happen contiguously, from start to end. If an allocation
does not fit into the remaining space of the block and its size is smaller
than the specified out-band size, a new block is allocated using the
`block_allocator` and the allocation is performed from a newly-allocated block.

If an allocation is larger than the specified out-band size, a new block
is allocated such that the allocation fits into this new block. This is referred
to as an *out-band allocation*. The out-band blocks are kept separately from
normal blocks.

Just like `Arena`, the dynamic arena does not support freeing of individual
objects.
*/
@(require_results)
dynamic_arena_allocator :: proc(a: ^Dynamic_Arena) -> mem.Allocator {
	return mem.Allocator{
		procedure = dynamic_arena_allocator_proc,
		data = a,
	}
}

/*
Destroy a dynamic arena.

This procedure frees all allocations made on a dynamic arena, including the
unused blocks, as well as the arrays for storing blocks.
*/
dynamic_arena_destroy :: proc(a: ^Dynamic_Arena) {
	dynamic_arena_free_all(a)
	delete(a.unused_blocks)
	delete(a.used_blocks)
	delete(a.out_band_allocations)
	mem.zero(a, size_of(a^))
}

@(private="file")
_dynamic_arena_cycle_new_block :: proc(a: ^Dynamic_Arena, alignment: int, loc := #caller_location) -> (err: mem.Allocator_Error) {
	if a.block_allocator.procedure == nil {
		panic("You must call `dynamic_arena_init` on a Dynamic Arena before using it.", loc)
	}
	if a.current_block != nil {
		append(&a.used_blocks, a.current_block, loc=loc)
	}
	new_block: rawptr
	if len(a.unused_blocks) > 0 {
		new_block = pop(&a.unused_blocks)
	} else {
		data: []byte
		data, err = a.block_allocator.procedure(
			a.block_allocator.data,
			mem.Allocator_Mode.Alloc,
			a.block_size,
			alignment,
			nil,
			0,
		)
		// sanitizer.address_poison(data)
		new_block = raw_data(data)
	}
	a.bytes_left    = a.block_size
	a.current_pos   = new_block
	a.current_block = new_block
	return
}

/*
Allocate memory from a dynamic arena.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment` from a dynamic arena `a`. The allocated memory is
zero-initialized. This procedure returns a pointer to the newly allocated memory
region.
*/
@(require_results)
dynamic_arena_alloc :: proc(a: ^Dynamic_Arena, size, alignment: int, loc := #caller_location) -> (rawptr, mem.Allocator_Error) {
	data, err := dynamic_arena_alloc_bytes(a, size, alignment, loc)
	return raw_data(data), err
}

/*
Allocate memory from a dynamic arena.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment` from a dynamic arena `a`. The allocated memory is
zero-initialized. This procedure returns a slice of the newly allocated memory
region.
*/
@(require_results)
dynamic_arena_alloc_bytes :: proc(a: ^Dynamic_Arena, size, alignment: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	bytes, err := dynamic_arena_alloc_bytes_non_zeroed(a, size, alignment, loc)
	if bytes != nil {
		mem.zero_slice(bytes)
	}
	return bytes, err
}

/*
Allocate non-initialized memory from a dynamic arena.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment` from a dynamic arena `a`. The allocated memory is not explicitly
zero-initialized. This procedure returns a pointer to the newly allocated
memory region.
*/
@(require_results)
dynamic_arena_alloc_non_zeroed :: proc(a: ^Dynamic_Arena, size, alignment: int, loc := #caller_location) -> (rawptr, mem.Allocator_Error) {
	data, err := dynamic_arena_alloc_bytes_non_zeroed(a, size, alignment, loc)
	return raw_data(data), err
}

/*
Allocate non-initialized memory from a dynamic arena.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment` from a dynamic arena `a`. The allocated memory is not explicitly
zero-initialized. This procedure returns a slice of the newly allocated
memory region.
*/
@(require_results)
dynamic_arena_alloc_bytes_non_zeroed :: proc(a: ^Dynamic_Arena, size, alignment: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
	if size >= a.out_band_size {
		assert(a.out_band_allocations.allocator.procedure != nil, "Backing array allocator must be initialized", loc=loc)
		memory, err := mem.alloc_bytes_non_zeroed(size, alignment, a.out_band_allocations.allocator, loc)
		if memory != nil {
			append(&a.out_band_allocations, raw_data(memory), loc = loc)
		}
		return memory, err
	}
	if size > a.block_size {
		return nil, .Invalid_Argument
	}

	ptr        := mem.align_forward(a.current_pos, uintptr(alignment))
	total_size := size + mem.ptr_sub((^byte)(ptr), (^byte)(a.current_pos))
	if total_size > a.bytes_left {
		err := _dynamic_arena_cycle_new_block(a, alignment, loc)
		if err != nil {
			return nil, err
		}
		if a.current_block == nil {
			return nil, .Out_Of_Memory
		}
		total_size = size
		ptr        = a.current_pos // no need to align since we allocated the new block with the required alignment
	}
	a.current_pos = ([^]byte)(a.current_pos)[total_size:]
	a.bytes_left -= total_size
	result       := ([^]byte)(ptr)[:size]
	// ensure_poisoned(result)
	// sanitizer.address_unpoison(result)
	return result, nil
}

/*
Reset a dynamic arena allocator.

This procedure frees all the allocations owned by the dynamic arena, excluding
the unused blocks.
*/
dynamic_arena_reset :: proc(a: ^Dynamic_Arena, loc := #caller_location) {
	if a.current_block != nil {
		// sanitizer.address_poison(a.current_block, a.block_size)
		append(&a.unused_blocks, a.current_block, loc=loc)
		a.current_block = nil
	}
	for block in a.used_blocks {
		// sanitizer.address_poison(block, a.block_size)
		append(&a.unused_blocks, block, loc=loc)
	}
	clear(&a.used_blocks)
	for allocation in a.out_band_allocations {
		free(allocation, a.out_band_allocations.allocator, loc=loc)
	}
	clear(&a.out_band_allocations)
	a.bytes_left = 0 // Make new allocations call `_dynamic_arena_cycle_new_block` again.
}

/*
Free all memory back to the dynamic arena allocator.

This procedure frees all the allocations owned by the dynamic arena, including
the unused blocks.
*/
dynamic_arena_free_all :: proc(a: ^Dynamic_Arena, loc := #caller_location) {
	dynamic_arena_reset(a)
	for block in a.unused_blocks {
		// sanitizer.address_unpoison(block, a.block_size)
		free(block, a.block_allocator, loc)
	}
	clear(&a.unused_blocks)
}

/*
Resize an allocation owned by a dynamic arena allocator.

This procedure resizes a memory region defined by its location `old_memory`
and its size `old_size` to have a size `size` and alignment `alignment`. The
newly allocated memory, if any, is zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `dynamic_arena_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

This procedure returns the pointer to the resized memory region.
*/
@(require_results)
dynamic_arena_resize :: proc(
	a:          ^Dynamic_Arena,
	old_memory: rawptr,
	old_size:   int,
	size:       int,
	alignment:  int,
	loc := #caller_location,
) -> (rawptr, mem.Allocator_Error) {
	bytes, err := dynamic_arena_resize_bytes(a, mem.byte_slice(old_memory, old_size), size, alignment, loc)
	return raw_data(bytes), err
}

/*
Resize an allocation owned by a dynamic arena allocator.

This procedure resizes a memory region specified by `old_data` to have a size
`size` and alignment `alignment`. The newly allocated memory, if any, is
zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `dynamic_arena_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

This procedure returns the slice of the resized memory region.
*/
@(require_results)
dynamic_arena_resize_bytes :: proc(
	a:         ^Dynamic_Arena,
	old_data:  []byte,
	size:      int,
	alignment: int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	if size == 0 {
		// NOTE: This allocator has no Free mode.
		return nil, nil
	}
	bytes, err := dynamic_arena_resize_bytes_non_zeroed(a, old_data, size, alignment, loc)
	if bytes != nil {
		if old_data == nil {
			mem.zero_slice(bytes)
		} else if size > len(old_data) {
			mem.zero_slice(bytes[len(old_data):])
		}
	}
	return bytes, err
}

/*
Resize an allocation owned by a dynamic arena allocator, without zero-initialization.

This procedure resizes a memory region defined by its location `old_memory`
and its size `old_size` to have a size `size` and alignment `alignment`. The
newly allocated memory, if any, is not explicitly zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `dynamic_arena_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

This procedure returns the pointer to the resized memory region.
*/
@(require_results)
dynamic_arena_resize_non_zeroed :: proc(
	a:          ^Dynamic_Arena,
	old_memory: rawptr,
	old_size:   int,
	size:       int,
	alignment:  int,
	loc := #caller_location,
) -> (rawptr, mem.Allocator_Error) {
	bytes, err := dynamic_arena_resize_bytes_non_zeroed(a, mem.byte_slice(old_memory, old_size), size, alignment, loc)
	return raw_data(bytes), err
}

/*
Resize an allocation owned by a dynamic arena allocator, without zero-initialization.

This procedure resizes a memory region specified by `old_data` to have a size
`size` and alignment `alignment`. The newly allocated memory, if any, is not
explicitly zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `dynamic_arena_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

This procedure returns the slice of the resized memory region.
*/
@(require_results)
dynamic_arena_resize_bytes_non_zeroed :: proc(
	a:         ^Dynamic_Arena,
	old_data:  []byte,
	size:      int,
	alignment: int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	if size == 0 {
		// NOTE: This allocator has no Free mode.
		return nil, nil
	}
	old_memory := raw_data(old_data)
	old_size := len(old_data)
	if old_size >= size {
		// sanitizer.address_poison(old_data[size:])
		return mem.byte_slice(old_memory, size), nil
	}
	// No information is kept about allocations in this allocator, thus we
	// cannot truly resize anything and must reallocate.
	data, err := dynamic_arena_alloc_bytes_non_zeroed(a, size, alignment, loc)
	if err == nil {
		runtime.copy(data, mem.byte_slice(old_memory, old_size))
	}
	return data, err
}

dynamic_arena_allocator_proc :: proc(
	allocator_data: rawptr,
	mode:           mem.Allocator_Mode,
	size:           int,
	alignment:      int,
	old_memory:     rawptr,
	old_size:       int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	arena := (^Dynamic_Arena)(allocator_data)
	switch mode {
	case .Alloc:
		return dynamic_arena_alloc_bytes(arena, size, alignment, loc)
	case .Alloc_Non_Zeroed:
		return dynamic_arena_alloc_bytes_non_zeroed(arena, size, alignment, loc)
	case .Free:
		return nil, .Mode_Not_Implemented
	case .Free_All:
		dynamic_arena_free_all(arena, loc)
	case .Resize:
		return dynamic_arena_resize_bytes(arena, mem.byte_slice(old_memory, old_size), size, alignment, loc)
	case .Resize_Non_Zeroed:
		return dynamic_arena_resize_bytes_non_zeroed(arena, mem.byte_slice(old_memory, old_size), size, alignment, loc)
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free_All, .Resize, .Resize_Non_Zeroed, .Query_Features, .Query_Info}
		}
		return nil, nil
	case .Query_Info:
		info := (^mem.Allocator_Query_Info)(old_memory)
		if info != nil && info.pointer != nil {
			info.size = arena.block_size
			return mem.byte_slice(info, size_of(info^)), nil
		}
		return nil, nil
	}
	return nil, nil
}
