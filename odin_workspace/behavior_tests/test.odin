package behavior_tests

import "core:testing"
import "../compiler"
import "../vm"

@(test)
branch_greater_than :: proc(t: ^testing.T) {
	source :: `
	@(entrypoint, state)
	def main:
		a = 23
		if a > 5:
			return
		end
		a = 100
	end
	`
	c := compiler.make_compiler()
	defer compiler.delete_compiler(c)
	program, ok := compiler.compile_program(c, source)
	testing.expect(t, ok, "Compiler should not produce errors")

	_vm: vm.VM
	vm.init_vm(&_vm)
	vm.run(&_vm, program)

	vm.dump_program(program)
}

@(test)
branch_less_than :: proc(t: ^testing.T) {
	source :: `
	@(entrypoint, state)
	def main:
		a = 23
		if a < 5:
			return
		end
		a = 100
	end
	`
	c := compiler.make_compiler()
	defer compiler.delete_compiler(c)
	program, ok := compiler.compile_program(c, source)
	testing.expect(t, ok, "Compiler should not produce errors")

	_vm: vm.VM
	vm.init_vm(&_vm)
	vm.run(&_vm, program)

	vm.dump_program(program)
}

@(test)
math_operations :: proc(t: ^testing.T) {
	source :: `
	@(entrypoint, state)
	def main:
		// 10 + (2 * 5) - (4 / 2) = 10 + 10 - 2 = 18
		a = 10 + 2 * 5 - 4 / 2
	end
	`
	c := compiler.make_compiler()
	defer compiler.delete_compiler(c)
	program, ok := compiler.compile_program(c, source)
	testing.expect(t, ok, "Compiler should not produce errors")

	_vm: vm.VM
	vm.init_vm(&_vm)
	vm.run(&_vm, program)

	testing.expect_value(t, _vm.stack.data[0].(f32), 18)
}

@(test)
multiple_locals :: proc(t: ^testing.T) {
	source :: `
	@(entrypoint, state)
	def main:
		a = 5
		b = 10
		c = a * b
	end
	`
	c := compiler.make_compiler()
	defer compiler.delete_compiler(c)
	program, ok := compiler.compile_program(c, source)
	testing.expect(t, ok, "Compiler should not produce errors")

	_vm: vm.VM
	vm.init_vm(&_vm)
	vm.run(&_vm, program)

	testing.expect_value(t, _vm.stack.data[0].(f32), 5)
	testing.expect_value(t, _vm.stack.data[1].(f32), 10)
	testing.expect_value(t, _vm.stack.data[2].(f32), 50)
}

@(test)
if_else_branch :: proc(t: ^testing.T) {
	source :: `
	@(entrypoint, state)
	def main:
		a = 10
		b = 0
		if a == 10:
			b = 1
		else:
			b = 2
		end
	end
	`
	c := compiler.make_compiler()
	defer compiler.delete_compiler(c)
	program, ok := compiler.compile_program(c, source)
	testing.expect(t, ok, "Compiler should not produce errors")

	_vm: vm.VM
	vm.init_vm(&_vm)
	vm.run(&_vm, program)

	testing.expect_value(t, _vm.stack.data[0].(f32), 10)
	testing.expect_value(t, _vm.stack.data[1].(f32), 1)
}

@(test)
unary_negate :: proc(t: ^testing.T) {
	source :: `
	@(entrypoint, state)
	def main:
		a = 5
		b = -a
	end
	`
	c := compiler.make_compiler()
	defer compiler.delete_compiler(c)
	program, ok := compiler.compile_program(c, source)
	testing.expect(t, ok, "Compiler should not produce errors")

	_vm: vm.VM
	vm.init_vm(&_vm)
	vm.run(&_vm, program)

	testing.expect_value(t, _vm.stack.data[0].(f32), 5)
	testing.expect_value(t, _vm.stack.data[1].(f32), -5)
}
