package compiler

import "core:fmt"
import "core:strings"
import "core:mem"
import "base:intrinsics"

new_ast_node :: proc{
	new_ast_node_empty,
	new_ast_node_from_tokens,
}

new_ast_node_empty :: proc($T: typeid, allocator: mem.Allocator) -> ^T
	where intrinsics.type_is_subtype_of(T, AST_Node)
{
	n, _ := mem.new(T, allocator)

	base: ^AST_Node = n // dummy check
	_ = base // "Use" type to make -vet happy

	n.derived = n

	when !intrinsics.type_is_variant_of(AST_Base_Node, ^T) {
		when      intrinsics.type_has_field(T, "derived_def")  { n.derived_def = n }
		else when intrinsics.type_has_field(T, "derived_expr") { n.derived_expr = n }
		else when intrinsics.type_has_field(T, "derived_stmt") { n.derived_stmt = n }
	}

	return n
}

new_ast_node_from_tokens :: proc($T: typeid, start, end: ^Token, allocator: mem.Allocator) -> ^T
	where intrinsics.type_is_subtype_of(T, AST_Node)
{
	n := new_ast_node_empty(T, allocator)
	n.span[0] = start
	n.span[1] = end
	return n
}

dump_ast_to_string :: proc(node: ^AST_Node, allocator := context.allocator, loc := #caller_location) -> string {
	sb := strings.builder_make(allocator, loc)
	dump_ast(&sb, node)
	return strings.to_string(sb)
}

// Note: `node` changed to pointer `^AST_Node` for efficiency and `line_len` to `^int` for shared state.
dump_ast :: proc(sb: ^strings.Builder, node: ^AST_Node) {
	if node == nil do return

	if node.has_errors do fmt.sbprint(sb, "!")

	fmt.sbprint(sb, "(")
	defer fmt.sbprint(sb, ")")

	switch n in node.derived {
	case nil:
	case ^AST_Module:
		fmt.sbprint(sb, "module")
		for def in n.defs {
			fmt.sbprint(sb, " ")
			dump_ast(sb, def)
		}
	case ^AST_Number_Lit: fmt.sbprint(sb, n.v)
	case ^AST_Color_Lit: fmt.sbprint(sb, n.v)
	case ^AST_Bool_Lit: fmt.sbprint(sb, n.v)
	case ^AST_State_Lit: fmt.sbprintf(sb, ":%v", n.v)
	case ^AST_Identifier: fmt.sbprint(sb, n.name)
	case ^AST_Binary_Expr:
		fmt.sbprintf(sb, "%v ", n.op)
		dump_ast(sb, n.left)
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.right)
	case ^AST_Unary_Expr:
		fmt.sbprintf(sb, "%s_negation ", n.op)
		dump_ast(sb, n.operand)
	case ^AST_Ternary_Expr:
		fmt.sbprint(sb, "ternary_expr ")
		dump_ast(sb, n.condition)
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.expr_if)
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.expr_else)
	case ^AST_Prop_Access_Expr:
		fmt.sbprint(sb, "prop_access ")
		dump_ast(sb, n.entity)
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.property)
	case ^AST_Call_Builtin_Expr:
		fmt.sbprintf(sb, "%v", n.name)
		for arg in n.args {
			fmt.sbprint(sb, " ")
			dump_ast(sb, arg)
		}
	case ^AST_Constant_Def:
		fmt.sbprint(sb, "const_def ")
		dump_ast(sb, n.name)
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.value)
	case ^AST_Function_Def:
		fmt.sbprint(sb, "function_def ")
		dump_ast(sb, n.annotation)
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.name)
		fmt.sbprint(sb, " ")
		fmt.sbprint(sb, "(")
		for param, i in n.params {
			if i > 0 do fmt.sbprint(sb, " ")
			dump_ast(sb, param)
		}
		fmt.sbprint(sb, ")")
		fmt.sbprint(sb, " ")
		fmt.sbprint(sb, "(")
		for stmt, i in n.body {
			if i > 0 do fmt.sbprint(sb, " ")
			dump_ast(sb, stmt)
		}
		fmt.sbprint(sb, ")")
	case ^AST_Assign_Stmt:
		fmt.sbprint(sb, "assign ")
		switch t in n.target {
		case ^AST_Identifier: dump_ast(sb, t)
		case ^AST_Prop_Access_Expr: dump_ast(sb, t)
		}
		fmt.sbprint(sb, " ")
		dump_ast(sb, n.value)
	case ^AST_If_Stmt:
		fmt.sbprint(sb, "if ")
		dump_ast(sb, n.condition)
		fmt.sbprint(sb, " ")
		fmt.sbprint(sb, "(")
		for stmt, i in n.body_if {
			if i > 0 do fmt.sbprint(sb, " ")
			dump_ast(sb, stmt)
		}
		fmt.sbprint(sb, ")")
		fmt.sbprint(sb, " ")
		fmt.sbprint(sb, "(")
		for stmt, i in n.body_else {
			if i > 0 do fmt.sbprint(sb, " ")
			dump_ast(sb, stmt)
		}
		fmt.sbprint(sb, ")")
	case ^AST_Return_Stmt:
		fmt.sbprint(sb, "return")
	case ^AST_Expr_Stmt:
		fmt.sbprint(sb, "stmt_expr ")
		dump_ast(sb, n.expr)
	case ^AST_Annotation:
		for item, i in n.items {
			if i > 0 do fmt.sbprint(sb, " ")
			dump_ast(sb, item)
		}
	case ^AST_Stmt:
		switch t in n.derived_stmt {
			case ^AST_Assign_Stmt: dump_ast(sb, t)
			case ^AST_If_Stmt: dump_ast(sb, t)
			case ^AST_Return_Stmt: dump_ast(sb, t)
			case ^AST_Expr_Stmt: dump_ast(sb, t)
		}
	case ^AST_Expr:
		switch t in n.derived_expr {
			case ^AST_Ternary_Expr: dump_ast(sb, t)
			case ^AST_Binary_Expr: dump_ast(sb, t)
			case ^AST_Unary_Expr: dump_ast(sb, t)
			case ^AST_Number_Lit: dump_ast(sb, t)
			case ^AST_Color_Lit: dump_ast(sb, t)
			case ^AST_Bool_Lit: dump_ast(sb, t)
			case ^AST_State_Lit: dump_ast(sb, t)
			case ^AST_Prop_Access_Expr: dump_ast(sb, t)
			case ^AST_Identifier: dump_ast(sb, t)
			case ^AST_Call_Builtin_Expr: dump_ast(sb, t)
		}
	case ^AST_Top_Level_Def:
		switch t in n.derived_def {
		case ^AST_Function_Def: dump_ast(sb, t)
		case ^AST_Constant_Def: dump_ast(sb, t)
		}
	case:
		fmt.sbprint(sb, "UnknownAstNode")
	}
}

// Extracts the original source code slice covered by the span.
span_to_string :: proc(span: SrcSpan) -> string {
	start_raw := transmute(mem.Raw_String)span[0].raw
	end_raw   := transmute(mem.Raw_String)span[1].raw

	start_addr := uintptr(start_raw.data)
	end_addr   := uintptr(end_raw.data) + uintptr(end_raw.len)

	if start_addr > end_addr || start_raw.data == nil {
		return ""
	}

	total_len := int(end_addr - start_addr)

	result := mem.Raw_String{ data = start_raw.data, len  = total_len }
	return transmute(string)result
}
