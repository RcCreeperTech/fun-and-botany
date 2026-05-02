package compiler_web_worker

import "core:strings"
import "core:encoding/json"
import "../compiler"
import "base:runtime"
import "core:log"

import "../vm"

Worker :: struct {
	highligh_tokens:    []compiler.Token,
	source_buf:         [dynamic]u8,
	ffi_program_buffer: []u8,
	ffi_diagnostics:    [dynamic]FFI_Diagnostic,
	semantic_tokens:    [dynamic]Semantic_Token,
	compiler:           ^compiler.Compiler,
	ctx:                runtime.Context,
}

g_worker: Worker

main :: proc() {
	when ODIN_DEBUG {
		context.logger = log.create_console_logger(opt = {
			.Level,
			.Terminal_Color,
			.Short_File_Path,
			.Line,
			.Procedure,
		})
	}

	self := &g_worker
	self.compiler = compiler.make_compiler()
	self.ctx = context

	self.ffi_diagnostics = make([dynamic]FFI_Diagnostic)
	self.semantic_tokens = make([dynamic]Semantic_Token)

	vm.init_json_encoders()
}

re_analyze :: proc(self: ^Worker) {
	context = self.ctx

	delete(self.ffi_program_buffer) // Re-analysis invalidates the program output
	self.ffi_program_buffer = nil

	compiler.reset_compiler(self.compiler)
	source := cast(string)self.source_buf[:]
	compiler.analyze_program(self.compiler, source) // Re-creates the AST and generates new diagnostics
	// Need to tokenize comments for lsp
	delete(self.highligh_tokens)
	self.highligh_tokens = compiler.scanner_collect(source, skip_comments=false)

	clear(&self.semantic_tokens)
	generate_semantic_tokens(self)
	log.debug("Generated some tokens", self.semantic_tokens[:])
	for d in self.compiler.diagnostics.items {
		log.debugf("%v: %v", d.subsystem, d.message)
	}
}

// Edit the current text buffer and trigger a recompile.
// @param edit_start Start of the edit slice this indicates where to insert the new text.
// @param edit_len Length of the edit slice. Len == 0 means no deletion Just insert at the offset.
@(export)
apply_edit :: proc(
	edit_start, edit_len: u32,
	text_ptr: [^]byte, text_len: u32 // The new string to be inserted
) {
	self := &g_worker
	context = self.ctx
	buf := &self.source_buf

	if int(edit_start) > len(buf) do return
	// Clamp the edit length to avoid overflowing the buffer
	edit_len := edit_len
	edit_len = min(edit_len, u32(len(buf)))

	// If we are replacing or deleting, remove the old characters first.
	if edit_len > 0 {
		tail_start := edit_start + edit_len
		tail_len := u32(len(buf)) - tail_start

		if tail_len > 0 {
			for i in 0 ..< int(tail_len) {
				buf[int(edit_start) + i] = buf[int(tail_start) + i]
			}
		}

		resize(buf, len(buf) - int(edit_len))
	}

	// If there is new text, make room and copy it in.
	if text_len > 0 {
		old_len := u32(len(buf))

		resize(buf, int(old_len + text_len))

		tail_len := old_len - edit_start

		if tail_len > 0 {
			for i := int(tail_len) - 1; i >= 0; i -= 1 {
				buf[int(edit_start + text_len) + i] = buf[int(edit_start) + i]
			}
		}

		for i in 0 ..< int(text_len) {
			buf[int(edit_start) + i] = text_ptr[i]
		}
	}

    re_analyze(&g_worker)
}

@(export)
get_semantic_tokens :: proc() -> rawptr {
	self := &g_worker
	context = self.ctx

	out := ffi_out_var(runtime.Raw_Slice)
	out^ = transmute(runtime.Raw_Slice)self.semantic_tokens[:]
	return out
}

@(export)
can_compile_program :: proc() -> bool {
	self := &g_worker
	context = self.ctx

	if len(self.compiler.diagnostics.items) > 0 do return false
	if self.compiler.ast == nil do return false
	// TODO: Walk the whole ast and check for error nodes.
	return true
}

@(export)
get_compiled_bytecode :: proc() -> rawptr {
	self := &g_worker
	context = self.ctx

	if self.ffi_program_buffer == nil {
		program, ok := compiler.emit_bytecode(self.compiler)
		assert(ok, "The user should have checked that the ast was valid")

		sb := strings.builder_make()
		defer strings.builder_destroy(&sb)
		vm.dump_program_sb(&sb, program)
		log.debug("Worker got", strings.to_string(sb))

		err: json.Marshal_Error
		self.ffi_program_buffer, err = json.marshal(program, {
			use_enum_names = true,
		})
		if err != nil {
			log.error("Unable to marshal program", err)
		}
	}



	out := ffi_out_var(runtime.Raw_Slice)
	out^ = transmute(runtime.Raw_Slice)self.ffi_program_buffer
	return out
}

FFI_Diagnostic :: struct #packed {
    offset:  u32,
    length:  u32,
    msg_ptr: u32,
    msg_len: u32,
}

@(export)
get_diagnostics :: proc() -> rawptr {
	self := &g_worker
	context = self.ctx

    clear(&self.ffi_diagnostics)
    for d in self.compiler.diagnostics.items {
    	if(d.span[0] == nil && d.span[1] == nil) {
     		log.panicf("Got an invalid span for '%v'", d.message)
     	}
        start, end := d.span[0], d.span[1]

        base_addr := uintptr(raw_data(self.source_buf))
        start_addr := uintptr(raw_data(start.raw))
        end_addr := uintptr(raw_data(end.raw)) + uintptr(len(end.raw))

        offset: u32
        if start_addr >= base_addr {
            offset = u32(start_addr - base_addr)
        } else {
            offset = u32(len(self.source_buf))
        }

        length: u32
        if end_addr >= start_addr {
            length = u32(end_addr - start_addr)
        }

        msg := transmute(runtime.Raw_String)d.message

        append(&self.ffi_diagnostics, FFI_Diagnostic{
            offset  = offset,
            length  = length,
            msg_ptr = u32(uintptr(msg.data)),
            msg_len = u32(msg.len),
        })
    }

    out := ffi_out_var(runtime.Raw_Slice)
	out^ = transmute(runtime.Raw_Slice)self.ffi_diagnostics[:]
	return out
}

Semantic_TokenKind :: enum u8 {
	None = 0,
	Variable,
	Function,
	Constant,
	Property,
	Builtin,
	Keyword,
	Number,
	String,
	Color,
	Boolean,
	Operator,
	Punctuation,
	Comment,
}

Semantic_TokenInfo :: bit_field u32 {
	kind: Semantic_TokenKind | 8,
	_pad: int                | 24,
}

Semantic_Token :: struct #packed {
	offset: u32,
	length: u32,
	info:   Semantic_TokenInfo,
}

generate_semantic_tokens :: proc(self: ^Worker) {
	for t in self.highligh_tokens {
		if t.kind == .End_Of_Statement || t.kind == .End_Of_Stream || t.kind == .Invalid || t.kind == .Error {
			continue
		}

		kind: Semantic_TokenKind = .None
		#partial switch t.kind {
		case .Comment: kind = .Comment
		case .Keyword_End, .Keyword_Def, .Keyword_If, .Keyword_Else, .Keyword_Return, .Keyword_And, .Keyword_Or:
			kind = .Keyword
		case .Literal_Color: kind = .Color
		case .Literal_Number: kind = .Number
		case .Literal_State_Label: kind = .String
		case .Literal_Boolean: kind = .Boolean
		case .Identifier: kind = .Variable
		case .Builtin_Identifier: kind = .Builtin
		case .Plus, .Minus, .Asterisk, .Forward_Slash, .Less, .Less_Equals, .Greater, .Greater_Equals, .Equals, .Equals_Equals, .Exclamation, .Exclamation_Equals:
			kind = .Operator
		case .Colon, .Period, .Comma, .Open_Paren, .Close_Paren, .At:
			kind = .Punctuation
		}

		base_ptr := uintptr(raw_data(self.source_buf[:]))
		tok_ptr  := uintptr(raw_data(t.raw))
		offset   := u32(tok_ptr - base_ptr)

		append(&self.semantic_tokens, Semantic_Token{
			offset = offset,
			length = u32(len(t.raw)),
			info   = { kind = kind },
		})
	}

	for def in self.compiler.ast.defs {
		walk_def(self, def)
	}

	update_token :: proc(self: ^Worker, span: compiler.SrcSpan, kind: Semantic_TokenKind) {
		if span[0] == nil do return

		base_ptr := uintptr(raw_data(self.source_buf[:]))
		tok_ptr  := uintptr(raw_data(span[0].raw))
		offset   := u32(tok_ptr - base_ptr)

		// Binary search to find the token quickly
		low := 0
		high := len(self.semantic_tokens) - 1
		for low <= high {
			mid := low + (high - low) / 2
			if self.semantic_tokens[mid].offset == offset {
				self.semantic_tokens[mid].info.kind = kind
				return
			} else if self.semantic_tokens[mid].offset < offset {
				low = mid + 1
			} else {
				high = mid - 1
			}
		}
	}

	walk_expr :: proc(self: ^Worker, expr: ^compiler.AST_Expr) {
		if expr == nil do return

		#partial switch e in expr.derived_expr {
		case ^compiler.AST_Ternary_Expr:
			walk_expr(self, e.condition); walk_expr(self, e.expr_if); walk_expr(self, e.expr_else)
		case ^compiler.AST_Binary_Expr:
			walk_expr(self, e.left); walk_expr(self, e.right)
		case ^compiler.AST_Unary_Expr:
			walk_expr(self, e.operand)
		case ^compiler.AST_Prop_Access_Expr:
			walk_expr(self, e.entity)
			update_token(self, e.property.span, .Property)
		case ^compiler.AST_Call_Builtin_Expr:
			update_token(self, e.span, .Builtin)
			for arg in e.args do walk_expr(self, arg)
		}
	}

	walk_stmt :: proc(self: ^Worker, stmt: ^compiler.AST_Stmt) {
		if stmt == nil do return

		#partial switch s in stmt.derived_stmt {
		case ^compiler.AST_Assign_Stmt:
			#partial switch t in s.target {
			case ^compiler.AST_Prop_Access_Expr:
				walk_expr(self, t.entity)
				update_token(self, t.property.span, .Property)
			}
			walk_expr(self, s.value)
		case ^compiler.AST_If_Stmt:
			walk_expr(self, s.condition)
			for b in s.body_if do walk_stmt(self, b)
			for b in s.body_else do walk_stmt(self, b)
		case ^compiler.AST_Expr_Stmt:
			walk_expr(self, s.expr)
		}
	}

	walk_def :: proc(self: ^Worker, def: ^compiler.AST_Top_Level_Def) {
		if def == nil do return

		if def.annotation != nil {
			for item in def.annotation.items do update_token(self, item.span, .Keyword)
		}

		switch d in def.derived_def {
		case ^compiler.AST_Function_Def:
			update_token(self, d.name.span, .Function)
			for s in d.body do walk_stmt(self, s)
		case ^compiler.AST_Constant_Def:
			update_token(self, d.name.span, .Constant)
			walk_expr(self, d.value)
		}
	}
}
