#+test
package web_testing

import sm "core:container/small_array"
import "core:testing"

// FIXME: Port these once we have an assembler
@(test)
vm_test_push_pop :: proc(t: ^testing.T) {

	program, asm_err := asm_assemble(`
		Main:
			push 123
			push false
			pop
		end
	`)
	testing.expect(t, asm_err == AsmError.None)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.None)
	v := sm.pop_back(&vm.stack)
	testing.expect_value(t, v, i32(123))
}


@(test)
vm_test_underflow :: proc(t: ^testing.T) {
	program, asm_err := asm_assemble(`
		Main:
			pop
		end
	`)
	testing.expect(t, asm_err == AsmError.None)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.Stack_Underflow)
}

@(test)
vm_test_add :: proc(t: ^testing.T) {
	program, asm_err := asm_assemble(`
		Main:
			push 34
			push 35
			add
		end
	`)
	testing.expect(t, asm_err == AsmError.None)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.None)
	v := sm.pop_back(&vm.stack)
	testing.expect_value(t, v, i32(69))
}

@(test)
vm_test_bad_add :: proc(t: ^testing.T) {
	program, asm_err := asm_assemble(`
		Main:
			push 34
			push false
			add
		end
	`)
	testing.expect(t, asm_err == AsmError.None)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.Argument_Mismatch)
}

@(test)
vm_test_sub_float :: proc(t: ^testing.T) {
	program, asm_err := asm_assemble(`
		Main:
			push 34
			push 35
			sub
		end
	`)
	testing.expect(t, asm_err == AsmError.None)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.None)
	v := sm.pop_back(&vm.stack)
	testing.expect_value(t, v, i32(1))
}

// TODO: In order to restore this test, A distinction must be made between jump and call
// This requires more work in the VM and compiler
// @(test)
// vm_test_overflow :: proc(t: ^testing.T) {
// 	program: []VM_Instruction = {
// 		{.Push, f32(0xCAFE_BABE)},
// 		{.Jump, i32(0)}
// 	}
// 	vm: VM
// 	err := vm_exec(&vm, raw_data(program))
// 	testing.expect_value(t, err, VM_Error.Stack_Overflow)
// }
