package engine

import "../vm"

vm_spawn_element :: proc(user_context: any, theta: f32, mass: f32, entrypoint: vm.Label) {
	element := user_context.(^Sim_Element)
	sim_element_spawn(&g_app_state, element, theta, mass, entrypoint)
}

vm_get_entrypoint :: proc(user_context: any) -> (vm.Label) {
	element := user_context.(^Sim_Element)
	return element.vm_entrypoint
}

vm_get_param :: proc(user_context: any, param: vm.Param) -> (v: vm.Value, err: vm.Error) {
	element := user_context.(^Sim_Element)
	switch param {
	case .State:
		return element.vm_entrypoint, .None
	case .Thickness:
		return element.thickness, .None
	case .Length:
		return element.length, .None
	case .Color:
		return element.color, .None
	case .Growth_Rate:
		return element.growth_rate, .None
	case .Stiffness:
		return element.stiffness, .None
	case .Density:
		return element.density, .None
	}
	return nil, .Unknown_Parameter_Access
}

vm_set_param :: proc(user_context: any, param: vm.Param, value: vm.Value) -> vm.Error {
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
	case .Growth_Rate:
		return .Readonly_Parameter
	case .Stiffness:
		v, ok := value.(f32)
		if !ok do return .Parameter_Type_Mistmatch
        element.target_stiffness = v
	case .Density:
		v, ok := value.(f32)
		if !ok do return .Parameter_Type_Mistmatch
        element.target_density = v
	}
	return .None
}
