package compiler

import "../vm"

lower_ast :: proc(self: ^Compiler, ast: ^AST_Module) -> vm.Program {
	for def in ast.defs {
		func, is_func := def.derived_def.(^AST_Function_Def)
		if !is_func do continue
		// If the function is not in the state table, it is not a state block
		// For now it does nothing since we cannot call functions
		label, is_state := self.state_table[func.name.name]
		if !is_state do continue

		lower_function_def(self, func, label)
	}

	// Finalize the blocks into the format the VM expects
	program_allocator := dynamic_arena_allocator(&self.arenas.program)
	// I dont think this is the right place... Gotta write some usage code and
	// see where it shakes out. Also should this be its own subsystem? Its
	// unclear who owns the blocks because sema also generates them.
	final_blocks := make([]vm.Block, len(self.blocks), program_allocator)
	for block, i in self.blocks {
		final_blocks[i] = block[:]
	}

	return vm.Program{ blocks = final_blocks }
}

lower_function_def :: proc(
	self: ^Compiler,
	func: ^AST_Function_Def,
	active_block: vm.Label,
) {
	locals := make(map[string]int, 16, self.allocator)
	defer delete(locals)
	local_count := 0

	for param in func.params {
		// Cell is a special variable, it does not behave as a stack vaar
		if param.name == "cell" && def_has_annotation(func, "state") do continue
		locals[param.name] = local_count
		local_count += 1
	}

	out_block := active_block

	for stmt in func.body {
		out_block = lower_stmt(self, stmt, &locals, &local_count, out_block)
	}

	block_append(self, out_block, { op = .EarlyReturn })
}

lower_stmt :: proc(
	self: ^Compiler,
	stmt: ^AST_Stmt,
	locals: ^map[string]int,
	local_count: ^int,
	active_block: vm.Label,
) -> vm.Label {
	if stmt == nil do return active_block
	assert(!stmt.has_errors, "Cannot lower statement that has errors.")

	out_block := active_block

	switch s in stmt.derived_stmt {
	case ^AST_Assign_Stmt:
		// Post-order: Evaluate the RHS value first, leaving it on top of the stack.
		out_block = lower_expr(self, s.value, locals, local_count, out_block)

		switch target in s.target {
		case ^AST_Identifier:
			// Resolve or create the local variable index
			idx, found := locals[target.name]
			if !found {
				idx = local_count^
				locals[target.name] = idx
				local_count^ += 1
			}
			block_append(self, out_block, { op = .SetLocal, imm = {f32(idx), nil} })
		case ^AST_Prop_Access_Expr:
			ent := target.entity.derived_expr.(^AST_Identifier)
			assert(ent.name == "cell", "Prop access only legal for cell currently")

			param := map_string_to_vm_param(target.property.name)
			block_append(self, out_block, { op = .SetParam, imm = {param, nil} })
		}
	case ^AST_Return_Stmt:
		block_append(self, out_block, { op = .EarlyReturn })
	case ^AST_Expr_Stmt:
		out_block = lower_expr(self, s.expr, locals, local_count, out_block)
	case ^AST_If_Stmt:
		if_label := alloc_block(self)
		cont_label := alloc_block(self)

		else_label := cont_label
		if len(s.body_else) > 0 {
			else_label = alloc_block(self)
		}

		precond := vm.Precondition.None
		if bin, is_bin := s.condition.derived_expr.(^AST_Binary_Expr); is_bin {
			#partial switch bin.op {
			case .Eq:  precond = .Eq
			case .Neq: precond = .Neq
			case .Lt:  precond = .Lt
			case .Leq: precond = .Leq
			case .Gt:  precond = .Gt
			case .Geq: precond = .Geq
			}
			if precond != .None {
				out_block = lower_expr(self, bin.left, locals, local_count, out_block)
				out_block = lower_expr(self, bin.right, locals, local_count, out_block)
			}
		}

		if precond == .None {
			out_block = lower_expr(self, s.condition, locals, local_count, out_block)
			block_append(self, out_block, { op = .Push, imm = {true, nil} })
			precond = .Eq
		}

		block_append(self, out_block, { precondition = precond, op = .Jump, imm = {if_label, else_label} })

		curr_if := if_label
		for b_stmt in s.body_if {
			curr_if = lower_stmt(self, b_stmt, locals, local_count, curr_if)
		}
		block_append(self, curr_if, { op = .Jump, imm = {cont_label, cont_label} })

		if len(s.body_else) > 0 {
			curr_else := else_label
			for b_stmt in s.body_else {
				curr_else = lower_stmt(self, b_stmt, locals, local_count, curr_else)
			}
			block_append(self, curr_else, { op = .Jump, imm = {cont_label, cont_label} })
		}

		out_block = cont_label
	}

	return out_block
}

lower_expr :: proc(
	self: ^Compiler,
	expr: ^AST_Expr,
	locals: ^map[string]int,
	local_count: ^int,
	active_block: vm.Label
) -> vm.Label {
	if expr == nil do return active_block
	assert(!expr.has_errors, "Cannot lower expression that has errors.")

	out_block := active_block

	switch e in expr.derived_expr {
	case ^AST_Number_Lit: block_append(self, out_block, { op = .Push, imm = {e.v, nil} })
	case ^AST_Color_Lit:  block_append(self, out_block, { op = .Push, imm = {e.v, nil} })
	case ^AST_Bool_Lit:   block_append(self, out_block, { op = .Push, imm = {e.v, nil} })
	case ^AST_State_Lit:
		label, ok := self.state_table[e.v[1:]]
		assert(ok, "State labels should be fully resolved by now")
		block_append(self, out_block, { op = .Push, imm = {label, nil} })
	case ^AST_Identifier:
		if val, is_global := self.symbol_table[e.name]; is_global {
			block_append(self, out_block, { op = .Push, imm = {val, nil} })
		} else {
			idx := locals[e.name]
			block_append(self, out_block, { op = .GetLocal, imm = {f32(idx), nil} })
		}
	case ^AST_Binary_Expr:
		// Post-order traversal: push operands to the stack first
		out_block = lower_expr(self, e.left, locals, local_count, out_block)
		out_block = lower_expr(self, e.right, locals, local_count, out_block)

		op: vm.Op
		#partial switch e.op {
		case .Add: op = .Add
		case .Sub: op = .Subtract
		case .Mul: op = .Multiply
		case .Div: op = .Divide
		case: unimplemented(":^)")
		}
		block_append(self, out_block, { op = op })
	case ^AST_Unary_Expr:
		out_block = lower_expr(self, e.operand, locals, local_count, out_block)
		block_append(self, out_block, { op = .Negate })
	case ^AST_Call_Builtin_Expr:
		switch e.name {
		case "$Rand":
			block_append(self, out_block, { op = .Rand })
		case "$Spawn":
			out_block = lower_expr(self, e.args[0], locals, local_count, out_block)
			out_block = lower_expr(self, e.args[1], locals, local_count, out_block)
			block_append(self, out_block, { op = .Spawn })
		case: unreachable()
		}
	case ^AST_Prop_Access_Expr:
		target := e.entity.derived_expr.(^AST_Identifier)
		assert(target.name == "cell", "Prop access only legal for cell currently")
		// When a property access appears in an expression context, it's a READ.
		// e.g. `if cell.length > 5`. We map the string to the enum and emit .GetParam.
		param := map_string_to_vm_param(e.property.name)
		block_append(self, out_block, { op = .GetParam, imm = {param, nil} })
	case ^AST_Ternary_Expr:
		true_label := alloc_block(self)
		false_label := alloc_block(self)
		cont_label := alloc_block(self)

		precond := vm.Precondition.None
		if bin, is_bin := e.condition.derived_expr.(^AST_Binary_Expr); is_bin {
			#partial switch bin.op {
			case .Eq:  precond = .Eq
			case .Neq: precond = .Neq
			case .Lt:  precond = .Lt
			case .Leq: precond = .Leq
			case .Gt:  precond = .Gt
			case .Geq: precond = .Geq
			}
			if precond != .None {
				out_block = lower_expr(self, bin.left, locals, local_count, out_block)
				out_block = lower_expr(self, bin.right, locals, local_count, out_block)
			}
		}

		if precond == .None {
			out_block = lower_expr(self, e.condition, locals, local_count, out_block)
			block_append(self, out_block, { op = .Push, imm = {true, nil} })
			precond = .Eq
		}

		block_append(self, out_block, { precondition = precond, op = .Jump, imm = {true_label, false_label} })

		curr_true := lower_expr(self, e.expr_if, locals, local_count, true_label)
		block_append(self, curr_true, { op = .Jump, imm = {cont_label, cont_label} })

		curr_false := lower_expr(self, e.expr_else, locals, local_count, false_label)
		block_append(self, curr_false, { op = .Jump, imm = {cont_label, cont_label} })

		out_block = cont_label
	}

	return out_block
}


// Helper to map property names to VM parameter enums
map_string_to_vm_param :: proc(name: string) -> vm.Param {
	switch name {
	case "state":       return .State
	case "thickness":   return .Thickness
	case "length":      return .Length
	case "color":       return .Color
	case "growth_rate": return .Growth_Rate
	case "stiffness":   return .Stiffness
	case "density":     return .Density
	}
	return .State // Fallback, SEMA should prevent this
}

alloc_block :: proc(self: ^Compiler) -> vm.Label {
	block_allocator := dynamic_arena_allocator(&self.arenas.blocks)
	id := vm.Label(len(self.blocks))
	block := make(DynBlock, block_allocator)
	append(&self.blocks, block)

	return id
}

block_append :: proc(self: ^Compiler, id: vm.Label, instruction: vm.Instruction) {
	append(&self.blocks[id], instruction)
}
