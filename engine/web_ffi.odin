#+feature using-stmt
package web_testing

import "core:mem"
import "core:strings"
import "core:fmt"
import "base:runtime"
import "core:reflect"

// Used for FFI with wasm.
@(private)
g_ffi_allocator: mem.Allocator
@(private)
g_ffi_arena: mem.Arena
@(private)
g_ffi_buf: [1024]u8

@(private, init)
ffi_init :: proc "contextless" () {
	// Set up a shared space for ffi results
	for &b in g_ffi_buf do b = 0
	// Not using mem procedures because they are not contextless
	g_ffi_arena.data = g_ffi_buf[:]
	g_ffi_allocator = {
		procedure = mem.arena_allocator_proc,
		data      = &g_ffi_arena,
	}
}

ffi_out_var :: proc($T: typeid) -> ^T {
	free_all(g_ffi_allocator)
	return new(string)
}

@(export)
get_sim_state_ptr :: proc() -> rawptr {return &g_sim}

@(export)
get_sim_state_schema_json :: proc() -> rawptr {
	using strings
	defer free_all(context.temp_allocator)
	sb := builder_make(context.allocator) // TODO: Free me
	tagged_fields := make([dynamic]string, context.temp_allocator)
	write_string(&sb, "{\n")
	write_quoted_string(&sb, "schema")
	write_string(&sb, ": {\n")
	build_schema_recursive(&sb, &tagged_fields, type_info_of(typeid_of(SimulationState)))
	if sb.buf[len(sb.buf) - 2] == ',' { 	// Remove final comma
		sb.buf[len(sb.buf) - 2] = ' '
	}
	write_string(&sb, "},\n")
	write_quoted_string(&sb, "ui_params")
	write_string(&sb, ": [\n")
	for full_path in tagged_fields {
		write_quoted_string(&sb, full_path)
		write_string(&sb, ",")
	}
	strings.pop_byte(&sb) // Remove the last comma
	write_string(&sb, "]")
	write_string(&sb, "}")

	s := ffi_out_var(string)
	s^ = strings.to_string(sb)
	return s

	build_schema_recursive :: proc(
		sb: ^strings.Builder,
		tagged_fields: ^[dynamic]string,
		info: ^reflect.Type_Info,
		base_offset: uintptr = 0,
		prefix: string = "",
		metadata: string = "",
	) {
		// Resolve named types (like "Vector3") to their underlying struct info
		ti := reflect.type_info_base(info)
		#partial switch variant in ti.variant {
		case reflect.Type_Info_Struct:
			fields := soa_zip(
				name = variant.names[:variant.field_count],
				type = variant.types[:variant.field_count],
				offset = variant.offsets[:variant.field_count],
				tag = ([^]reflect.Struct_Tag)(variant.tags)[:variant.field_count],
				// is_using = variant.usings[:variant.field_count],
			)
			for field in fields {
				full_path := (prefix == "") ? field.name : fmt.tprintf("%s.%s", prefix, field.name)
				meta := reflect.struct_tag_lookup(field.tag, "ui") or_else ""
				if (meta != "") do append(tagged_fields, full_path)
				build_schema_recursive(
					sb,
					tagged_fields,
					field.type,
					base_offset + field.offset,
					full_path,
					meta,
				)
			}
		case:
			fmt.sbprintf(
				sb,
				`"%s": {{ "offset": %d, "type": "`,
				prefix, // Append a thing?
				base_offset, // Append a thing?
			)
			reflect.write_type(sb, ti)
			fmt.sbprint(sb, "\"")
			if (metadata != "") {
				write_string(sb, ",")
				meta := metadata
				for entry in strings.split_iterator(&meta, ",") {
					eq_idx := strings.index(entry, "=")
					key, value := entry[:eq_idx], entry[eq_idx + 1:]
					escaped_val, _ := strings.replace_all(value, "'", "\"", context.temp_allocator)
					fmt.sbprintf(sb, "\"%s\": %s,", key, escaped_val)
				}
				strings.pop_byte(sb) // Remove the last comma
			}
			fmt.sbprintln(sb, "},")
		}
	}
}
