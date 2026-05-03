#+feature using-stmt
package vm

import "core:reflect"
import sm "core:container/small_array"
import "core:log"
import "core:math/rand"

VM :: struct {
	stack:        sm.Small_Array(64, Value),
	call_stack:   sm.Small_Array(16, BlockPointer),
	active_block: BlockPointer,
	usr:          UsrVtable,
}

UsrVtable :: struct {
	get_param: GetParam,
	set_param: SetParam,
	get_entrypoint: GetEntrypoint,
	spawn_element: SpawnElement,
}

GetParam :: #type proc(user_context: any, param: Param) -> (Value, VM_Error)
SetParam :: #type proc(user_context: any, param: Param, value: Value) -> VM_Error
GetEntrypoint :: #type proc(user_context: any) -> Label
SpawnElement :: #type proc(user_context: any, theta: f32, mass: f32, entrypoint: Label)

usr_get_param :: proc(vm: ^VM, user_context: any, param: Param) -> (Value, VM_Error) {
	get_param := vm.usr.get_param if vm.usr.get_param != nil else default_vtable.get_param
	return get_param(user_context, param)
}
usr_set_param :: proc(vm: ^VM, user_context: any, param: Param, value: Value) -> VM_Error {
	set_param := vm.usr.set_param if vm.usr.set_param != nil else default_vtable.set_param
	return set_param(user_context, param, value)
}
usr_get_entrypoint :: proc(vm: ^VM, user_context: any) -> Label {
	get_entrypoint := vm.usr.get_entrypoint if vm.usr.get_entrypoint != nil else default_vtable.get_entrypoint
	return get_entrypoint(user_context)
}
usr_spawn_element :: proc(vm: ^VM, user_context: any, theta: f32, mass: f32, entrypoint: Label) {
	spawn_element := vm.usr.spawn_element if vm.usr.spawn_element != nil else default_vtable.spawn_element
	spawn_element(user_context, theta, mass, entrypoint)
}

default_vtable := UsrVtable {
	get_param = proc(user_context: any, param: Param) -> (Value, VM_Error) {
		log.debugf("Tried to get_param(%w)", param)
		return nil, nil
	},
	set_param = proc(user_context: any, param: Param, value: Value) -> VM_Error {
		log.debugf("Tried to call set_param(%w, %w)", param, value)
		return nil
	},
	get_entrypoint = proc(user_context: any) -> Label {
		log.debugf("Tried to call get_entrypoint()")
		return 0
	},
	spawn_element = proc(user_context: any, theta: f32, mass: f32, entrypoint: Label) {
		log.debugf("Tried to call spawn_element(%w, %w, %w)", theta, mass, entrypoint)
	}
}

init_vm :: proc(self: ^VM, vtable: UsrVtable = default_vtable) {
	self.usr = vtable
}

reset_vm :: proc(self: ^VM) {
	sm.clear(&self.stack)
	sm.clear(&self.call_stack)
	self.active_block = {}
	self.usr = default_vtable
}

push_value :: proc "contextless" (vm: ^VM, v: Value) -> VM_Error {
	if sm.push_back(&vm.stack, v) {
		return nil
	} else {
		return .Stack_Overflow
	}
}

ensure_arg_count :: proc "contextless" (vm: ^VM, arity: int, op: Op) -> VM_Error {
	if sm.len(vm.stack) < arity {
		return Instruction_Arity_Mismatch_Error{ op, arity }
	} else {
		return nil
	}
}

// This operation is unsafe. The caller is expected to check the number of args
// on the stack before calling.
take_any_arg :: proc "contextless" (vm: ^VM) -> Value {
	item := vm.stack.data[vm.stack.len - 1]
	vm.stack.len -= 1
	return item
}
// This operation is unsafe. The caller is expected to check the number of args
// on the stack before calling.
take_arg :: proc(vm: ^VM, op: Op, $T: typeid) -> (T, VM_Error) {
	item := vm.stack.data[vm.stack.len - 1]
	vm.stack.len -= 1

	value, ok := item.(T)
	if !ok {
		err :=  Argument_Mismatch_Error {
			op = op,
			expected = T,
			got = reflect.union_variant_typeid(item)
		}
		return {}, err
	}

	return value, nil
}

get_imm :: proc(inst: Instruction, slot: int, $T: typeid) -> (T, VM_Error) {
	raw := inst.imm[slot]
	value, ok := raw.(T)
	if !ok {
		err :=  Argument_Mismatch_Error {
			op = inst.op,
			expected = T,
			got = reflect.union_variant_typeid(raw)
		}
		return {}, err
	}

	return value, nil
}

is_falsy :: proc "contextless" (v: Value) -> (bool, VM_Error) {
	#partial switch value in v {
	case f32:
		return value == 0, nil
	case bool:
		return value == false, nil
	}
	return false, .Comparison_Faliure
}

Precondition :: enum u8 {
	None = 0,
	Eq,
	Neq,
	Lt,
	Leq,
	Gt,
	Geq,
}
Op :: enum u8 {
	Rand,
	Push,
	Pop,
	Add,
	Subtract,
	Multiply,
	Divide,
	Negate,
	Jump,
	Call,
	EarlyReturn,
	GetParam,
	SetParam,
	Spawn,
	GetLocal,
	SetLocal,
}

Block :: []Instruction
Program :: struct {
	blocks: []Block,
}
BlockPointer :: struct {
	idx:  Label,
	head: Block,
}

Error :: enum {
	Stack_Overflow,
	Stack_Underflow,
	Comparison_Faliure,
	Unknown_Parameter_Access,
	Parameter_Type_Mistmatch,
	Readonly_Parameter,
	Not_Enough_Args_To_Evaluate_Precondition,
	Unsupported_Operation,
	Division_By_Zero,
}

Out_Of_Bounds_Error :: struct {
	kind: enum {read, write},
	attempted_to_access: int,
}

Instruction_Arity_Mismatch_Error :: struct {
	op: Op,
	expected: int,
}

Argument_Mismatch_Error :: struct {
	op:       Op,
	expected: typeid,
	got:      typeid,
}

Types_Not_Comparable_Error :: struct {
	t1, t2: typeid,
}

VM_Error :: union {
	Error,
	Argument_Mismatch_Error,
	Types_Not_Comparable_Error,
	Instruction_Arity_Mismatch_Error,
	Out_Of_Bounds_Error,
}

Instruction :: struct {
	precondition: Precondition,
	op:           Op,
	imm:          [2]Value, // PERF: Encode this better right now each value will have a tag
}

Value :: union {
	f32,
	bool,
	Color,
	Label,
	Param,
}

Color :: [4]u8
Label :: distinct u8

// TODO: Parent variants for relevent parameters
// TODO: Move to sim & make opaque here?
Param :: enum u8 {
	State,
	Thickness,
	Length,
	Color,
	Growth_Rate,
	Stiffness,
	Density,
	Interpolate_Colors,
}

run :: proc(vm: ^VM, program: Program, user_context: any = nil) -> (err: VM_Error) {
	sm.clear(&vm.stack)
	sm.clear(&vm.call_stack)
	entrypoint := usr_get_entrypoint(vm, user_context)
	vm.active_block = {
		idx  = entrypoint,
		head = program.blocks[entrypoint],
	}
	for {
		if inst, ok := fetch(vm); ok {
			early_return := exec(vm, inst, program, user_context) or_return
			if early_return do return nil
		} else {
			vm.active_block = sm.pop_back_safe(&vm.call_stack) or_break
		}
	}
	return nil
}

fetch :: proc(vm: ^VM) -> (Instruction, bool) {
	if len(vm.active_block.head) == 0 {
		return {}, false
	} else {
		return vm.active_block.head[0], true
	}
}

exec :: proc(
	vm: ^VM,
	inst: Instruction,
	program: Program,
	user_context: any = nil,
) -> (
	early_return: bool,
	err: VM_Error,
) {
	advance_pc: bool = true
	defer if advance_pc do vm.active_block.head = vm.active_block.head[1:]

	precond_success: bool = true
	if inst.precondition != nil {
		if sm.len(vm.stack) < 2 {
			return false, .Not_Enough_Args_To_Evaluate_Precondition
		}
		b := take_any_arg(vm)
		a := take_any_arg(vm)

		precond_success, err = evaluate_precondition(inst.precondition, a, b)
		log.debugf("Precond Comparison: %v %v %v => %v", a, inst.precondition, b, precond_success)
	}

	is_instruction_skippable := inst.op != .Push && inst.op != .Jump && inst.op != .Call

	if is_instruction_skippable && !precond_success {
		log.debugf("Skipping instruction")
		return false, nil
	}

	switch inst.op {
	case .Spawn:
		ensure_arg_count(vm, 2, inst.op) or_return

		label := take_arg(vm, inst.op, Label) or_return
		angle := take_arg(vm, inst.op, f32) or_return

		usr_spawn_element(vm, user_context, angle, 1, label)
	case .GetParam:
		param := get_imm(inst, 0, Param) or_return

		value := usr_get_param(vm, user_context, param) or_return
		push_value(vm , value) or_return
	case .SetParam:
		ensure_arg_count(vm, 1, inst.op) or_return

		value := take_any_arg(vm)
		param := get_imm(inst, 0, Param) or_return

		usr_set_param(vm, user_context, param, value) or_return
	case .SetLocal:
		ensure_arg_count(vm, 1, inst.op) or_return
		val := take_any_arg(vm)

		offset := cast(int)get_imm(inst, 0 if precond_success else 1, f32) or_return
		if offset == vm.stack.len {
			push_value(vm, val) or_return
		} else if offset < vm.stack.len {
			vm.stack.data[offset] = val
		} else {
			return false, Out_Of_Bounds_Error {.write, offset}
		}
	case .GetLocal:
		offset := cast(int)get_imm(inst, 0 if precond_success else 1, f32) or_return
		if offset < vm.stack.len {
			val := vm.stack.data[offset]
			push_value(vm, val) or_return
		} else {
			return false, Out_Of_Bounds_Error {.read, offset }
		}
	case .Rand:
		push_value(vm, rand.float32()) or_return
	case .Push:
		push_value(vm, inst.imm[0 if precond_success else 1]) or_return
	case .Pop:
		if _, ok := sm.pop_back_safe(&vm.stack); !ok {
			return false, .Stack_Underflow
		}
	case .Add:
		add(vm) or_return
	case .Subtract:
		subtract(vm) or_return
	case .Multiply:
		multiply(vm) or_return
	case .Divide:
		divide(vm) or_return
	case .Negate:
		negate(vm) or_return
	case .Jump:
		advance_pc = false
		label := get_imm(inst, 0 if precond_success else 1, Label) or_return
		vm.active_block = {
			idx  = label,
			head = program.blocks[label],
		}
		return false, nil // To avoid incrementing PC
	case .Call: // TODO: REMOVE THIS OP FOR GOOD
		advance_pc = false
		label := get_imm(inst, 0 if precond_success else 1, Label) or_return
		return_point :=  BlockPointer {
			idx = vm.active_block.idx,
			head = vm.active_block.head[1:] // Execution should countinue after the call
		}
		if !sm.push_back(&vm.call_stack, return_point) {
			log.error("Block call depth limit exceeded, please remove this deprecated op")
		}
		vm.active_block = {
			idx  = label,
			head = program.blocks[label],
		}
		return false, nil // To avoid incrementing PC
	case .EarlyReturn:
		return true, nil
	}

	return false, nil
}

evaluate_precondition :: proc(cond: Precondition, a, b: Value) -> (bool, VM_Error) {
	tag_a := reflect.union_variant_typeid(a)
	tag_b := reflect.union_variant_typeid(b)
	if tag_a != tag_b {
		return false, Types_Not_Comparable_Error{ tag_a, tag_b }
	}

	switch t1 in a {
	case f32:
		t2 := b.(f32)
		#partial switch cond {
		case .Eq: return  (t1 == t2), nil
		case .Neq: return (t1 != t2), nil
		case .Lt: return  (t1 <  t2), nil
		case .Leq: return (t1 <= t2), nil
		case .Gt: return  (t1 >  t2), nil
		case .Geq: return (t1 >= t2), nil
		}
	case bool:
		t2 := b.(bool)
		#partial switch cond {
		case .Eq: return  (t1 == t2), nil
		case .Neq: return (t1 != t2), nil
		case: return false, .Comparison_Faliure
		}
	case Color:
		t2 := b.(Color)
		#partial switch cond {
		case .Eq: return  (t1 == t2), nil
		case .Neq: return (t1 != t2), nil
		case: return false, .Comparison_Faliure
		}
	case Label:
		t2 := b.(Label)
		#partial switch cond {
		case .Eq: return  (t1 == t2), nil
		case .Neq: return (t1 != t2), nil
		case: return false, .Comparison_Faliure
		}
	case Param:
		return false, .Comparison_Faliure
	}
	return false, .Comparison_Faliure
}

add :: proc(vm: ^VM) -> VM_Error {
	ensure_arg_count(vm, 2, .Add) or_return
	b := take_any_arg(vm)
	a := take_any_arg(vm)

	tag_a := reflect.union_variant_typeid(a)
	tag_b := reflect.union_variant_typeid(b)
	if tag_a != tag_b {
		return Argument_Mismatch_Error{ .Add, tag_a, tag_b }
	}

	switch va in a {
	case f32:
		vb := b.(f32)
		push_value(vm, va + vb) or_return
	case Color:
		vb := b.(Color)
		push_value(vm, va + vb) or_return
	case bool, Label, Param:
		return .Unsupported_Operation
	}

	return nil
}

subtract :: proc(vm: ^VM) -> VM_Error {
	ensure_arg_count(vm, 2, .Subtract) or_return
	b := take_any_arg(vm)
	a := take_any_arg(vm)

	tag_a := reflect.union_variant_typeid(a)
	tag_b := reflect.union_variant_typeid(b)
	if tag_a != tag_b {
		return Argument_Mismatch_Error{ .Subtract, tag_a, tag_b }
	}

	switch va in a {
	case f32:
		vb := b.(f32)
		push_value(vm, va - vb) or_return
	case Color:
		vb := b.(Color)
		push_value(vm, va - vb) or_return
	case bool, Label, Param:
		return .Unsupported_Operation
	}

	return nil
}

multiply :: proc(vm: ^VM) -> VM_Error {
	ensure_arg_count(vm, 2, .Multiply) or_return
	b := take_any_arg(vm)
	a := take_any_arg(vm)

	tag_a := reflect.union_variant_typeid(a)
	tag_b := reflect.union_variant_typeid(b)
	if tag_a != tag_b {
		return Argument_Mismatch_Error{ .Multiply, tag_a, tag_b }
	}

	switch va in a {
	case f32:
		vb := b.(f32)
		push_value(vm, va * vb) or_return
	case Color:
		vb := b.(Color)
		push_value(vm, va * vb) or_return
	case bool, Label, Param:
		return .Unsupported_Operation
	}

	return nil
}

divide :: proc(vm: ^VM) -> VM_Error {
	ensure_arg_count(vm, 2, .Divide) or_return
	b := take_any_arg(vm)
	a := take_any_arg(vm)

	tag_a := reflect.union_variant_typeid(a)
	tag_b := reflect.union_variant_typeid(b)
	if tag_a != tag_b {
		return Argument_Mismatch_Error{ .Divide, tag_a, tag_b }
	}

	switch va in a {
	case f32:
		vb := b.(f32)
		if vb == 0 do return .Division_By_Zero
		push_value(vm, va / vb) or_return
	case Color:
		vb := b.(Color)
		push_value(vm, va / vb) or_return
	case bool, Label, Param:
		return .Unsupported_Operation
	}

	return nil
}

negate :: proc(vm: ^VM) -> VM_Error {
	ensure_arg_count(vm, 1, .Negate) or_return

	switch v in take_any_arg(vm) {
	case f32:
		push_value(vm, -v) or_return
	case bool:
		push_value(vm, !v) or_return
	case Color, Label, Param:
		return .Unsupported_Operation
	}

	return nil
}
