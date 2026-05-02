#+feature using-stmt
package engine

import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"

@(export)
get_sim_state_ptr :: proc() -> rawptr {return &g_app_state}

@(export)
get_sim_state_schema_json :: proc() -> rawptr {
	using strings
	defer free_all(context.temp_allocator)
	sb := builder_make(context.allocator) // TODO: Free me
	tagged_fields := make([dynamic]string, context.temp_allocator)
	write_string(&sb, "{\n")
	write_quoted_string(&sb, "schema")
	write_string(&sb, ": {\n")
	build_schema_recursive(&sb, &tagged_fields, type_info_of(typeid_of(ApplicationState)))
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
