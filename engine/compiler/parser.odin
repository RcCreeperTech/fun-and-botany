package compiler

import "core:mem"
import "core:fmt"


Parser :: struct {
	tokens: []Token,
	head: []Token,
	diagnostics: ^[dynamic]Diagnostic,
	arena: Dynamic_Arena, // Parsed ast nodes go in here for cache efficency
	allocator: mem.Allocator,
	panic_mode: bool
}
parser_init :: proc(self: ^Parser, tokens: []Token, diagnostics: ^[dynamic]Diagnostic, allocator := context.allocator) {
	dynamic_arena_init(&self.arena)
	self.allocator = dynamic_arena_allocator(&self.arena)
	self.diagnostics = diagnostics
	self.tokens = tokens
	self.head = tokens
}
parser_deinit :: proc(self: ^Parser) {
	dynamic_arena_destroy(&self.arena)
}

parse_program :: proc(self: ^Parser) -> ^AST_Module {
	module := new_ast_node(AST_Module, self.allocator)
	top_level_defs := make([dynamic]^AST_Top_Level_Def, self.allocator)
	for parser_peek(self).kind != .End_Of_Stream {
		if parser_eat_optional(self, .End_Of_Statement) do continue

		def := parse_top_level_def(self)

		if self.panic_mode {
			self.panic_mode = false
			parser_sync(self)
		}

		assert(def != nil)
		append(&top_level_defs, def)
	}
	module.defs = top_level_defs[:]
	return module
}

parser_sync :: proc(self: ^Parser) {
	for {
		#partial switch parser_peek(self).kind {
        // These always start a new statement or def — safe to resume
        case .Keyword_End, .Keyword_Def, .Keyword_If, .Keyword_Return, .End_Of_Stream:
            return
        case .End_Of_Statement:
            parser_advance(self)
            return
        }
        parser_advance(self)
    }
}

parse_top_level_def :: proc(self: ^Parser) -> ^AST_Top_Level_Def {
	annotation: ^AST_Annotation
	if parser_peek(self).kind == .At {
		annotation = parse_annotation(self)
	} else {
		annotation = new_ast_node(AST_Annotation, self.allocator)
	}

	start, ok := parser_expect(self, .Keyword_Def)
	if !ok {
		parser_error(self, annotation.span, "Annotation is not attached to a top level def")
		dummy := new_ast_node(AST_Top_Level_Def, self.allocator)
		dummy.annotation = annotation
		dummy.has_errors = true
		return dummy
	}

	// This is the point where we commit to parse the def and emit dummies
	ident := parse_identifier(self)
	#partial switch parser_peek(self).kind {
	case .Equals:
		return parse_constant_def(self, start, ident, annotation)
	case .Colon, .Open_Paren:
		return parse_function_def(self, start, ident, annotation)
	case:
		bad_token := parser_peek(self)
		parser_error(self, bad_token, "Encountered invalid token '%v', when trying to parse def '%v'", bad_token.raw, ident.name)
		dummy := new_ast_node(AST_Top_Level_Def, self.allocator)
		dummy.annotation = annotation
		dummy.has_errors = true
		return dummy
	}
}

parse_identifier_tuple :: proc(self: ^Parser, parent: ^AST_Node) -> []^AST_Identifier {
	open_paren := parser_expect(self, .Open_Paren, parent)
	parser_eat_optional(self, .End_Of_Statement, parent)
	items := make([dynamic]^AST_Identifier, self.allocator)
	scan: for {
		#partial switch parser_peek(self).kind {
		case .Identifier:
			ident := parse_identifier(self)
			ast_span_extend(parent, ident)
			append(&items, ident)

			parser_eat_optional(self, .Comma, parent)
			parser_eat_optional(self, .End_Of_Statement, parent)
		case .Close_Paren:
			parser_advance(self, parent)
			break scan
		case:
			parent.has_errors = true
			parser_error(self, parent.span, "'Identifier tuple must be closed with ')'")
			break scan
		}
	}
	return items[:]
}

parse_expression_tuple :: proc(self: ^Parser, parent: ^AST_Node) -> []^AST_Expr {
	open_paren := parser_expect(self, .Open_Paren, parent)
	parser_eat_optional(self, .End_Of_Statement, parent)
	items := make([dynamic]^AST_Expr, self.allocator)
	scan: for {
		head := parser_peek(self)
		switch {
		case is_valid_start_of_expression(head.kind):
			expr := parse_expression(self)
			ast_span_extend(parent, expr)
			append(&items, expr)

			parser_eat_optional(self, .Comma, parent)
			parser_eat_optional(self, .End_Of_Statement, parent)
		case head.kind == .Close_Paren:
			parser_advance(self, parent)
			break scan
		case:
			parent.has_errors = true
			parser_error(self, parent.span, "Expression tuple must be closed with ')'")
			break scan
		}
	}
	return items[:]
}

is_valid_start_of_expression :: proc(kind: Token_Kind) -> bool {
	if kind == .Literal_Number do return true
	if kind == .Literal_Color do return true
	if kind == .Literal_Boolean do return true
	if kind == .Literal_State_Label do return true
	if kind == .Identifier do return true
	if kind == .Builtin_Identifier do return true
	if kind == .Builtin_Identifier do return true
	if kind == .Open_Paren do return true
	if kind == .Minus do return true
	if kind == .Exclamation do return true
	return false
}

parse_function_def :: proc(self: ^Parser, start: ^Token, name: ^AST_Identifier, annotation: ^AST_Annotation) -> ^AST_Function_Def {
	def := new_ast_node(AST_Function_Def, start, parser_peek(self), self.allocator)
	def.name = name
	def.span[0] = start
	def.annotation = annotation

	if parser_peek(self).kind == .Open_Paren {
		def.params = parse_identifier_tuple(self, def)
	}

	parser_expect(self, .Colon, def)
	parser_expect(self, .End_Of_Statement, def)

	stmts := make([dynamic]^AST_Stmt, self.allocator)
	for parser_peek(self).kind != .Keyword_End {
		if parser_eat_optional(self, .End_Of_Statement) do continue

		stmt := parse_stmt(self)
		ast_span_extend(def, stmt)

		if self.panic_mode { // Q: is this a good place to sync?
			self.panic_mode = false
			parser_sync(self)
		}

		append(&stmts, stmt)
	}
	def.body = stmts[:]

	parser_expect(self, .Keyword_End, def)

	return def
}

parse_stmt :: proc(self: ^Parser) -> ^AST_Stmt {
	kind := parser_peek(self).kind
	switch {
	case is_valid_start_of_expression(kind):
		left_expr := parse_expression(self)

		if parser_peek(self).kind == .Equals {
			return parse_assign_stmt(self, left_expr)
		}

		stmt := new_ast_node(AST_Expr_Stmt, self.allocator)
		stmt.expr = left_expr
		parser_expect(self, .End_Of_Statement)
		return stmt
	case kind == .Keyword_If:
		return parse_if_stmt(self)
	case kind == .Keyword_Return:
		stmt := new_ast_node(AST_Return_Stmt, self.allocator)
		parser_expect(self, .Keyword_Return, stmt)
		parser_expect(self, .End_Of_Statement, stmt)
		return stmt
	case:
		bad_token := parser_advance(self)
		parser_error(self, bad_token, "Encountered invalid token '%v' when trying to parse statement.", bad_token.raw)
		bad_stmt := new_ast_node(AST_Stmt, self.allocator)
		bad_stmt.has_errors = true
		bad_stmt.span = bad_token
		return bad_stmt
	}
}

parse_assign_stmt :: proc(self: ^Parser, left_expr: ^AST_Expr) -> ^AST_Stmt {
	stmt := new_ast_node(AST_Assign_Stmt, self.allocator)
	stmt.span = left_expr.span

	// Validate that the expression we parsed is a valid l-value
	#partial switch v in left_expr.derived_expr {
	case ^AST_Identifier:
		stmt.target = v
	case ^AST_Prop_Access_Expr:
		stmt.target = v
	case:
		parser_error(self, stmt.span, "Invalid assignment target. Must be an identifier or property access.")
		stmt.has_errors = true
		return stmt
	}

	parser_expect(self, .Equals, stmt)

	stmt.value = parse_expression(self)
	ast_span_extend(stmt, stmt.value)

	parser_expect(self, .End_Of_Statement, stmt)

	return stmt
}

parse_if_stmt :: proc(self: ^Parser) -> ^AST_If_Stmt {
	stmt := new_ast_node(AST_If_Stmt, self.allocator)
	keyword_if := parser_advance(self)
	stmt.span = keyword_if

	stmt.condition = parse_expression(self)
	ast_span_extend(stmt, stmt.condition)

	parser_expect(self, .Colon, stmt)
	parser_expect(self, .End_Of_Statement, stmt)

	body_if := make([dynamic]^AST_Stmt)
	for {
		if parser_eat_optional(self, .End_Of_Statement) do continue
		next := parser_peek(self)
		if next.kind == .Keyword_Else || next.kind == .Keyword_End do break

		s := parse_stmt(self)
		ast_span_extend(stmt, s)

		append(&body_if, s)
	}
	stmt.body_if = body_if[:]

	#partial switch parser_peek(self).kind {
	case .Keyword_End:
		parser_advance(self, stmt)
		parser_expect(self, .End_Of_Statement, stmt)
	case .Keyword_Else:
		parser_advance(self, stmt)
		parser_expect(self, .Colon, stmt)
		parser_expect(self, .End_Of_Statement, stmt)

		body_else := make([dynamic]^AST_Stmt)
		for {
			if parser_eat_optional(self, .End_Of_Statement) do continue
			next := parser_peek(self)
			if next.kind == .Keyword_End do break

			s := parse_stmt(self)
			ast_span_extend(stmt, s)

			append(&body_else, s)
		}
		stmt.body_else = body_else[:]

		parser_expect(self, .Keyword_End, stmt)
		parser_expect(self, .End_Of_Statement, stmt)
	}

	return stmt

}

parse_constant_def :: proc(self: ^Parser, start: ^Token, name: ^AST_Identifier, annotation: ^AST_Annotation) -> ^AST_Constant_Def {
	def := new_ast_node(AST_Constant_Def, start, parser_peek(self), self.allocator)
	def.name = name
	def.span[0] = start
	def.annotation = annotation
	def.value = parse_expression(self)
	ast_span_extend(def, def.value)

	if eos, ok := parser_expect(self, .End_Of_Statement); !ok {
		def.has_errors = true
		return def
	}

	return def
}

parse_annotation :: proc(self: ^Parser) -> ^AST_Annotation {
	annotation := new_ast_node(AST_Annotation, self.allocator)
	annotation.span[0] = parser_advance(self)

	#partial switch parser_peek(self).kind {
		case .Open_Paren:
			annotation.items = parse_identifier_tuple(self, annotation)
		case .Identifier:
			items := make([dynamic]^AST_Identifier, self.allocator)
			ident := parse_identifier(self)
			ast_span_extend(annotation, ident)
			append(&items, ident)
			annotation.items = items[:]
		case:
			bad_token := parser_advance(self, annotation)
			annotation.has_errors = true
			parser_error(self, annotation.span, "Unrecognized token '%v' after @", bad_token.raw)
	}

	parser_eat_optional(self, .End_Of_Statement, annotation)

	return annotation
}

parse_identifier :: proc(self: ^Parser) -> ^AST_Identifier {
	ident := new_ast_node(AST_Identifier, self.allocator)
	token := parser_advance(self)
	ident.span = token
	#partial switch token.kind {
	case .Identifier:
		ident.name = token.raw
	case:
		ident.name = "<error>"
		ident.has_errors = true
		parser_error(self, ident.span, "'%v' is not a valid identifier", token.raw)
	}
	return ident
}

Precedence :: enum {
	None,
	Assignment,  // =
	Ternary,     // if ... else
	Logical_Or,  // ||
	Logical_And, // &&
	Equality,    // == !=
	Comparison,  // < > <= >=
	Term,        // + -
	Factor,      // * /
	Unary,       // ! -
	Call,        // . () []
	Primary,
}
@(private, rodata)
precedence_table: [Token_Kind]Precedence = #partial {
	.Exclamation         = .Term,
	.Minus               = .Term,
	.Plus                = .Term,
	.Asterisk            = .Factor,
	.Forward_Slash       = .Factor,
	.Keyword_And         = .Logical_And,
	.Keyword_Or          = .Logical_Or,
	.Less                = .Comparison,
	.Less_Equals         = .Comparison,
	.Greater             = .Comparison,
	.Greater_Equals      = .Comparison,
	.Equals_Equals       = .Equality,
	.Exclamation_Equals  = .Equality,
	.Keyword_If          = .Ternary,
	.Period              = .Call,
}
parse_expression :: proc(self: ^Parser, precedence: Precedence = .Assignment) -> ^AST_Expr {
	left: ^AST_Expr
	#partial switch parser_peek(self).kind {
	case .Literal_Number:
		token := parser_advance(self)
		expr := new_ast_node(AST_Number_Lit, self.allocator)
		expr.v = token.literal_value.(f32)
		expr.span = token
		left = expr
	case .Literal_Color:
		token := parser_advance(self)
		expr := new_ast_node(AST_Color_Lit, self.allocator)
		expr.v = token.literal_value.(Color)
		expr.span = token
		left = expr
	case .Literal_Boolean:
		token := parser_advance(self)
		expr := new_ast_node(AST_Bool_Lit, self.allocator)
		expr.v = token.literal_value.(bool)
		expr.span = token
		left = expr
	case .Literal_State_Label:
		token := parser_advance(self)
		expr := new_ast_node(AST_State_Lit, self.allocator)
		expr.v = token.literal_value.(string)
		expr.span = token
		left = expr
	case .Identifier:
		left = parse_identifier(self)
	case .Builtin_Identifier:
		left = parse_builtin_call(self)
	case .Open_Paren:
		left = parse_grouping(self)
	case .Minus, .Exclamation:
		left = parse_unary(self)
	case:
		token := parser_advance(self)
		switch {
		case token.kind == .End_Of_Statement:
			parser_error(self, token, "Expected an expression but found the end of the line.")
		case token.kind == .End_Of_Stream:
			parser_error(self, token, "Expected an expression but found the end of the file.")
		case:
			parser_error(self, token, "Expected expression but found a(n) %v: '%v'.", token.kind, token.raw)
		}
		// Return a dummy AST_Expr node here to prevent null pointer crashes downstream
		dummy := new_ast_node(AST_Expr, self.allocator)
		dummy.has_errors = true
		dummy.span = token
		return dummy
	}

	// Keep parsing as long as the upcoming token has a higher or equal precedence
	for  {
		next := parser_peek(self)
		next_precedence := precedence_table[next.kind]

		if precedence > next_precedence do break

		#partial switch parser_peek(self).kind {
		case .Minus, .Plus, .Asterisk, .Forward_Slash: fallthrough
		case .Keyword_And, .Keyword_Or: fallthrough
		case .Less, .Less_Equals, .Greater, .Greater_Equals: fallthrough
		case .Equals_Equals, .Exclamation_Equals:
			left = parse_binary(self, left)
		case .Keyword_If:
			left = parse_ternary(self, left)
		case .Period:
			left = parse_property(self, left)
		}
	}

	return left
}

parse_binary :: proc(self: ^Parser, left: ^AST_Expr) -> ^AST_Expr {
	expr := new_ast_node(AST_Binary_Expr, self.allocator)
	expr.left = left
	expr.span = left.span

	operator := parser_advance(self, expr)
	#partial switch operator.kind {
	case .Plus: expr.op = .Add
	case .Minus: expr.op = .Sub
	case .Asterisk: expr.op = .Mul
	case .Forward_Slash: expr.op = .Div
	case .Equals_Equals: expr.op = .Eq
	case .Exclamation_Equals: expr.op = .Neq
	case .Less: expr.op = .Lt
	case .Less_Equals: expr.op = .Leq
	case .Greater: expr.op = .Gt
	case .Greater_Equals: expr.op = .Geq
	case .Keyword_And: expr.op = .And
	case .Keyword_Or: expr.op = .Or
	case: unreachable()
	}


	// We parse the right-hand side using one precedence level strictly higher
	// than the current operator to enforce left-associativity.
	expr.right = parse_expression(self, Precedence(int(precedence_table[operator.kind]) + 1))

	ast_span_extend(expr, expr.right)
	return expr
}

parse_property :: proc(self: ^Parser, left: ^AST_Expr) -> ^AST_Expr {
	expr := new_ast_node(AST_Prop_Access_Expr, self.allocator)
	expr.entity = left
	expr.span = left.span

	period := parser_advance(self, expr)
	ident := parse_identifier(self)
	expr.property = ident
	ast_span_extend(expr, ident)

	return expr
}

// Parses inline conditionals: or_expr "if" or_expr "else" or_expr
// E.g. `a if b else c` -> The `if` token receives `a` as the left expression.
parse_ternary :: proc(self: ^Parser, left: ^AST_Expr) -> ^AST_Expr {
	expr := new_ast_node(AST_Ternary_Expr, self.allocator)

	// The left-hand side is the true-branch
	expr.expr_if = left
	expr.span = expr.expr_if.span

	if_identifier := parser_advance(self, expr)
	// Parse the condition (`b`)
	expr.condition = parse_expression(self, .Ternary)
	ast_span_extend(expr, expr.condition)

	if keyword_else, ok := parser_expect(self, .Keyword_Else); !ok {
		expr.has_errors = true
		parser_error(self, expr.span, "Expected to see an else when parsing ternary expression")
		return expr
	} else {
		ast_span_extend(expr, keyword_else)
	}

	// Parse the false-branch (`c`).
	// We use exact precedence (.Ternary) to make it right-associative (chainable).
	expr.expr_else = parse_expression(self, .Ternary)
	ast_span_extend(expr, expr.expr_else)

	return expr
}

parse_builtin_call :: proc(self: ^Parser) -> ^AST_Expr {
	token := parser_advance(self)
	expr := new_ast_node(AST_Call_Builtin_Expr, self.allocator)
	expr.name = token.raw
	expr.span = token

	if parser_peek(self).kind == .Open_Paren {
		expr.args = parse_expression_tuple(self, expr)
	}

	return expr
}

parse_grouping :: proc(self: ^Parser) -> ^AST_Expr {
	open_paren := parser_advance(self)
	expr := parse_expression(self)

	if close_paren, ok := parser_expect(self, .Close_Paren); ok {
		expr.span = {open_paren, close_paren}
	} else {
		parser_error(self, {open_paren, expr.span[1]}, "'(' must be closed with ')'")
		expr.has_errors = true
	}

	return expr
}

parse_unary :: proc(self: ^Parser) -> ^AST_Expr {
	uop := parser_advance(self)
	expr := new_ast_node(AST_Unary_Expr, self.allocator)
	expr.span = uop
	expr.op = .Arithmetic if uop.kind == .Minus else .Logical

	expr.operand = parse_expression(self, .Unary)
	ast_span_extend(expr, expr.operand)

	return expr
}

@(private="file", rodata)
dummy_eos: Token = { kind = .End_Of_Stream }

parser_peek :: proc(self: ^Parser, caller := #caller_location, expp := #caller_expression) -> ^Token {
	if self.head == nil {
		return &dummy_eos
	}
	if len(self.head) == 0 {
		return &dummy_eos
	}
	return &self.head[0]
}
parser_advance :: proc(self: ^Parser, node: ^AST_Node = nil) -> ^Token {
	result: ^Token
	for {
		next := parser_peek(self)
		if next.kind == .End_Of_Stream {
			result = next
			break
		}
		current := &self.head[0]
		self.head = self.head[1:]
		if current.kind != .Error {
			result = current
			break
		}
	}

	if node != nil {
		ast_span_extend(node, result)
	}

	return result
}

parser_had_errors :: proc(self: ^Parser) -> bool { return len(self.diagnostics) > 0 }
parser_error :: proc(self: ^Parser, span: SrcSpan, msg: string, args: ..any) {
	self.panic_mode = true
	diagnostic := Diagnostic{
		subsystem = .parser,
		span = span,
		message = fmt.aprintf(msg, ..args, allocator=self.allocator)
	}
	append(self.diagnostics, diagnostic)
}

parser_expect :: proc(self: ^Parser, token_kind: Token_Kind, building: ^AST_Node = nil) -> (^Token, bool) #optional_ok {
    tok := parser_peek(self)
    if tok.kind == token_kind {
   		return parser_advance(self, building), true
    } else {
    	if building != nil do building.has_errors = true
	    parser_error(self, tok, "Expected %v but got %v.", token_kind, tok.kind)
	    return tok, false
    }
}

parser_eat_optional :: proc(self: ^Parser, token_kind: Token_Kind, building: ^AST_Node = nil) -> bool {
	tok := parser_peek(self)
	if tok.kind == token_kind {
   		parser_advance(self, building)
     	return true
    }
    return false
}
