package compiler

SrcSpan :: [2]^Token
ast_span_extend :: proc{ast_span_extend_node, ast_span_extend_token}
ast_span_extend_node :: proc(node, to: ^AST_Node) { node.span[1] = to.span[1] }
ast_span_extend_token :: proc(node: ^AST_Node, to: ^Token) { node.span[1] = to }

AST_Node :: struct {
	span: SrcSpan,
	has_errors: bool, // Lots of room for more flags here
	derived: AST_Any_Node,
}
AST_Any_Node :: union {
	// Base Types
	^AST_Module,
	^AST_Top_Level_Def,
	^AST_Stmt,
	^AST_Expr,
	// Defs
	^AST_Function_Def,
	^AST_Constant_Def,
	// Stmts
	^AST_Assign_Stmt,
	^AST_If_Stmt,
	^AST_Return_Stmt,
	^AST_Expr_Stmt,
	// Exprs
	^AST_Ternary_Expr,
	^AST_Binary_Expr,
	^AST_Unary_Expr,
	^AST_Number_Lit,
	^AST_Color_Lit,
	^AST_Bool_Lit,
	^AST_State_Lit,
	^AST_Prop_Access_Expr,
	^AST_Identifier,
	^AST_Call_Builtin_Expr,
	// Other
	^AST_Annotation,
}

AST_Annotation :: struct {
	using base: AST_Node,
	items: []^AST_Identifier,
}

// Base Types
AST_Base_Node :: union {
	^AST_Module,
	^AST_Top_Level_Def,
	^AST_Expr,
	^AST_Stmt,
}

AST_Module :: struct {
	using base: AST_Node,
	defs: []^AST_Top_Level_Def,
}

AST_Top_Level_Def :: struct {
	using base: AST_Node,
	annotation: ^AST_Annotation,
	derived_def: union {
		^AST_Function_Def,
		^AST_Constant_Def,
	}
}

AST_Stmt :: struct {
	using base: AST_Node,
	derived_stmt: union {
		^AST_Assign_Stmt,
		^AST_If_Stmt,
		^AST_Return_Stmt,
		^AST_Expr_Stmt,
	}
}

AST_Expr :: struct {
	using base: AST_Node,
	derived_expr: union {
		^AST_Ternary_Expr,
		^AST_Binary_Expr,
		^AST_Unary_Expr,
		^AST_Number_Lit,
		^AST_Color_Lit,
		^AST_Bool_Lit,
		^AST_State_Lit,
		^AST_Prop_Access_Expr,
		^AST_Identifier,
		^AST_Call_Builtin_Expr,
	}
}

// Defs
AST_Function_Def :: struct {
	using node: AST_Top_Level_Def,
	name: ^AST_Identifier,
	params: []^AST_Identifier,
	body: []^AST_Stmt,
}

AST_Constant_Def :: struct {
	using node: AST_Top_Level_Def,
	name: ^AST_Identifier,
	value: ^AST_Expr,
}

// Statements
AST_Assign_Stmt :: struct {
	using node: AST_Stmt,
	target: union {
		^AST_Identifier,
	 	^AST_Prop_Access_Expr,
 	},
	value: ^AST_Expr,
}

AST_If_Stmt :: struct {
	using node: AST_Stmt,
	condition: ^AST_Expr,
	body_if: []^AST_Stmt,
	body_else: []^AST_Stmt,
}

AST_Return_Stmt :: struct {
	using node: AST_Stmt,
}

AST_Expr_Stmt :: struct {
	using node: AST_Stmt,
	expr: ^AST_Expr,
}

// Expressions
AST_Ternary_Expr :: struct {
	using node: AST_Expr,
	condition: ^AST_Expr,
	expr_if: ^AST_Expr,
	expr_else: ^AST_Expr,
}

AST_Binary_Expr_Op :: enum { Add, Sub, Mul, Div, Eq, Neq, Lt, Leq, Gt, Geq, And, Or }
AST_Binary_Expr :: struct {
	using node: AST_Expr,
    op:    AST_Binary_Expr_Op,
    left:  ^AST_Expr,
    right: ^AST_Expr,
}

AST_Unary_Expr :: struct {
	using node: AST_Expr,
	op: enum { Arithmetic, Logical },
    operand: ^AST_Expr,
}

AST_Number_Lit :: struct {
	using node: AST_Expr,
	v: f32
}
AST_State_Lit :: struct {
	using node: AST_Expr,
	v: string
}
AST_Identifier :: struct {
	using node: AST_Expr,
	name: string
}
AST_Color_Lit :: struct {
	using node: AST_Expr,
	v: Color
}
AST_Bool_Lit :: struct {
	using node: AST_Expr,
	v: bool
}

AST_Prop_Access_Expr :: struct {
	using node: AST_Expr,
	entity: ^AST_Expr, // Is this too permissive?
	property: ^AST_Identifier,
}

AST_Call_Builtin_Expr :: struct {
	using node: AST_Expr,
	name: string, // This is not a normal identifier, but also it seems pointless to make it's own ast node
	args: []^AST_Expr,
}
