package vm

import "core:encoding/json"
import "core:io"
import "core:reflect"
import "core:strconv"

value_marshaler :: proc(w: io.Writer, v: any, opt: ^json.Marshal_Options) -> json.Marshal_Error {
	val, ok := v.(Value)
	if !ok do return .Unsupported_Type

	json.opt_write_start(w, opt, '{') or_return
	json.opt_write_iteration(w, opt, true) or_return

	switch variant in val {
	case f32:
		json.opt_write_key(w, opt, "f32") or_return
		json.marshal_to_writer(w, variant, opt) or_return
	case bool:
		json.opt_write_key(w, opt, "bool") or_return
		json.marshal_to_writer(w, variant, opt) or_return
	case Color:
		json.opt_write_key(w, opt, "Color") or_return
		json.marshal_to_writer(w, variant, opt) or_return
	case Label:
		json.opt_write_key(w, opt, "Label") or_return
		// Cast to u8 to prevent an infinite loop, as we are bypassing the union
		json.marshal_to_writer(w, u8(variant), opt) or_return
	case Param:
		json.opt_write_key(w, opt, "Param") or_return
		json.marshal_to_writer(w, variant, opt) or_return
	}

	json.opt_write_end(w, opt, '}') or_return
	return nil
}

value_unmarshaler :: proc(p: ^json.Parser, v: any) -> json.Unmarshal_Error {
	val_ptr := (^Value)(v.data)

	if p.curr_token.kind != .Open_Brace do return .Invalid_Data
	json.advance_token(p)

	// If the next token is already a closing brace, it's an empty/unused union slot.
	if p.curr_token.kind == .Close_Brace {
		json.advance_token(p)
		return nil // Leave val_ptr^ as its default zero-value
	}

	if p.curr_token.kind != .String do return .Invalid_Data
	key := p.curr_token.text[1 : len(p.curr_token.text)-1]
	json.advance_token(p)

	if p.curr_token.kind != .Colon do return .Invalid_Data
	json.advance_token(p)

	switch key {
	case "f32":
		if p.curr_token.kind != .Float && p.curr_token.kind != .Integer do return .Invalid_Data
		f, _ := strconv.parse_f32(p.curr_token.text)
		val_ptr^ = f
		json.advance_token(p)

	case "bool":
		if p.curr_token.kind == .True {
			val_ptr^ = true
		} else if p.curr_token.kind == .False {
			val_ptr^ = false
		} else {
			return .Invalid_Data
		}
		json.advance_token(p)

	case "Label":
		if p.curr_token.kind != .Integer do return .Invalid_Data
		i, _ := strconv.parse_int(p.curr_token.text)
		val_ptr^ = Label(i)
		json.advance_token(p)

	case "Color":
		if p.curr_token.kind != .Open_Bracket do return .Invalid_Data
		json.advance_token(p)

		c: Color
		for i in 0..<4 {
			if p.curr_token.kind != .Integer do return .Invalid_Data
			num, _ := strconv.parse_int(p.curr_token.text)
			c[i] = u8(num)
			json.advance_token(p)

			if i < 3 { // Consume commas between color elements
				if p.curr_token.kind != .Comma do return .Invalid_Data
				json.advance_token(p)
			}
		}

		if p.curr_token.kind != .Close_Bracket do return .Invalid_Data
		val_ptr^ = c
		json.advance_token(p)

	case "Param":
			if p.curr_token.kind == .String {
				s := p.curr_token.text[1 : len(p.curr_token.text)-1]

				// Get the base type info to bypass the Type_Info_Named wrapper
				base_info := reflect.type_info_base(type_info_of(Param))
				ti := base_info.variant.(reflect.Type_Info_Enum)

				found := false
				for name, i in ti.names {
					if name == s {
						val_ptr^ = Param(ti.values[i])
						found = true
						break
					}
				}
				if !found do return .Invalid_Data

			} else if p.curr_token.kind == .Integer {
				i, _ := strconv.parse_int(p.curr_token.text)
				val_ptr^ = Param(i)
			} else {
				return .Invalid_Data
			}
			json.advance_token(p)
	case:
		return .Invalid_Data // Unknown variant type
	}

	if p.curr_token.kind != .Close_Brace do return .Invalid_Data
	json.advance_token(p)

	return nil
}

init_json_encoders :: proc() {
	json.set_user_marshalers(new(map[typeid]json.User_Marshaler))
	json.set_user_unmarshalers(new(map[typeid]json.User_Unmarshaler))

	json.register_user_marshaler(typeid_of(Value), value_marshaler)
	json.register_user_unmarshaler(typeid_of(Value), value_unmarshaler)
}
