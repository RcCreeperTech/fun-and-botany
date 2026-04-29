#+test
package compiler

import "core:log"
import "core:testing"

@(test)
test_parser_binops :: proc(t: ^testing.T) {
	test_parse_expression(t, "a + b",   "(Add (a) (b))" )
	test_parse_expression(t, "a - b",   "(Sub (a) (b))" )
	test_parse_expression(t, "a / b",   "(Div (a) (b))" )
	test_parse_expression(t, "a * b",   "(Mul (a) (b))" )
	test_parse_expression(t, "a == b",  "(Eq (a) (b))"  )
	test_parse_expression(t, "a != b",  "(Neq (a) (b))" )
	test_parse_expression(t, "a < b",   "(Lt (a) (b))"  )
	test_parse_expression(t, "a <= b",  "(Leq (a) (b))" )
	test_parse_expression(t, "a > b",   "(Gt (a) (b))"  )
	test_parse_expression(t, "a >= b",  "(Geq (a) (b))" )
	test_parse_expression(t, "a and b", "(And (a) (b))" )
	test_parse_expression(t, "a or b",  "(Or (a) (b))"  )

	eof_err := "Expected an expression but found the end of the file."
	test_parse_expression(t, "a + ",   "(Add (a) !())", eof_err)
	test_parse_expression(t, "a - ",   "(Sub (a) !())", eof_err)
	test_parse_expression(t, "a / ",   "(Div (a) !())", eof_err)
	test_parse_expression(t, "a * ",   "(Mul (a) !())", eof_err)
	test_parse_expression(t, "a == ",  "(Eq (a) !())",  eof_err)
	test_parse_expression(t, "a != ",  "(Neq (a) !())", eof_err)
	test_parse_expression(t, "a < ",   "(Lt (a) !())",  eof_err)
	test_parse_expression(t, "a <= ",  "(Leq (a) !())", eof_err)
	test_parse_expression(t, "a > ",   "(Gt (a) !())",  eof_err)
	test_parse_expression(t, "a >= ",  "(Geq (a) !())", eof_err)
	test_parse_expression(t, "a and ", "(And (a) !())", eof_err)
	test_parse_expression(t, "a or ",  "(Or (a) !())",  eof_err)
}

@(test)
test_parser_functions :: proc(t: ^testing.T) {
	test_parse_program(t,
		`def foo():
			return
		end`,
		"(module (function_def () (foo) () ((return))))",
	)

	test_parse_program(t,
		`def foo()
		end`,
		"(module !(function_def () (foo) () ()))",
		"Expected Colon but got End_Of_Statement."
	)

	test_parse_program(t,
		`def foo()
			return
		end`,
		"(module !(function_def () (foo) () ((return))))",
		"Expected Colon but got End_Of_Statement."
	)


	test_parse_program(t,
		`def foo():
			6 + 7
		end`,
		"(module (function_def () (foo) () ((stmt_expr (Add (6) (7))))))",
	)

	test_parse_program(t,
		`def foo():
			funny = 6 + 7
		end`,
		"(module (function_def () (foo) () ((assign (funny) (Add (6) (7))))))"
	)

	test_parse_program(t,
		`
		@Super_Cool_Annotation
		def foo():
			funny = return
		end`,
		"(module (function_def ((Super_Cool_Annotation)) (foo) () ((assign (funny) !()))))",
		"Expected expression but found a(n) Keyword_Return: 'return'."
	)


	test_parse_program(t,
		`
		@(foo, bar, baz, )
		def foo():
			funny =
		end`,
		"(module (function_def ((foo) (bar) (baz)) (foo) () (!(assign (funny) !()))))",
		"Expected an expression but found the end of the line.",
		"Expected End_Of_Statement but got Keyword_End."
	)

	test_parse_program(t,
		`def foo():
			hello = true
			else: // This should error but keep going
			goodbye = false
		end`,
		"(module (function_def () (foo) () ((assign (hello) (true)) !() (assign (goodbye) (false)))))",
		"Encountered invalid token 'else' when trying to parse statement."
	)

	test_parse_program(t,
		`
			def complex_func( a, b,
				c,
			):
				$Builtin(
					1,
					2,
				)
			end
		`,
		"(module (function_def () (complex_func) ((a) (b) (c)) ((stmt_expr ($Builtin (1) (2))))))"
	)

	test_parse_program(t,
	`

		def foo(

		):
			if a == 1:
				if b == 2:

					cell.state = :node
				else:
					cell.state = :stem

				end
			else:

				return
			end
		end
	`,
	"(module (function_def () (foo) () ((if (Eq (a) (1)) ((if (Eq (b) (2)) ((assign (prop_access (cell) (state)) (:node))) ((assign (prop_access (cell) (state)) (:stem))))) ((return))))))"
	)
}

@(test)
test_parser_operator_precedence :: proc(t: ^testing.T) {
	test_parse_expression(t,
		"b or c and d == e + f * g / -h",
		"(Or (b) (And (c) (Eq (d) (Add (e) (Div (Mul (f) (g)) (Arithmetic_negation (h)))))))",
	)
}

@(test)
test_parser_ternarys :: proc(t: ^testing.T) {
	test_parse_program(t,
		`def foo:
			value = 6 + 7 if c > 10 else d * 2
		end`,
		"(module (function_def () (foo) () ((assign (value) (ternary_expr (Gt (c) (10)) (Add (6) (7)) (Mul (d) (2)))))))"
	)
	test_parse_program(t,
		`def foo:
			chain = 1 if true else 2 if false else 3 if a == b else 4
		end`,
		"(module (function_def () (foo) () ((assign (chain) (ternary_expr (true) (1) (ternary_expr (false) (2) (ternary_expr (Eq (a) (b)) (3) (4))))))))"
	)
}

@(private="file")
make_test_parser :: proc(source: string, arena: ^Dynamic_Arena) -> ^Parser {
	tokens := scanner_collect(source)
	parser := new(Parser)
	arena_allocator := dynamic_arena_allocator(arena)
	diagnostics := make_diagnostic_list(arena)
	parser_init(parser, tokens, diagnostics, arena)
	return parser
}

@(private="file")
delete_test_parser :: proc(p: ^Parser) {
	delete(p.tokens)
	free(p)
}

@(private="file")
expect_diagnostics :: proc(t: ^testing.T, diagnostics: ^DiagnosticList, expected: ..string) {
	testing.expect(t, len(diagnostics.items) == len(expected), "The number of diagnostics must match")

	for i in 0..<len(diagnostics.items) {
		testing.expect_value(t, diagnostics.items[i].message, expected[i])
		// TODO: How to handle the span
	}
}

test_parse_expression :: proc(t: ^testing.T, source: string, expected: string, expected_diagnostics: ..string) {
	arena: Dynamic_Arena
	dynamic_arena_init(&arena)
	defer dynamic_arena_destroy(&arena)

	p := make_test_parser(source, &arena)
	defer delete_test_parser(p)

	expr := parse_expression(p)
	should_have_errors := len(expected_diagnostics) > 0
	testing.expect(t, should_have_errors == (len(p.diagnostics.items) > 0))

	tuple := dump_ast_to_string(expr)
	defer delete(tuple)

	log.debug("\n\nAst:", tuple, "\n\n")
	testing.expect_value(t, tuple, expected)

	test_dump_diagnostics(p.diagnostics)
	expect_diagnostics(t, p.diagnostics, ..expected_diagnostics)
}

test_parse_program :: proc(t: ^testing.T, source: string, expected: string, expected_diagnostics: ..string) {
	arena: Dynamic_Arena
	dynamic_arena_init(&arena)
	defer dynamic_arena_destroy(&arena)

	tokens := scanner_collect(source)
	defer delete(tokens)

	diagnostics := make_diagnostic_list(&arena)

	ast := parser_collect(tokens, diagnostics, &arena)

	should_have_errors := len(expected_diagnostics) > 0
	testing.expect(t, should_have_errors == (len(diagnostics.items) > 0))

	tuple := dump_ast_to_string(ast)
	defer delete(tuple)

	log.debug("\n\nAst:", tuple, "\n\n")
	testing.expect_value(t, tuple, expected)

	test_dump_diagnostics(diagnostics)
	expect_diagnostics(t, diagnostics, ..expected_diagnostics)
}
