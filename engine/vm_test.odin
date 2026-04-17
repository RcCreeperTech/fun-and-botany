#+test
package web_testing

import sm "core:container/small_array"
import "core:testing"

@(test)
vm_test_push_pop :: proc(t: ^testing.T) {
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	program, asm_err := asm_assemble(&assembler, `
		Main:
			push 123
			push false
			pop
		end
	`)
	testing.expect(t, asm_err == nil)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.None)
	v := sm.pop_back(&vm.stack)
	testing.expect_value(t, v, i32(123))
}


@(test)
vm_test_underflow :: proc(t: ^testing.T) {
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	program, asm_err := asm_assemble(&assembler,`
		Main:
			pop
		end
	`)
	testing.expect(t, asm_err == nil)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.Stack_Underflow)
}

@(test)
vm_test_add :: proc(t: ^testing.T) {
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	program, asm_err := asm_assemble(&assembler, `
		Main:
			push 34
			push 35
			add
		end
	`)
	testing.expect(t, asm_err == nil)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.None)
	v := sm.pop_back(&vm.stack)
	testing.expect_value(t, v, i32(69))
}

@(test)
vm_test_bad_add :: proc(t: ^testing.T) {
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	program, asm_err := asm_assemble(&assembler, `
		Main:
			push 34
			push false
			add
		end
	`)
	testing.expect(t, asm_err == nil)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.Argument_Mismatch)
}

@(test)
vm_test_sub_float :: proc(t: ^testing.T) {
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	program, asm_err := asm_assemble(&assembler, `
		Main:
			push 34
			push 35
			sub
		end
	`)
	testing.expect(t, asm_err == nil)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.None)
	v := sm.pop_back(&vm.stack)
	testing.expect_value(t, v, i32(1))
}

// TODO: In order to restore this test, A distinction must be made between jump and call
@(test)
vm_test_overflow :: proc(t: ^testing.T) {
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	program, asm_err := asm_assemble(&assembler, `
		Main:
			push 123
			jump :Main
		end
	`)
	testing.expect(t, asm_err == nil)

	vm: VM
	err := vm_run(&vm, program)
	testing.expect_value(t, err, VM_Error.Stack_Overflow)
}
