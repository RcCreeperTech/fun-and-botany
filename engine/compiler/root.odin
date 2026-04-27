package compiler

import "core:log"
import "core:mem"
import "core:fmt"
import "base:runtime"
import "../vm"

Compiler :: struct{
	source: string,
	tokens: []Token,
	parser: Parser, // Currently holds Dynamic_Arena where ast is alloced
	ast: ^AST_Module,
	state_uid:    uint,
	state_table:  map[string]vm.Label,
	symbol_table: map[string]vm.Value,
	entrypoint: Maybe(string),
	terminal: Maybe(string),
	diagnostics: [dynamic]Diagnostic,
	allocator: mem.Allocator
}

Diagnostic :: struct {
	subsystem: enum { parser, sema },
	span: SrcSpan,
	message: string,
}

compile_program :: proc(self: ^Compiler, source: string, allocator := context.allocator) ->  vm.Program {
	self.source = source
	self.allocator = allocator
	self.tokens = scanner_collect(self.source, allocator)
	self.diagnostics = make([dynamic]Diagnostic, allocator)

	self.state_table = make(map[string]vm.Label, allocator)
	// 0 is reserved for main
	// 1 is reserved for terminal
	self.state_uid = 2

	parser_init(&self.parser, self.tokens, &self.diagnostics, allocator)
	self.ast = parse_program(&self.parser)

	// TODO: Global Resolution
	def_has_annotation :: proc(def: ^AST_Top_Level_Def, name: string) -> bool {
		for a in def.annotation.items { if a.name == name do return true }
		return false
	}
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
			case:
				uid = vm.Label(self.state_uid)
				self.state_uid += 1
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
	// TODO: SEMA
	// TODO: Lowering

	return {}
}

sema_error :: proc(self: ^Compiler, span: SrcSpan, msg: string, args: ..any) {
	diagnostic := Diagnostic{
		subsystem = .sema,
		span = span,
		message = fmt.aprintf(msg, ..args, allocator=self.allocator)
	}
	append(&self.diagnostics, diagnostic)
}
