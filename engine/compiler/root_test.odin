#+test
package compiler

import "core:fmt"
import "core:log"
import "core:testing"
import "../vm"

@(test)
test_compiler_dummy :: proc(t: ^testing.T) {
	source := #load("./test_cases/plant_test_code.pil", string)
	c: Compiler
	program, ok := compile_program(&c, source)

	log.debugf("Got this out:\n")
	vm.dump_program(program)
	test_dump_diagnostics(c.diagnostics)
}

test_dump_diagnostics :: proc(d: ^DiagnosticList)
{
	when !ODIN_DEBUG do return
	if len(d.items) == 0 do return
	for diagnostic in d.items {
		fmt.printfln(">")
		fmt.printfln("> %s",  span_to_string(diagnostic.span))
		fmt.printfln(">")
		start := diagnostic.span[0]
		fmt.printfln("Note [%v:%v]: %s", start.line, start.col, diagnostic.message)
		fmt.printfln("")
	}
}
