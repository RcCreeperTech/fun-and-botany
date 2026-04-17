#+test
package web_testing

import "core:fmt"
import "core:math"
import "core:log"
import "core:strings"
import "core:testing"

@(test)
asm_test_constants :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/constants.asm", string)
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)

	// Expected Program Output
	expected := VM_Program {
	    blocks = {
	        {
	            { op = .Push,  imm = { i32(1337), nil, } },
	            { op = .Push,  imm = { f32(3.14159), nil, } },
	            { op = .Push,  imm = { Color { 255, 0, 0, 255, }, nil, } },
	            { op = .Push,  imm = { i32(4), nil, } },
	        },
	        {
	            { op = .Push,  imm = { i32(4), nil, } },
	        },
	        {
	            { op = .Push,  imm = { i32(1337), nil, } },
	            { op = .Push,  imm = { Color { 255, 0, 0, 255, }, nil, } },
	            { op = .Push,  imm = { true, nil, } },
	            { op = .Push,  imm = { true, nil, } },
	            { precondition = .Eq,  op = .Push,  imm = { Color { 255, 0, 0, 255, }, Color { 255, 0, 255, 0, }, } },
	            { op = .Push,  imm = { i32(4), nil, } },
	        },
	        {
	            { op = .Push,  imm = { i32(456), nil, } },
	        },
	    }
	}
	expect_program(t, prog, expected)
}

@(test)
asm_test_simple :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/simple.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)

	expected := VM_Program {
		blocks = {{{op = .Push, imm = {1.23, nil}}}},
	}

	expect_program(t, prog, expected)
}

@(test)
asm_test_get_set :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/get_set.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)

	dump_program(prog)
	// expect_program(t, prog, expected)
}

@(test)
asm_test_get_set_failing :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/get_set_failing.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, ProgramError.Unknown_Parameter)

	dump_program(prog)
	// expect_program(t, prog, expected)
}

@(test)
asm_test_basic_ops :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/basic_ops.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)

	expected := VM_Program {
		blocks = {
			{
				{op = .Push, imm = {i32(1), nil}},
				{op = .Push, imm = {i32(2), nil}},
				{op = .Pop},
				{op = .Push, imm = {i32(0), nil}},
				{op = .Push, imm = {i32(0), nil}},
				{precondition = .Eq, op = .Pop},
				{op = .Push, imm = {i32(1), nil}},
				{op = .Push, imm = {i32(2), nil}},
				{op = .Add},
				{op = .Push, imm = {i32(3), nil}},
				{op = .Push, imm = {i32(0), nil}},
				{op = .Push, imm = {i32(0), nil}},
				{precondition = .Eq, op = .Add},
				{op = .Push, imm = {i32(6), nil}},
				{op = .Subtract},
				{op = .Push, imm = {i32(0), nil}},
				{precondition = .Eq, op = .Rand},
				{op = .Pop},
				{op = .Push, imm = {i32(3), nil}},
				{op = .Push, imm = {i32(4), nil}},
				{op = .Push, imm = {i32(1000), nil}},
				{op = .Push, imm = {f32(0.5), nil}},
				{op = .Multiply},
				{op = .Push, imm = {i32(1000), nil}},
				{precondition = .Gt, op = .Multiply},
				{op = .Push, imm = {i32(3), nil}},
				{op = .Divide},
			},
		},
	}
	expect_program(t, prog, expected)
}

@(test)
asm_test_push_then_pop :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/push_then_pop.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)
	expected := VM_Program {
		blocks = {
			{
				{op = .Push, imm = {i32(123), nil}},
				{op = .Pop},
				{op = .Push, imm = {i32(456), nil}},
				{op = .Push, imm = {i32(1), nil}},
				{op = .Push, imm = {i32(1), nil}},
				{precondition = .Eq, op = .Pop},
			},
		},
	}
	expect_program(t, prog, expected)
}

@(test)
asm_test_push_literals :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/push_literals.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)
	expected := VM_Program {
		blocks = {
			{
				{op = .Push, imm = {f32(0.1), nil}},
				{op = .Push, imm = {i32(1234), nil}},
				{op = .Push, imm = {i32(-1234), nil}},
				{op = .Push, imm = {f32(0.1), nil}},
				{op = .Push, imm = {f32(-0.119999997), nil}},
				{op = .Push, imm = {i32(1), nil}},
				{op = .Push, imm = {i32(0), nil}},
				{op = .Push, imm = {true, nil}},
				{op = .Push, imm = {false, nil}},
				{op = .Push, imm = {Color{255, 24, 24, 24}, nil}},
				{op = .Push, imm = {Color{255, 88, 24, 40}, nil}},
			},
		},
	}
	expect_program(t, prog, expected)
}

@(test)
asm_test_push_with_precond :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/push_with_precond.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)
	expected := VM_Program {
		blocks = {
			{
				{op = .Push, imm = {i32(100), nil}},
				{op = .Push, imm = {i32(200), nil}},
				{precondition = .Gt, op = .Push, imm = {i32(1001), i32(1234)}},
			},
		},
	}
	expect_program(t, prog, expected)
}

@(test)
asm_test_jump_around :: proc(t: ^testing.T) {
	source: string = #load("./test_cases/jump_around.asm")
	assembler: Assembler
	asm_init(&assembler)
	defer asm_cleanup(&assembler)
	prog, err := asm_assemble(&assembler, source)
	testing.expect_value(t, err, nil)

	expected := VM_Program {
		blocks = {
			{
				{op = .Push, imm = {i32(1), nil}},
				{op = .Push, imm = {i32(0), nil}},
				{precondition = .Eq, op = .Jump, imm = {VM_Label(1), VM_Label(2)}},
			},
			{{op = .Push, imm = {i32(67), nil}}},
			{{op = .Push, imm = {i32(123), nil}}, {op = .Jump, imm = {VM_Label(3), nil}}},
			{{op = .Jump, imm = {VM_Label(1), nil}}},
		},
	}
	expect_program(t, prog, expected)
}


dump_program :: proc(p: VM_Program) {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	fmt.sbprintln(&sb)
	fmt.sbprintln(&sb, "// Expected Program Output")
	fmt.sbprintln(&sb, "expected := VM_Program {")
	fmt.sbprintln(&sb, "    blocks = {")
	for block, i in p.blocks {
		fmt.sbprintln(&sb, "        {")
		for inst in block {
			fmt.sbprint(&sb, "            {")
			if inst.precondition != .None {
				fmt.sbprintf(&sb, " precondition = .%v, ", inst.precondition)
			}
			fmt.sbprintf(&sb, " op = .%v, ", inst.op)
			if inst.imm[0] != nil || inst.imm[1] != nil {
				fmt.sbprint(&sb, " imm = { ")
				for val in inst.imm {
					print_vm_value(&sb, val)
				}
				fmt.sbprint(&sb, "} ")
			}
			fmt.sbprintln(&sb, "},")
		}
		fmt.sbprintln(&sb, "        },")
	}
	fmt.sbprintln(&sb, "    }")
	fmt.sbprintln(&sb, "}")
	out := strings.to_string(sb)
	log.info(out)

	print_vm_value :: proc(sb: ^strings.Builder, val: VM_Value) {
		switch v in val {
		case nil:
			fmt.sbprint(sb, "nil, ")
		case Color:
			fmt.sbprint(sb, "Color { ")
			for channel in v {
				fmt.sbprint(sb, channel)
				fmt.sbprint(sb, ", ")
			}
			fmt.sbprint(sb, "}, ")
		case f32:
			fmt.sbprintf(sb, "f32(%v), ", v)
		case i32:
			fmt.sbprintf(sb, "i32(%v), ", v)
		case bool:
			fmt.sbprintf(sb, "%v, ", v)
		case VM_Label:
			fmt.sbprintf(sb, "VM_Label(%v), ", v)
		case VM_Param:
			fmt.sbprintf(sb, "VM_Param.%v, ", v)
		}
	}
}

expect_program :: proc(t: ^testing.T, program, expected: VM_Program) {
	testing.expect(
		t,
		len(program.blocks) == len(expected.blocks),
		"Program generated with incorrect number of blocks",
	)
	for i in 0 ..< len(expected.blocks) {
		p := program.blocks[i]
		e := expected.blocks[i]
		testing.expect_value(t, len(p), len(e))
		for j in 0 ..< len(e) {
			inst := p[j]
			einst := e[j]
			testing.expect_value(t, inst, einst)
		}
	}
}
