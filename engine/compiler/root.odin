package compiler

import "core:mem"
import "core:fmt"
import "base:runtime"
import "../vm"

DynBlock :: [dynamic]vm.Instruction

Compiler :: struct{
	source: string,
	tokens: []Token,
	parser: Parser, // Currently holds Dynamic_Arena where ast is alloced
	ast: ^AST_Module,
	state_uid:    uint,
	state_table:  map[string]vm.Label,
	symbol_table: map[string]vm.Value,
	blocks:       [dynamic]DynBlock,
	entrypoint: Maybe(string),
	terminal: Maybe(string),
	diagnostics: ^DiagnosticList,
	allocator: mem.Allocator
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
make_diagnostic_list :: proc(allocator := context.allocator) -> ^DiagnosticList {
	self := new(DiagnosticList, allocator)
	self.items = make([dynamic]Diagnostic, allocator)
	self.allocator = allocator
	return self
}
delete_diagnostic_list :: proc(self: ^DiagnosticList) {
	delete(self.items)
	free(self)
}

compile_program :: proc(self: ^Compiler, source: string, allocator := context.allocator) -> (vm.Program, bool) {
	self.source = source
	self.allocator = allocator
	self.tokens = scanner_collect(self.source, allocator)
	self.diagnostics = make_diagnostic_list(allocator)
	self.state_table = make(map[string]vm.Label, allocator)
	self.blocks = make([dynamic]DynBlock, allocator)

	_ = alloc_block(self) // 0 is reserved for main
	_ = alloc_block(self) // 1 is reserved for terminal
	assert(self.state_uid == 2, "Blocks for main and terminal were not reserved")

	parser_init(&self.parser, self.tokens, self.diagnostics, allocator)
	self.ast = parse_program(&self.parser)

	fmt.printfln("AST:\n\n%v", dump_ast_to_string_fancy(self.ast))

	sema_resolve_globals(self)
	sema_check_program(self)
	if len(self.diagnostics.items) != 0 { return {}, false }
	program := lower_ast(self, self.ast) // TODO: Implement me

	return program, true
}

compiler_error :: proc(diagnostics: ^DiagnosticList, subsystem: CompilerSubsystem, span: SrcSpan, msg: string, args: ..any) {
	diagnostic := Diagnostic{
		subsystem = subsystem,
		span = span,
		message = fmt.aprintf(msg, ..args, allocator=diagnostics.allocator)
	}
	append(&diagnostics.items, diagnostic)
}
