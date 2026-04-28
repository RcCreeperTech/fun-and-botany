package compiler

import "../vm"
import "core:log"

Type_Class :: enum {
	Unknown, // Polymorphic or currently un-inferrable
	Number,
	State,
	Color,
	Bool,
	Poison, // Poison value to prevent cascading diagnostics
}

Sema_Context :: struct {
	locals:      map[string]int,
	local_types: map[string]Type_Class, // NEW: Track types for unification
	local_count: int,
	inside_state_function: bool
}


def_has_annotation :: proc(def: ^AST_Top_Level_Def, name: string) -> bool {
	for a in def.annotation.items { if a.name == name do return true }
	return false
}

sema_resolve_globals :: proc(self: ^Compiler) {
	for def in self.ast.defs {

		if def_has_annotation(def, "state") {
			func, is_func := def.derived_def.(^AST_Function_Def)
			if !is_func {
				sema_error(self, def.span, "Cannot register a constant as a state.")
				continue
			}

			if func.name.has_errors do continue
			name := func.name.name

			// Prevent duplicate state names
			if name in self.state_table {
				sema_error(self, func.span, "State ':%s' is already defined.", name)
				continue
			}


			uid: vm.Label
			switch {
			case def_has_annotation(def, "entrypoint"): uid = vm.Label(0)
			case def_has_annotation(def, "terminal"):   uid = vm.Label(1)
			case: uid = alloc_block(self)
			}
			self.state_table[name] = uid
			log.debugf("Registered state ':%s' -> vm.Label(%d)", name, uid)
		}

		if def_has_annotation(def, "entrypoint") {
			func, is_func := def.derived_def.(^AST_Function_Def)
			if !is_func {
				sema_error(self, def.span, "Cannot make a constant the entrypoint of the program.")
				continue
			}

			if func.name.has_errors do continue
			name := func.name.name

			if name not_in self.state_table {
				sema_error(self, func.span, "Entrypoint must be a state, try adding the '@state' annotation", name)
				continue
			}

			if entrypoint, ok := self.entrypoint.(string); !ok {
				self.entrypoint = name
			} else {
				sema_error(self, func.span,
					"Cannot have more than one entrypoint. Already marked '%s' as the entrypoint.",
					entrypoint
				)
			}
		}

		if def_has_annotation(def, "terminal") {
			func, is_func := def.derived_def.(^AST_Function_Def)
			if !is_func {
				sema_error(self, def.span, "Cannot make a constant the termination point of the program.")
				continue
			}

			if func.name.has_errors do continue
			name := func.name.name

			if name not_in self.state_table {
				sema_error(self, func.span, "Terminal must be a state, try adding the '@state' annotation", name)
				continue
			}

			if entrypoint, ok := self.terminal.(string); !ok {
				self.terminal = name
			} else {
				sema_error(self, func.span,
					"Cannot have more than one terminal. Already marked '%s' as the termination point.",
					entrypoint
				)
			}
		}

		switch d in def.derived_def {
		case ^AST_Function_Def: // Nothing to do with functions yet. Calls are not supported
		case ^AST_Constant_Def:
			if d.has_errors do continue
			if d.name.has_errors do continue
			name := d.name.name
			#partial switch expr in d.value.derived_expr {
			case ^AST_Number_Lit:
				self.symbol_table[name] = expr.v
			case ^AST_Color_Lit:
				self.symbol_table[name] = expr.v
			case ^AST_Bool_Lit:
				self.symbol_table[name] = expr.v
			case:
				sema_error(self, d.span,
					"Complex constant expressions are not supported for the demo. Use runtime expressions instead.",
				)
			}
		}
	}
}

sema_check_program :: proc(self: ^Compiler) {
	for def in self.ast.defs {
		#partial switch d in def.derived_def {
		case ^AST_Function_Def:
			if def_has_annotation(def, "state") { // Assuming you kept the helper
				sema_check_function(self, d)
			}
		}
	}
}

sema_check_function :: proc(self: ^Compiler, func: ^AST_Function_Def) {
	ctx := Sema_Context{
		locals = make(map[string]int, 16, self.allocator),
		local_types = make(map[string]Type_Class, 16, self.allocator),
		local_count = 0,
		inside_state_function = def_has_annotation(func, "state"),
	}
	defer delete(ctx.locals)
	defer delete(ctx.local_types)

	// Register parameters (like 'cell') so they don't trigger "undefined variable"
	for param in func.params {
		ctx.locals[param.name] = ctx.local_count
		ctx.local_count += 1
	}

	for stmt in func.body {
		sema_check_stmt(self, &ctx, stmt)
	}
}

sema_check_stmt :: proc(self: ^Compiler, ctx: ^Sema_Context, stmt: ^AST_Stmt) {
	if stmt == nil do return
	if stmt.has_errors do return

	switch s in stmt.derived_stmt {
	case ^AST_Assign_Stmt:
		sema_check_expr(self, ctx, s.value)
		rhs_type := sema_resolve_expr_type(self, ctx, s.value)

		lhs_type: Type_Class
		switch target in s.target {
		case ^AST_Identifier:
			if target.name not_in ctx.locals { // New Variable Declaration
				ctx.locals[target.name] = ctx.local_count
				ctx.local_types[target.name] = rhs_type
				ctx.local_count += 1
				lhs_type = rhs_type
			} else { // Re-assignment of an existing variable
				lhs_type = ctx.local_types[target.name]
			}
		case ^AST_Prop_Access_Expr:
			sema_check_expr(self, ctx, target.entity)
			lhs_type = sema_resolve_expr_type(self, ctx, target)
		}

		if lhs_type != rhs_type && lhs_type != .Unknown && rhs_type != .Unknown {
			sema_error(self, s.span, "Type mismatch on assignment: Cannot assign %v to %v.", rhs_type, lhs_type)
		} else if lhs_type == .Unknown && rhs_type != .Unknown {
			// Upgrade the inferred type of a local variable if we just figured it out
			if ident, is_ident := s.target.(^AST_Identifier); is_ident {
				ctx.local_types[ident.name] = rhs_type
			}
		}
	case ^AST_If_Stmt:
		sema_check_expr(self, ctx, s.condition)
		for body_stmt in s.body_if do sema_check_stmt(self, ctx, body_stmt)
		for body_stmt in s.body_else do sema_check_stmt(self, ctx, body_stmt)

	case ^AST_Expr_Stmt:
		sema_check_expr(self, ctx, s.expr)

	case ^AST_Return_Stmt: // Nothing to validate here for MVP
	}
}

sema_check_expr :: proc(self: ^Compiler, ctx: ^Sema_Context, expr: ^AST_Expr) {
	if expr == nil do return
	if expr.has_errors do return

	switch e in expr.derived_expr {
	case ^AST_Identifier:
		if e.name in ctx.locals do return
		if e.name in self.symbol_table do return

		sema_error(self, e.span, "Undefined variable or constant: '%s'", e.name)
	case ^AST_Call_Builtin_Expr:
		switch e.name {
		case "$Spawn":
			if len(e.args) != 2 {
				sema_error(self, e.span, "$Spawn expects exactly 2 arguments (angle, state), got %d.", len(e.args))
			} else {
				sema_check_expr(self, ctx, e.args[0])
				sema_check_expr(self, ctx, e.args[1])

				arg0_type := sema_resolve_expr_type(self, ctx, e.args[0])
				if arg0_type != .Number && arg0_type != .Unknown {
					sema_error(self, e.args[0].span, "Type mismatch: First argument to $Spawn must resolve to a Number, got %v.", arg0_type)
				}

				arg1_type := sema_resolve_expr_type(self, ctx, e.args[1])
				if arg1_type != .State && arg1_type != .Unknown {
					sema_error(self, e.args[1].span, "Type mismatch: Second argument to $Spawn must resolve to a State, got %v.", arg1_type)
				}

				if state_lit, is_lit := e.args[1].derived_expr.(^AST_State_Lit); is_lit {
					if state_lit.v[1:] not_in self.state_table {
						sema_error(self, state_lit.span, "Undefined state label: '%s'", state_lit.v)
					}
				}
			}
		case "$Rand":
			if len(e.args) != 0 {
				sema_error(self, e.span, "$Rand expects 0 arguments, got %d.", len(e.args))
			}
		case:
			sema_error(self, e.span, "Unknown builtin function: '%s'", e.name)
		}
	case ^AST_Binary_Expr:
		sema_check_expr(self, ctx, e.left)
		sema_check_expr(self, ctx, e.right)
	case ^AST_Unary_Expr:
		sema_check_expr(self, ctx, e.operand)
	case ^AST_Ternary_Expr:
		sema_check_expr(self, ctx, e.condition)
		sema_check_expr(self, ctx, e.expr_if)
		sema_check_expr(self, ctx, e.expr_else)
	case ^AST_Prop_Access_Expr:
		sema_check_expr(self, ctx, e.entity)
		// e.property is an identifier, but it's a field name (e.g., 'growth_rate'),
		// so we don't validate it against local variables.
	case ^AST_Number_Lit, ^AST_Color_Lit, ^AST_Bool_Lit, ^AST_State_Lit:
		// Literals are inherently valid
	}
}

sema_error :: proc(self: ^Compiler, span: SrcSpan, msg: string, args: ..any) {
	compiler_error(self.diagnostics, .sema, span, msg, ..args)
}

sema_resolve_expr_type :: proc(self: ^Compiler, ctx: ^Sema_Context, expr: ^AST_Expr) -> Type_Class {
	if expr == nil || expr.has_errors do return .Poison

	switch e in expr.derived_expr {
	case ^AST_Number_Lit: return .Number
	case ^AST_Color_Lit:  return .Color
	case ^AST_Bool_Lit:   return .Bool
	case ^AST_State_Lit:  return .State

	case ^AST_Identifier:
		// Unify against globals
		if val, is_global := self.symbol_table[e.name]; is_global {
			switch _ in val {
			case f32: return .Number
			case bool: return .Bool
			case vm.Color: return .Color
			case vm.Label: return .State
			case vm.Param: return .Unknown
			}
		}
		// Unify against locals
		if typ, ok := ctx.local_types[e.name]; ok {
			return typ
		}
		return .Unknown
	case ^AST_Binary_Expr:
		left_type := sema_resolve_expr_type(self, ctx, e.left)
		right_type := sema_resolve_expr_type(self, ctx, e.right)

		if left_type == .Poison || right_type == .Poison do return .Poison

		// Unify the branches
		if left_type != right_type && left_type != .Unknown && right_type != .Unknown {
			sema_error(self, e.span, "Type mismatch: Cannot unify %v and %v in binary expression.", left_type, right_type)
			return .Poison
		}

		// Logical and relational operators always yield booleans
		#partial switch e.op {
		case .Eq, .Neq, .Lt, .Leq, .Gt, .Geq, .And, .Or: return .Bool
		case:
			// Arithmetic yields the unified type
			return left_type != .Unknown ? left_type : right_type
		}
	case ^AST_Unary_Expr:
		return sema_resolve_expr_type(self, ctx, e.operand)
	case ^AST_Call_Builtin_Expr:
		switch e.name {
		case "Rand": return .Number
		case "Spawn": return .Unknown // Doesn't return a value
		case: return .Unknown
		}
	case ^AST_Prop_Access_Expr:
		target := e.entity.derived_expr.(^AST_Identifier)
		if target.name != "cell" do return .Unknown

		switch e.property.name {
		case "thickness", "length", "growth_rate", "stiffness", "density": return .Number
		case "color": return .Color
		case "state": return .State
		case: return .Unknown
		}
	case ^AST_Ternary_Expr:
		cond_type := sema_resolve_expr_type(self, ctx, e.condition)
		if cond_type != .Bool && cond_type != .Unknown {
			sema_error(self, e.condition.span, "Type mismatch: Ternary condition must be a Bool, got %v.", cond_type)
			return .Poison
		}

		true_type := sema_resolve_expr_type(self, ctx, e.expr_if)
		false_type := sema_resolve_expr_type(self, ctx, e.expr_else)

		if true_type == .Poison || false_type == .Poison do return .Poison

		if true_type != false_type && true_type != .Unknown && false_type != .Unknown {
			sema_error(self, e.span, "Type mismatch: Ternary branches must unify. Got %v and %v.", true_type, false_type)
			return .Poison
		}
		return true_type != .Unknown ? true_type : false_type
	}

	return .Unknown
}
