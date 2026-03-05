#+feature using-stmt
package web_testing

import sm "core:container/small_array"
import "core:log"
import "core:math/rand"

VM :: struct {
	stack: sm.Small_Array(64, VM_Value),
	call_stack: sm.Small_Array(16, VM_BlockPointer),
	active_block: VM_BlockPointer,
}

vm_push_value :: #force_inline proc "contextless" (vm: ^VM, v: VM_Value) -> VM_Error {
	if sm.push_back(&vm.stack, v) {
		return .None
	} else {
		return .Stack_Overflow
	}
}

vm_ensure_arg_count :: #force_inline proc "contextless" (vm: ^VM, arity: int) -> VM_Error {
	if sm.len(vm.stack) < arity {
		return .Instruction_Arity_Mismatch
	} else {
		return .None
	}
}

// This operation is unsafe. The caller is expected to check the number of args
// on the stack before calling.
vm_take_arg :: #force_inline proc "contextless" (vm: ^VM) -> VM_Value {
	item := vm.stack.data[vm.stack.len - 1]
	vm.stack.len -= 1
	return item
}

vm_is_falsy :: proc "contextless" (v: VM_Value) -> (bool, VM_Error) {
	#partial switch value in v {
	case i32:
		return value == 0, .None
	case f32:
		return value == 0, .None
	case bool:
		return value == false, .None
	}
	return false, .Comparison_Faliure
}

VM_Precondition :: enum u8 {
	None = 0,
	Eq,
	Neq,
	Lt,
	Leq,
	Gt,
	Geq,
}
VM_Op :: enum u8 {
	Rand,
	Push,
	Pop,
	Add,
	Subtract,
	Multiply,
	Divide,
	Negate,
	Jump,
	Jump_If_Falsy,
}

VM_Program :: struct {
	blocks: []VM_Block
}
VM_BlockPointer :: struct {
	idx: VM_Label,
	head: VM_Block,
}

VM_Instruction :: struct {
	precondition: VM_Precondition,
	op:           VM_Op,
	imm:          [2]VM_Value, // PERF: Encode this better right now each value will have a tag
}
VM_Value :: union {
	f32,
	i32,
	bool,
	Color,
	VM_Label,
}
VM_Label :: distinct u8 // TODO: Sort out labels
VM_Error :: enum {
	None = 0,
	Stack_Overflow,
	Stack_Underflow,
	Comparison_Faliure,
	Argument_Mismatch,
	Instruction_Arity_Mismatch,
}

VM_Block :: []VM_Instruction

vm_run :: proc(vm: ^VM, program: VM_Program) -> (err: VM_Error) {
	vm.active_block = {idx = 0, head = program.blocks[0]}
	for {
		if inst, ok := vm_fetch(vm); ok {
			vm_exec(vm, inst) or_return
		} else {
			vm.active_block = sm.pop_back_safe(&vm.call_stack) or_break
		}
	}
	return .None
}

vm_fetch :: proc(vm: ^VM) -> (VM_Instruction, bool) {
		if len(vm.active_block.head) == 0 {
			return {}, false
		} else {
			return vm.active_block.head[0], true
		}
	}

vm_exec :: proc(vm: ^VM, inst: VM_Instruction) -> (err: VM_Error) {

	precond_success: bool = true
	if inst.precondition != .None {
		vm_ensure_arg_count(vm, 2) or_return
		a := vm_take_arg(vm) // [HEAD]
		b := vm_take_arg(vm) // [HEAD - 1]

		{ 	// Implicit conversion special case
			_, a_is_float := a.(f32)
			bb, b_is_int := b.(i32)
			if a_is_float && b_is_int {
				b = f32(bb)
			}
		}
		precond_success, err := vm_evaluate_precondition(inst.precondition, a, b)
		if err != .None {
			#partial switch err {
			case .Argument_Mismatch:
				log.error("Types are not comparable:", a, "and,", b)
			case .Comparison_Faliure:
				log.error(a, "is not totally ordered.")
			}
			return err
		}

	}

	switch inst.op {
	case .Rand:
		if precond_success {
			vm_push_value(vm, rand.float32()) or_return
		}
	case .Push:
		imm := inst.imm[0] if precond_success else inst.imm[1]
		vm_push_value(vm, imm) or_return
	case .Pop:
		if precond_success {
			if _, ok := sm.pop_back_safe(&vm.stack); !ok {
				return .Stack_Underflow
			}
		}
	case .Add:
		if precond_success do vm_add(vm) or_return
	case .Subtract:
		if precond_success do vm_subtract(vm) or_return
	case .Multiply:
		if precond_success do vm_multiply(vm) or_return
	case .Divide:
		if precond_success do vm_divide(vm) or_return
	case .Negate:
		if precond_success do vm_negate(vm) or_return
	case .Jump: // TODO: This should really be a call Op not jump
		imm := inst.imm[0] if precond_success else inst.imm[1]
		if label, ok := imm.(VM_Label); ok {
			if !sm.push_back(&vm.call_stack, vm.active_block) {
				log.error("Block call depth limit exceeded")
			}
			vm.active_block = { idx = label }
			return .None // To avoid incrementing PC
		} else {
			return .Argument_Mismatch
		}
	case .Jump_If_Falsy:
		vm_ensure_arg_count(vm, 1) or_return
		pred := vm_take_arg(vm)

		imm := inst.imm[0] if precond_success else inst.imm[1]
		if label, ok := imm.(VM_Label); ok {
			should_jump := vm_is_falsy(pred) or_return
			if should_jump {
				if !sm.push_back(&vm.call_stack, vm.active_block) {
					log.error("Block call depth limit exceeded")
				}
				vm.active_block = { idx = label }
				return .None // To avoid incrementing PC
			}
		} else {
			return .Argument_Mismatch
		}
	}

	vm.active_block.head = vm.active_block.head[1:]
	return .None

}

vm_evaluate_precondition :: proc(cond: VM_Precondition, a, b: VM_Value) -> (bool, VM_Error) {
		#partial switch cond {
		case .Eq:
			switch t1 in a {
			case f32:
				if t2, ok := b.(f32); ok {
					return (t1 == t2), .None
				} else {
					return false, .Argument_Mismatch
				}
			case i32:
				if t2, ok := b.(i32); ok {
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
			case VM_Label:
				if t2, ok := b.(VM_Label); ok {
					return (t1 == t2), .None
				} else {
					return false, .Argument_Mismatch
				}
			}
		case .Neq:
			switch t1 in a {
			case f32:
				if t2, ok := b.(f32); ok {
					return (t1 != t2), .None
				} else {
					return false, .Argument_Mismatch
				}
			case i32:
				if t2, ok := b.(i32); ok {
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
			case VM_Label:
				if t2, ok := b.(VM_Label); ok {
					return (t1 != t2), .None
				} else {
					return false, .Argument_Mismatch
				}
			}
		case .Lt:
			#partial switch t1 in a {
			case f32:
				if t2, ok := b.(f32); ok {
					return (t1 < t2), .None
				} else {
					return false, .Argument_Mismatch
				}
			case i32:
				if t2, ok := b.(i32); ok {
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
			case i32:
				if t2, ok := b.(i32); ok {
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
			case i32:
				if t2, ok := b.(i32); ok {
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
			case i32:
				if t2, ok := b.(i32); ok {
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

vm_add :: proc(vm: ^VM) -> VM_Error {
	vm_ensure_arg_count(vm, 2) or_return
	a := vm_take_arg(vm)
	b := vm_take_arg(vm)

	switch va in a {
	case i32:
		if vb, ok := b.(i32); ok {
			vm_push_value(vm, va + vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case f32:
		if vb, ok := b.(f32); ok {
			vm_push_value(vm, va + vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			vm_push_value(vm, va + vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, VM_Label:
		return .Argument_Mismatch
	}

	return .None
}

vm_subtract :: proc(vm: ^VM) -> VM_Error {
	vm_ensure_arg_count(vm, 2) or_return
	a := vm_take_arg(vm)
	b := vm_take_arg(vm)

	switch va in a {
	case i32:
		if vb, ok := b.(i32); ok {
			vm_push_value(vm, va - vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case f32:
		if vb, ok := b.(f32); ok {
			vm_push_value(vm, va - vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			vm_push_value(vm, va - vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, VM_Label:
		return .Argument_Mismatch
	}

	return .None
}

vm_multiply :: proc(vm: ^VM) -> VM_Error {
	vm_ensure_arg_count(vm, 2) or_return
	a := vm_take_arg(vm)
	b := vm_take_arg(vm)

	switch va in a {
	case i32:
		if vb, ok := b.(i32); ok {
			vm_push_value(vm, va * vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case f32:
		if vb, ok := b.(f32); ok {
			vm_push_value(vm, va * vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			vm_push_value(vm, va * vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, VM_Label:
		return .Argument_Mismatch
	}

	return .None
}

vm_divide :: proc(vm: ^VM) -> VM_Error {
	vm_ensure_arg_count(vm, 2) or_return
	a := vm_take_arg(vm)
	b := vm_take_arg(vm)

	switch va in a {
	case i32:
		if vb, ok := b.(i32); ok {
			vm_push_value(vm, va / vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case f32:
		if vb, ok := b.(f32); ok {
			vm_push_value(vm, va / vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case Color:
		if vb, ok := b.(Color); ok {
			vm_push_value(vm, va / vb) or_return
		} else {
			return .Argument_Mismatch
		}
	case bool, VM_Label:
		return .Argument_Mismatch
	}

	return .None
}

vm_negate :: proc(vm: ^VM) -> VM_Error {
	vm_ensure_arg_count(vm, 1) or_return

	switch v in vm_take_arg(vm) {
	case i32:
		vm_push_value(vm, -v) or_return
	case f32:
		vm_push_value(vm, -v) or_return
	case bool:
		vm_push_value(vm, !v) or_return
	case Color:
	// TODO: Invert color
	case VM_Label:
		return .Argument_Mismatch
	}

	return .None
}
