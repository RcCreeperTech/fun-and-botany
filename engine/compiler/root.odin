package compiler

import "core:log"
import "base:runtime"

Compiler :: struct{
}
CompilerError :: union #shared_nil {
}

VM_Program :: struct {}

lang_compile_program :: proc(
	self: ^Compiler,
	source: string,
	allocator := context.allocator,
) -> (
	program: VM_Program,
	err: CompilerError,
) {
	scanner := Scanner {
		source = source,
		head = source,
	}

	tokens := make([dynamic]Token, allocator)
	for {
		tok := scanner_next(&scanner)
		append(&tokens, tok)
		if tok.kind == .End_Of_Stream do break
	}

	parser: Parser
	parser_init(&parser, tokens[:], allocator)


	// self.ast = parse_program(&parser)
	// if parser_had_errors(&parser) {
	// 	for error in parser.errors {
	// 		log.errorf("(%v:%v): %v", error.span.start.line, error.span.start.col, error.message)
	// 	}
	// }

	return
}
