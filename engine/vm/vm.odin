#+feature using-stmt
package vm

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

GetParam :: #type proc(user_context: any, param: Param) -> (Value, Error)
SetParam :: #type proc(user_context: any, param: Param, value: Value) -> Error
GetEntrypoint :: #type proc(user_context: any) -> Label
SpawnElement :: #type proc(user_context: any, theta: f32, mass: f32, entrypoint: Label)

default_vtable := UsrVtable {
	get_param = proc(user_context: any, param: Param) -> (Value, Error) {
		log.debugf("Tried to get_param(%w)", param)
		return nil, .None
	},
	set_param = proc(user_context: any, param: Param, value: Value) -> Error {
		log.debugf("Tried to call set_param(%w, %w)", param, value)
		return .None
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

push_value :: #force_inline proc "contextless" (vm: ^VM, v: Value) -> Error {
	if sm.push_back(&vm.stack, v) {
		return .None
	} else {
		return .Stack_Overflow
	}
}

ensure_arg_count :: #force_inline proc "contextless" (vm: ^VM, arity: int) -> Error {
	if sm.len(vm.stack) < arity {
		return .Instruction_Arity_Mismatch
	} else {
		return .None
	}
}

// This operation is unsafe. The caller is expected to check the number of args
// on the stack before calling.
take_arg :: #force_inline proc "contextless" (vm: ^VM) -> Value {
	item := vm.stack.data[vm.stack.len - 1]
	vm.stack.len -= 1
	return item
}

is_falsy :: proc "contextless" (v: Value) -> (bool, Error) {
	#partial switch value in v {
	case f32:
		return value == 0, .None
	case bool:
		return value == false, .None
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
	None = 0,
	Stack_Overflow,
	Stack_Underflow,
	Comparison_Faliure,
	Argument_Mismatch,
	Instruction_Arity_Mismatch,
	Unknown_Parameter_Access,
	Parameter_Type_Mistmatch,
	Readonly_Parameter,
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
Param :: enum u8 {
	State,
	Thickness,
	Length,
	Color,
	Growth_Rate,
	Stiffness,
	Density,
}

run :: proc(vm: ^VM, program: Program, user_context: any = nil) -> (err: Error) {
	sm.clear(&vm.stack)
	sm.clear(&vm.call_stack)
	use_usr_entrypoint := user_context != nil && vm.usr.get_entrypoint != nil
	entrypoint := vm.usr.get_entrypoint(user_context) if use_usr_entrypoint else 0
	vm.active_block = {
		idx  = entrypoint,
		head = program.blocks[entrypoint],
	}
	for {
		if inst, ok := fetch(vm); ok {
			early_return := exec(vm, inst, program, user_context) or_return
			if early_return do return .None
		} else {
			vm.active_block = sm.pop_back_safe(&vm.call_stack) or_break
		}
	}
	return .None
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
	err: Error,
) {
	advance_pc: bool = true
	defer if advance_pc do vm.active_block.head = vm.active_block.head[1:]

	log.debugf("Exec: %v", inst)
	log.debugf("Pre-stack: %v", vm.stack.data[:vm.stack.len])
	defer log.debugf("Post-stack: %v", vm.stack.data[:vm.stack.len])

	precond_success: bool = true
	if inst.precondition != .None {
		ensure_arg_count(vm, 2) or_return
		a := take_arg(vm) // [HEAD]
		b := take_arg(vm) // [HEAD - 1]

		precond_success, err = evaluate_precondition(inst.precondition, a, b)
		log.debugf("Precond Comparison: %v %v %v => %v", a, inst.precondition, b, precond_success)
		if err != .None {
			#partial switch err {
			case .Argument_Mismatch:
				log.error("Types are not comparable:", a, "and,", b)
			case .Comparison_Faliure:
				log.error(a, "is not totally ordered.")
			}
			return false, err
		}
	}

	is_instruction_skippable := inst.op != .Push && inst.op != .Jump && inst.op != .Call

	if is_instruction_skippable && !precond_success {
		log.debugf("Skipping instruction")
		return false, nil
	}

	switch inst.op {
	case .Spawn:
		if user_context != nil {
			ensure_arg_count(vm, 2) or_return

			arg0 := take_arg(vm)
			label, ok := arg0.(Label)
			if !ok do return false, .Argument_Mismatch

			arg1 := take_arg(vm)
			angle, ok2 := arg1.(f32)
			if !ok2 do return false, .Argument_Mismatch

			if vm.usr.spawn_element != nil do vm.usr.spawn_element(user_context, angle, 1, label)
		}
	case .GetParam:
		if user_context != nil {
			param, ok := inst.imm[0].(Param)
			if !ok do return false, .Argument_Mismatch

			if vm.usr.get_param != nil {
				val := vm.usr.get_param(user_context, param) or_return
				push_value(vm, val) or_return
			} else {
				// TODO: What to emit here?
			}
		}
	case .SetParam:
		if user_context != nil {
			ensure_arg_count(vm, 1) or_return

			value := take_arg(vm)
			param, ok := inst.imm[0].(Param)
			if !ok do return false, .Argument_Mismatch

			if vm.usr.set_param != nil {
				vm.usr.set_param(user_context, param, value) or_return
			} else {
				// TODO: What to do here?
			}
		}
	case .Rand:
		push_value(vm, rand.float32()) or_return
	case .Push:
		imm := inst.imm[0 if precond_success else 1]
		push_value(vm, imm) or_return
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
		imm := inst.imm[0 if precond_success else 1]
		if label, ok := imm.(Label); ok {
			vm.active_block = {
				idx  = label,
				head = program.blocks[label],
			}
			log.debugf("Jumping to new block %v: %#v", label, program.blocks[label])
			return false, .None // To avoid incrementing PC
		} else {
			return false, .Argument_Mismatch
		}
	case .Call:
		advance_pc = false
		imm := inst.imm[0 if precond_success else 1]
		if label, ok := imm.(Label); ok {
			return_point :=  BlockPointer {
				idx = vm.active_block.idx,
				head = vm.active_block.head[1:] // Execution should countinue after the call
			}
			if !sm.push_back(&vm.call_stack, return_point) {
				log.error("Block call depth limit exceeded")
			}
			vm.active_block = {
				idx  = label,
				head = program.blocks[label],
			}
			return false, .None // To avoid incrementing PC
		} else {
			return false, .Argument_Mismatch
		}
	case .EarlyReturn:
		log.debug("Prematurely ending block execution")
		return true, .None
	}

	return false, .None

}

evaluate_precondition :: proc(cond: Precondition, a, b: Value) -> (bool, Error) {
	#partial switch cond {
	case .Eq:
		switch t1 in a {
		case f32:
			if t2, ok := b.(f32); ok {
				return (t1 == t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case bool:
			if t2, ok := b.(bool); ok {
				return (t1 == t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case Color:
			if t2, ok := b.(Color); ok {
				return (t1 == t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case Label:
			if t2, ok := b.(Label); ok {
				return (t1 == t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case Param:
			// Type is not comparable
			return false, .Comparison_Faliure
		}
	case .Neq:
		switch t1 in a {
		case f32:
			if t2, ok := b.(f32); ok {
				return (t1 != t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case bool:
			if t2, ok := b.(bool); ok {
				return (t1 != t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case Color:
			if t2, ok := b.(Color); ok {
				return (t1 != t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case Label:
			if t2, ok := b.(Label); ok {
				return (t1 != t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case Param:
			// Type is not comparable
			return false, .Comparison_Faliure
		}
	case .Lt:
		#partial switch t1 in a {
		case f32:
			if t2, ok := b.(f32); ok {
				return (t1 < t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case:
			return false, .Comparison_Faliure
		}
	case .Leq:
		#partial switch t1 in a {
		case f32:
			if t2, ok := b.(f32); ok {
				return (t1 <= t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case:
			return false, .Comparison_Faliure
		}
	case .Gt:
		#partial switch t1 in a {
		case f32:
			if t2, ok := b.(f32); ok {
				return (t1 > t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case:
			return false, .Comparison_Faliure
		}
	case .Geq:
		#partial switch t1 in a {
		case f32:
			if t2, ok := b.(f32); ok {
				return (t1 >= t2), .None
			} else {
				return false, .Argument_Mismatch
			}
		case:
			return false, .Comparison_Faliure
		}
	}
	unreachable()
}

add :: proc(vm: ^VM) -> Error {
	ensure_arg_count(vm, 2) or_return
	a := take_arg(vm)
	b := take_arg(vm)

	switch va in a {
	case f32:
		if vb, ok := b.(f32); ok {
			push_value(vm, va + vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			push_value(vm, va + vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, Label, Param:
		return .Argument_Mismatch
	}

	return .None
}

subtract :: proc(vm: ^VM) -> Error {
	ensure_arg_count(vm, 2) or_return
	a := take_arg(vm)
	b := take_arg(vm)

	switch va in a {
	case f32:
		if vb, ok := b.(f32); ok {
			push_value(vm, va - vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			push_value(vm, va - vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, Label, Param:
		return .Argument_Mismatch
	}

	return .None
}

multiply :: proc(vm: ^VM) -> Error {
	ensure_arg_count(vm, 2) or_return
	a := take_arg(vm)
	b := take_arg(vm)

	switch va in a {
	case f32:
		if vb, ok := b.(f32); ok {
			push_value(vm, va * vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			push_value(vm, va * vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, Label, Param:
		return .Argument_Mismatch
	}

	return .None
}

divide :: proc(vm: ^VM) -> Error {
	ensure_arg_count(vm, 2) or_return
	a := take_arg(vm)
	b := take_arg(vm)

	switch va in a {
	case f32:
		if vb, ok := b.(f32); ok {
			push_value(vm, va / vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			push_value(vm, va / vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, Label, Param:
		return .Argument_Mismatch
	}

	return .None
}

negate :: proc(vm: ^VM) -> Error {
	ensure_arg_count(vm, 1) or_return

	switch v in take_arg(vm) {
	case f32:
		push_value(vm, -v) or_return
	case bool:
		push_value(vm, !v) or_return
	case Color:
		unimplemented("TODO: Invert color")
	case Label, Param:
		return .Argument_Mismatch
	}

	return .None
}
