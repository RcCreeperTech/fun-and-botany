package compiler

import "core:mem"
import "core:fmt"
import "base:runtime"
import "../vm"

DynBlock :: [dynamic]vm.Instruction

Compiler :: struct{
	tokens:       []Token,
	ast:          ^AST_Module,
	state_table:  map[string]vm.Label,
	symbol_table: map[string]vm.Value,
	blocks:       [dynamic]DynBlock,
	entrypoint:   Maybe(string),
	terminal:     Maybe(string),
	diagnostics:  ^DiagnosticList,
	allocator:    mem.Allocator,
	arenas: struct {
		ast:         Dynamic_Arena,
		blocks:      Dynamic_Arena,
		diagnostics: Dynamic_Arena,
	}
}

CompilerSubsystem :: enum { parser, sema }
Diagnostic :: struct {
	subsystem: CompilerSubsystem,
	span: SrcSpan,
	message: string,
}
DiagnosticList :: struct {
	items: [dynamic]Diagnostic,
	allocator: mem.Allocator,
}
make_diagnostic_list :: proc(arena: ^Dynamic_Arena) -> ^DiagnosticList {
	arena_allocator := dynamic_arena_allocator(arena)
	self := new(DiagnosticList, arena_allocator)
	self.items = make([dynamic]Diagnostic, arena_allocator)
	self.allocator = arena_allocator
	return self
}

make_compiler :: proc(allocator := context.allocator, loc := #caller_location) -> ^Compiler {
	self := new(Compiler, allocator, loc)
	self.allocator = allocator
	dynamic_arena_init(&self.arenas.ast, self.allocator, self.allocator)
	dynamic_arena_init(&self.arenas.blocks, self.allocator, self.allocator)
	dynamic_arena_init(&self.arenas.diagnostics, self.allocator, self.allocator)

	self.diagnostics  = make_diagnostic_list(&self.arenas.diagnostics)
	self.state_table  = make(map[string]vm.Label, self.allocator)
	self.symbol_table = make(map[string]vm.Value, self.allocator)
	self.blocks       = make([dynamic]DynBlock, self.allocator)

	return self
}
delete_compiler :: proc(self: ^Compiler) {
	dynamic_arena_destroy(&self.arenas.ast)
	dynamic_arena_destroy(&self.arenas.blocks)
	dynamic_arena_destroy(&self.arenas.diagnostics)
	delete(self.state_table)
	delete(self.symbol_table)
	delete(self.tokens)
	delete(self.blocks)
	free(self)
}
reset_compiler :: proc(self: ^Compiler) {
	delete(self.tokens)
	dynamic_arena_reset(&self.arenas.ast)
	dynamic_arena_reset(&self.arenas.blocks)
	dynamic_arena_reset(&self.arenas.diagnostics)

	clear(&self.state_table)
	clear(&self.symbol_table)
	clear(&self.blocks)

	self.entrypoint = nil
	self.terminal = nil
}

compile_program :: proc(self: ^Compiler, source: string) -> (vm.Program, bool) {
	self.tokens = scanner_collect(source, allocator=self.allocator)
	self.ast = parser_collect(self.tokens, self.diagnostics, &self.arenas.ast)
	sema_resolve_globals(self)
	sema_check_program(self)
	if len(self.diagnostics.items) != 0 { return {}, false }
	program := lower_ast(self, self.ast)

	return program, true
}

analyze_program :: proc(self: ^Compiler, source: string) {
	self.tokens = scanner_collect(source, allocator=self.allocator)
	self.diagnostics = make_diagnostic_list(&self.arenas.diagnostics)

	self.ast = parser_collect(self.tokens, self.diagnostics, &self.arenas.ast)
	sema_resolve_globals(self)
	sema_check_program(self)
}

compiler_error :: proc(diagnostics: ^DiagnosticList, subsystem: CompilerSubsystem, span: SrcSpan, msg: string, args: ..any) {
	diagnostic := Diagnostic{
		subsystem = subsystem,
		span = span,
		message = fmt.aprintf(msg, ..args, allocator=diagnostics.allocator)
	}
	append(&diagnostics.items, diagnostic)
}
