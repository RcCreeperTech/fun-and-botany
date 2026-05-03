package engine

import "../vm"

vm_interop_vtable := vm.UsrVtable {
	get_entrypoint = vm_get_entrypoint,
	get_param = vm_get_param,
	set_param = vm_set_param,
	spawn_element = vm_spawn_element,
}

vm_spawn_element :: proc(user_context: any, theta: f32, mass: f32, entrypoint: vm.Label) {
	element := user_context.(^Sim_Element)
	sim_element_spawn(&g_app_state.sim, element, theta, mass, entrypoint)
}

vm_get_entrypoint :: proc(user_context: any) -> (vm.Label) {
	element := user_context.(^Sim_Element)
	return element.vm_entrypoint
}

vm_get_param :: proc(user_context: any, param: vm.Param) -> (v: vm.Value, err: vm.VM_Error) {
	element := user_context.(^Sim_Element)
	switch param {
	case .State:
		return element.vm_entrypoint, nil
	case .Thickness:
		return element.thickness, nil
	case .Length:
		return element.length, nil
	case .Color:
		return element.color, nil
	case .Growth_Rate:
		return element.growth_rate, nil
	case .Lignen:
		return element.lignen, nil
	case .Interpolate_Colors:
		return .interpolate_colors in element.flags, nil
	case .Depth:
		return f32(element.depth), nil
	}
	return nil, .Unknown_Parameter_Access
}

vm_set_param :: proc(user_context: any, param: vm.Param, value: vm.Value) -> vm.VM_Error {
	element := user_context.(^Sim_Element)
	switch param {
	case .State:
		v, ok := value.(vm.Label)
		if !ok do return .Parameter_Type_Mistmatch
		element.vm_entrypoint = v
	case .Thickness:
		v, ok := value.(f32)
		if !ok do return .Parameter_Type_Mistmatch
        element.target_thickness = v
	case .Length:
		v, ok := value.(f32)
		if !ok do return .Parameter_Type_Mistmatch
        element.target_length = v
	case .Color:
		v, ok := value.(Color)
		if !ok do return .Parameter_Type_Mistmatch
        element.target_color = v
	case .Growth_Rate, .Depth:
		return .Readonly_Parameter
	case .Lignen:
		v, ok := value.(f32)
		if !ok do return .Parameter_Type_Mistmatch
        element.lignen = v
        element.lignen_changed = true
	case .Interpolate_Colors:
		v, ok := value.(bool)
		if !ok do return .Parameter_Type_Mistmatch
		if v {
			element.flags += {.interpolate_colors}
		} else {
			element.flags -= {.interpolate_colors}
		}
	}
	return nil
}
