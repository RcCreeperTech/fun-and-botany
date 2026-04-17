package web_testing

import "core:sort"
import "base:runtime"
import "core:slice"
import "core:log"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:reflect"
import "core:strconv"

Token :: struct {
	line, col: u32,
	raw:       string,
	kind:      Token_Kind,
}

Token_Keyword :: enum {
	Const,
	Push,
	Pop,
	Mul,
	Div,
	Add,
	Sub,
	Rand,
	Jump,
	Spawn,
	End,
	Get,
	Set,
}
Token_Identifier :: struct {}
Token_Parameter :: struct {}
Token_Equals :: struct {}
Token_Minus :: struct {}
Token_Colon :: struct {}
Token_Period :: struct {}
Token_Slash :: struct {}
Token_Comma :: struct {}
Token_End_Of_Statement :: struct {}
Token_Label :: struct {}
Token_IntLit :: i32
Token_FloatLit :: f32
Token_HexLit :: u32
Token_BoolLit :: bool

Token_Kind :: union {
	Token_Identifier,
	Token_Parameter,
	Token_Equals,
	Token_Period,
	Token_Minus,
	Token_Colon,
	Token_Slash,
	Token_Comma,
	Token_Label,
	Token_IntLit,
	Token_FloatLit,
	Token_HexLit,
	Token_BoolLit,
	Token_Keyword,
	Token_End_Of_Statement,
}

AssemblerError :: union #shared_nil {
	ProgramError,
	ParserError,
	ScannerError,
}

ProgramError :: enum {
	None = 0,
	Unknown_Parameter,
	No_Entrypoint_Found,
}

ParserError :: enum {
	None = 0,
	Undefined_Predicate,
	Unexpected_Token,
	Unexpected_Top_Level_Keyword,
	Unable_To_Resolve_Constant_To_Value,
	Unable_To_Resolve_Block_To_Value,
	Duplicate_Identifier,
}

Constant :: VM_Value
BlockBuilder :: [dynamic]VM_Instruction
// Could these be conbined?
BlockRef :: struct {
	block_path: []string,
	offset: int,
	ref: string,
	pred: bool,
}
Relocation :: struct {
	block_path: []string,
	offset: int,
	constant_name: string,
	pred: bool,
}
Assembler :: struct {
	using scanner: Scanner,
	arena: mem.Dynamic_Arena,
	allocator: mem.Allocator,
	blocks: map[string]VM_Block,
	path_builder: strings.Builder,
	current_scope: [dynamic]string,
	constants: map[string]Constant,
	relocations: [dynamic]Relocation,
	block_refs: [dynamic]BlockRef,
	block_name_table: map[string]VM_Label
}
asm_init :: proc(self: ^Assembler, allocator := context.allocator) {
	mem.dynamic_arena_init(&self.arena, allocator, allocator, alignment=runtime.MAP_CACHE_LINE_SIZE)
	self.allocator = mem.dynamic_arena_allocator(&self.arena)
	self.blocks = make(map[string]VM_Block, self.allocator)
	self.constants = make(map[string]Constant,  self.allocator)
	self.relocations = make([dynamic]Relocation,  self.allocator)
	self.block_refs = make([dynamic]BlockRef,  self.allocator)
	self.block_name_table = make(map[string]VM_Label, self.allocator)
	self.current_scope = make([dynamic]string, self.allocator)
	self.path_builder = strings.builder_make(self.allocator)
	return
}
asm_cleanup :: proc(self: ^Assembler) {
	mem.dynamic_arena_destroy(&self.arena)
}

asm_push_scope :: proc(self: ^Assembler, label: string) {
	append(&self.current_scope, label)
}

asm_pop_scope :: proc(self: ^Assembler) {
	pop(&self.current_scope);
}
asm_register_constant :: proc(self: ^Assembler, prefix: []string, label: string, value: Constant) -> ParserError {
	qualified_name := asm_get_path(self, prefix, label, ".")
	if qualified_name in self.constants do return .Duplicate_Identifier
	log.infof("Registered constant %v = %v", qualified_name, value)
	self.constants[qualified_name] = value
	return nil
}
asm_resolve_constant :: proc(self: ^Assembler, query_path: []string, constant_name: string) -> (constant: Constant, found: bool = false) {
	prefix := asm_get_path_tmp(self, query_path, "", ".")
	log.infof("Resolving constant %v.<%v>", prefix, constant_name)
	for i := len(query_path); i >= 0; i -= 1 {
		candidate := asm_get_path_tmp(self, query_path[:i], constant_name, ".")
		log.debugf("\tChecking candidate %v", candidate)
		if value, found := self.constants[candidate]; found {
			log.debugf("\tFound match! %v = %v", candidate, value)
			return value, true
		}
	}
	return
}
asm_register_block :: proc(self: ^Assembler, path: []string, block: VM_Block) -> ParserError {
	qualified_name := asm_get_path(self, path[:], "", ":")
	if qualified_name in self.blocks do return .Duplicate_Identifier
	log.infof("Registered block: %v[%v]", qualified_name, len(block))
	self.blocks[qualified_name] = block
	return nil
}
asm_resolve_block_ref :: proc(self: ^Assembler, ref: BlockRef) -> (label: VM_Label, found: bool = false) {
	prefix := asm_get_path_tmp(self, ref.block_path, "", ":")
	log.infof("Resolving label %v <%v>", prefix, ref.ref)
	for i := len(ref.block_path); i >= 0; i -= 1 {
		candidate := asm_get_path_tmp(self, ref.block_path[:i], ref.ref, ":")
		log.debugf("\tChecking candidate %v", candidate)
		if value, found := self.block_name_table[candidate]; found {
			log.debugf("\tFound match! %v", candidate)
			return value, true
		}
	}
	return
}

asm_get_path_tmp :: proc(self: ^Assembler, prefix: []string, item, seperator: string) -> string {
	strings.builder_reset(&self.path_builder)
	for p, i in prefix {
		strings.write_string(&self.path_builder, p)
		if item == "" && i == (len(prefix) - 1) {
			return strings.to_string(self.path_builder)
		}
		strings.write_string(&self.path_builder, seperator)
	}
	strings.write_string(&self.path_builder, item)
	return strings.to_string(self.path_builder)
}
asm_get_path :: proc(self: ^Assembler, prefix: []string, item, seperator: string) -> string {
	return strings.clone(asm_get_path_tmp(self, prefix, item, seperator), self.allocator)
}

// TODO: Error reporting needs to improve a lot. Currently the error value is
// just bubbled out to the caller of assemble but no context for the error is
// collected.
asm_assemble :: proc(
	self: ^Assembler,
	source: string,
) -> (
	program: VM_Program,
	err: AssemblerError,
) {
	self.scanner.head = source

	lookup_parameter_by_name :: proc(name: string) -> (param: VM_Param, err: ProgramError) {
		val, ok := reflect.enum_from_name(VM_Param, name[1:]);
		if !ok do return {}, .Unknown_Parameter
		return val, nil
	}

	_, parse_err := parse(self)
	if parse_err != nil {
		if parse_err == .Unexpected_Token {
			log.errorf("Error during parsing (%v:%v): Unexpected token", self.scanner.line, self.scanner.col)
		}
		return {}, parse_err
	}

	// TODO: Here is where the constant folding will happen. This can also
	// fail. so we need to track that.

	for entry in self.relocations {
		if value, found := asm_resolve_constant(self, entry.block_path, entry.constant_name); found {
			name := asm_get_path(self, entry.block_path, "", ":")
			block := &self.blocks[name]
			inst := &block[entry.offset]
			assert(inst.op == .Push, "Push should be the only instruction that can accept a constant.")
			slot := entry.pred ? 1 : 0;
			inst.imm[slot] = value
		} else {
			return program, ParserError.Unable_To_Resolve_Constant_To_Value
		}
	}

	valid_blocks := make([dynamic]string, self.allocator)
	for n, b in self.blocks {
		if len(b) > 0 && n != "Main" {
			append(&valid_blocks, n)
		}
	}
	slice.sort(valid_blocks[:])
	inject_at(&valid_blocks, 0, "Main")

	block_id: int = 0
	program.blocks = make([]VM_Block, len(valid_blocks), self.allocator)
	found_main := false
	log.infof("Linearizing %v Blocks...", len(valid_blocks))
	for name in valid_blocks {
		log.infof("Block `%v` resolved to %v", name, block_id)
		self.block_name_table[name] = VM_Label(block_id)

		program.blocks[block_id] = self.blocks[name]
		block_id += 1
		if name == "Main" {
			found_main = true
		}
	}

	if !found_main {
		return {}, ProgramError.No_Entrypoint_Found
	}

	// Here is where the block index is deciede and the jumps need to be backpatched
	for ref in self.block_refs {
		if value, found := asm_resolve_block_ref(self, ref); found {
			name := asm_get_path(self, ref.block_path, "", ":")
			block := &self.blocks[name]
			inst := &block[ref.offset]
			assert(inst.op == .Jump, "Jump should be the only instruction that can accept a label.")
			slot := ref.pred ? 1 : 0;
			inst.imm[slot] = value
		} else {
			return program, ParserError.Unable_To_Resolve_Block_To_Value
		}
	}


	return program, nil

	parse :: proc(self: ^Assembler) -> (t: Token, err: AssemblerError) {
		for {
			tok := scanner_next(self) or_break

			#partial switch k in tok.kind {
			case Token_Identifier:
				parse_block(self, tok.raw) or_return
			case Token_Keyword:
				#partial switch k {
				case .Const:
					parse_constant(self) or_return
				case:
					return t, .Unexpected_Top_Level_Keyword
				}
			case:
				fmt.panicf("ERROR: Unexpected Top Level token: %v", tok)
			}
		}
		return {}, nil

		parse_constant :: proc(self: ^Assembler) -> (err: AssemblerError) {
			ident := expect(self, Token_Identifier) or_return
			_ = expect(self, Token_Equals) or_return

			tok := scanner_next(self) or_return
			#partial switch k in tok.kind {
			case Token_IntLit:
				asm_register_constant(self, self.current_scope[:], ident.raw, k) or_return
			case Token_FloatLit:
				asm_register_constant(self, self.current_scope[:], ident.raw, k) or_return
			case Token_HexLit:
				c := rgba_u32_to_color(k)
				asm_register_constant(self, self.current_scope[:], ident.raw, c) or_return
			case:
				log.errorf("TODO: Got a %v when parsing constant %v", tok, ident.raw)
				return .Unexpected_Token
			}

			_ = expect(self, Token_End_Of_Statement) or_return

			return nil
		}
		parse_constant_literal :: proc(self: ^Assembler, front: string) -> (constant_name: string, err: AssemblerError) {
			next := scanner_peek(self) or_return
			if _, ok := next.kind.(Token_Period); ok {
				_ = expect(self, Token_Period) or_return
				ident := expect(self, Token_Identifier) or_return
				new_front := fmt.aprintf("%v.%v", front, ident.raw)
				return parse_constant_literal(self, new_front)
			}

			return front, nil
		}

		parse_block :: proc(self: ^Assembler, label: string) -> (
			err: AssemblerError,
		) {
			asm_push_scope(self, label)
			defer asm_pop_scope(self)

			block := make([dynamic]VM_Instruction, self.allocator)

			_ = expect(self, Token_Colon) or_return
			_ = expect(self, Token_End_Of_Statement) or_return

			loop: for {
				tok := scanner_next(self) or_return
				#partial switch k in tok.kind {
				case Token_Keyword:
					#partial switch k {
					case .End:
						_ = expect(self, Token_End_Of_Statement) or_return
						break loop
					case .Const:
						parse_constant(self)
					case:
						inst := parse_instruction(self, k, len(block)) or_return
						append(&block, inst)
					}

				case Token_Identifier:
					parse_block(self, tok.raw) or_return
				case:
					return .Unexpected_Token

				}
			}

			asm_register_block(self, self.current_scope[:], block[:]) or_return

			return nil
		}
		parse_instruction :: proc(
			self: ^Assembler,
			keyword: Token_Keyword,
			offset: int,
		) -> (
			inst: VM_Instruction,
			err: AssemblerError,
		) {
			switch keyword {
			case .Get:
				inst.op = .GetParam

				tok := scanner_peek(self) or_return
				if check_token(tok, Token_Slash) {
					_ = expect(self, Token_Slash) or_return
					inst.precondition = parse_precondition(self) or_return
				}

				param := expect(self, Token_Parameter) or_return
				inst.imm[0] = lookup_parameter_by_name(param.raw) or_return

				_ = expect(self, Token_End_Of_Statement) or_return
			case .Set:
				inst.op = .SetParam

				tok := scanner_peek(self) or_return
				if check_token(tok, Token_Slash) {
					_ = expect(self, Token_Slash) or_return
					inst.precondition = parse_precondition(self) or_return
				}

				param := expect(self, Token_Parameter) or_return
				inst.imm[0] = lookup_parameter_by_name(param.raw) or_return

				_ = expect(self, Token_End_Of_Statement) or_return
			case .Push:
				inst.op = .Push

				tok:= scanner_peek(self) or_return
				if check_token(tok, Token_Slash) {
					_ = expect(self, Token_Slash) or_return
					inst.precondition = parse_precondition(self) or_return

					imm0, maybe_constant_name := parse_literal(self) or_return
					if constant_name, ok := maybe_constant_name.(string); ok {
						append(&self.relocations, Relocation{
							block_path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = false,
							constant_name = constant_name,
						})
					}
					inst.imm[0] = imm0

					tok := scanner_peek(self) or_return
					if check_token(tok, Token_Comma) {
						_ = expect(self, Token_Comma) or_return
						imm1, maybe_constant_name := parse_literal(self) or_return
						if constant_name, ok := maybe_constant_name.(string); ok {
							append(&self.relocations, Relocation{
								block_path = slice.clone(self.current_scope[:], self.allocator),
								offset = offset,
								pred = true,
								constant_name = constant_name,
							})
						}
						inst.imm[1] = imm1
					}
				} else {
					imm, maybe_constant_name := parse_literal(self) or_return
					if constant_name, ok := maybe_constant_name.(string); ok {
						append(&self.relocations, Relocation{
							block_path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = false,
							constant_name = constant_name,
						})
					}
					inst.imm[0] = imm
				}

				_ = expect(self, Token_End_Of_Statement) or_return
			case .Jump:
				inst.op = .Jump
				tok := scanner_peek(self) or_return
				if check_token(tok, Token_Slash) {
					_ = expect(self, Token_Slash) or_return
					inst.precondition = parse_precondition(self) or_return

					l0 := expect(self, Token_Label) or_return
					append(&self.block_refs, BlockRef{
						block_path = slice.clone(self.current_scope[:], self.allocator),
						offset = offset,
						pred = false,
						ref = l0.raw[1:],
					})

					tok := scanner_peek(self) or_return
					if check_token(tok, Token_Comma) {
						_ = expect(self, Token_Comma) or_return

						l1 := expect(self, Token_Label) or_return
						append(&self.block_refs, BlockRef{
							block_path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = true,
							ref = l1.raw[1:],
						})
					}
				} else {
					l := expect(self, Token_Label) or_return
					append(&self.block_refs, BlockRef{
						block_path = slice.clone(self.current_scope[:], self.allocator),
						offset = offset,
						pred = false,
						ref = l.raw[1:],
					})
				}

				_ = expect(self, Token_End_Of_Statement) or_return
			case .Pop:
				inst.op = .Pop
				parse_basic_instruction(self, &inst) or_return
			case .Add:
				inst.op = .Add
				parse_basic_instruction(self, &inst) or_return
			case .Sub:
				inst.op = .Subtract
				parse_basic_instruction(self, &inst) or_return
			case .Mul:
				inst.op = .Multiply
				parse_basic_instruction(self, &inst) or_return
			case .Div:
				inst.op = .Divide
				parse_basic_instruction(self, &inst) or_return
			case .Rand:
				inst.op = .Rand
				parse_basic_instruction(self, &inst) or_return
			case .Spawn:
				unimplemented()
			case .Const, .End:
				unreachable()
			}
			return
		}
		parse_basic_instruction :: proc(s: ^Scanner, inst: ^VM_Instruction) -> AssemblerError {
			tok := scanner_next(s) or_return
			#partial switch k in tok.kind {
			case Token_Slash:
				inst.precondition = parse_precondition(s) or_return
				_ = expect(s, Token_End_Of_Statement) or_return
			case Token_End_Of_Statement:
			case:
				return .Unexpected_Token
			}

			return nil
		}
		parse_precondition :: proc(s: ^Scanner) -> (cond: VM_Precondition, err: AssemblerError) {
			predicate := expect(s, Token_Identifier) or_return
			switch predicate.raw {
			case "eq":
				return .Eq, nil
			case "neq":
				return .Neq, nil
			case "lt":
				return .Lt, nil
			case "leq":
				return .Leq, nil
			case "gt":
				return .Gt, nil
			case "geq":
				return .Geq, nil
			case:
				return {}, .Undefined_Predicate
			}
		}
		parse_literal :: proc(self: ^Assembler) -> (
			result: VM_Value,
		 	constant_name: Maybe(string),
			err: AssemblerError
		) {
			tok := scanner_next(self) or_return

			#partial switch k in tok.kind {
			case Token_IntLit:
				result = k
			case Token_FloatLit:
				result = k
			case Token_BoolLit:
				result = k
			case Token_HexLit:
				result = rgba_u32_to_color(k)
			case Token_Identifier:
				constant_name = parse_constant_literal(self, tok.raw) or_return
			case:
				err = .Unexpected_Token // Is there a better error I can put here?
			}
			return
		}

		check_token :: proc(token: Token, $T: typeid) -> bool {
			_, ok := token.kind.(T)
			return ok
		}
		@(require_results)
		expect :: proc(s: ^Scanner, $T: typeid) -> (tok: Token, err: AssemblerError) {
			tok = scanner_next(s) or_return
			if _, ok := tok.kind.(T); ok {
				return tok, nil
			} else {
				return tok, .Unexpected_Token
			}
		}
	}

}

ScannerState :: enum {
	EatWhitespace,
	Main,
	Identifier,
	Parameter,
	Comment,
	Colon,
	Minus,
	Digits,
	Period,
	FloatLit,
	HexLit,
	Label,
}
Scanner :: struct {
	state:     ScannerState,
	line, col: u32,
	head:      string,
	prev:      Token_Kind,
}
ScannerError :: enum {
	None = 0,
	Unexpected_End_Of_File,
}
scanner_peek :: proc(s: ^Scanner) -> (next: Token, err: ScannerError) {
	tmp := s^
	defer s^ = tmp
	return scanner_next(s)
}
scanner_next :: proc(s: ^Scanner) -> (next: Token, err: ScannerError) {
	for {
		switch s.state {
		case .EatWhitespace:
			c := peek(s) or_return
			switch c {
			case ' ', '\t', '\r', '\v', '\f':
				advance(s)
			case '\n':
				next = begin_token(s)
				advance(s)
				out := end_token(s, next, Token_End_Of_Statement{})
				s.line += 1
				s.col = 0
				if s.prev != nil {
					s.prev = nil
					return out, .None
				}
			case:
				s.state = .Main
			}
		case .Main:
			c := peek(s) or_return
			switch c {
			case '=':
				next = begin_token(s)
				advance(s)
				return end_token(s, next, Token_Equals{}), .None
			case ';':
				s.state = .Comment
			case '_', 'a' ..= 'z', 'A' ..= 'Z':
				next = begin_token(s)
				s.state = .Identifier
			case '/':
				next = begin_token(s)
				advance(s)
				return end_token(s, next, Token_Slash{}), .None
			case ',':
				next = begin_token(s)
				advance(s)
				return end_token(s, next, Token_Comma{}), .None
			case ':':
				next = begin_token(s)
				advance(s)
				s.state = .Colon
			case '-':
				next = begin_token(s)
				advance(s)
				s.state = .Minus
			case '#':
				next = begin_token(s)
				advance(s)
				s.state = .HexLit
			case '$':
				next = begin_token(s)
				advance(s)
				s.state = .Parameter
			case '.':
				next = begin_token(s)
				advance(s)
				s.state = .Period
			case '0' ..= '9':
				next = begin_token(s)
				advance(s)
				s.state = .Digits
			case:
				fmt.panicf("Unimplemented: Head is at: [%v]\"%c\".", s.head[0], s.head[0])
			}
		case .Parameter:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_Parameter{}), .None
			} else {
				switch c {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
					advance(s)
				case:
					return end_token(s, next, Token_Parameter{}), .None
				}
			}
		case .Identifier:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_Identifier{}), .None
			} else {
				switch c {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
					advance(s)
				case:
					return end_token(s, next, Token_Identifier{}), .None
				}
			}
		case .Comment:
			if c, err := peek(s); err != .None {
				return {}, .Unexpected_End_Of_File
			} else {
				switch c {
				case '\n':
					s.state = .EatWhitespace
				case:
					advance(s)
				}
			}
		case .Minus:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_Minus{}), .None
			} else {
				switch c {
				case '0' ..= '9', '.':
					s.state = .Digits
				case:
					return end_token(s, next, Token_Minus{}), .None
				}
			}
		case .Digits:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_IntLit{}), .None
			} else {
				switch c {
				case '.':
					advance(s)
					s.state = .FloatLit
				case '0' ..= '9', '_':
					advance(s)
				case:
					return end_token(s, next, Token_IntLit{}), .None
				}
			}
		case .Colon:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_Colon{}), .None
			} else {
				switch c {
				case 'a' ..= 'z', 'A' ..= 'Z':
					s.state = .Label
				case:
					return end_token(s, next, Token_Colon{}), .None
				}
			}
		case .Label:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_Label{}), .None
			} else {
				switch c {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', ':':
					advance(s)
				case:
					return end_token(s, next, Token_Label{}), .None
				}
			}
		case .Period:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_Period{}), .None
			} else {
				switch c {
				case '0' ..= '9':
					s.state = .FloatLit
				case:
					return end_token(s, next, Token_Period{}), .None
				}
			}
		case .FloatLit:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_FloatLit{}), .None
			} else {
				switch c {
				case '0' ..= '9', '_':
					advance(s)
				case:
					return end_token(s, next, Token_FloatLit{}), .None
				}
			}
		case .HexLit:
			if c, err := peek(s); err != .None {
				return end_token(s, next, Token_HexLit{}), .None
			} else {
				switch c {
				case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F', '_':
					advance(s)
				case:
					return end_token(s, next, Token_HexLit{}), .None
				}
			}
		}

	}

	begin_token :: proc(s: ^Scanner) -> Token {
		return {line = s.line, col = s.col, raw = s.head}
	}
	end_token :: proc(s: ^Scanner, t: Token, kind: Token_Kind) -> (out: Token) {
		if _, ok := kind.(Token_End_Of_Statement); !ok {
			s.prev = kind
		}

		out.kind = kind

		token_len := len(t.raw) - len(s.head)
		out.raw = t.raw[:token_len]

		#partial switch k in kind {
		case Token_Identifier:
			switch out.raw {
			case "true":
				out.kind = true
			case "false":
				out.kind = false
			case "const":
				out.kind = Token_Keyword.Const
			case "push":
				out.kind = Token_Keyword.Push
			case "pop":
				out.kind = Token_Keyword.Pop
			case "mul":
				out.kind = Token_Keyword.Mul
			case "div":
				out.kind = Token_Keyword.Div
			case "add":
				out.kind = Token_Keyword.Add
			case "sub":
				out.kind = Token_Keyword.Sub
			case "rand":
				out.kind = Token_Keyword.Rand
			case "jump":
				out.kind = Token_Keyword.Jump
			case "spawn":
				out.kind = Token_Keyword.Spawn
			case "end":
				out.kind = Token_Keyword.End
			case "get":
				out.kind = Token_Keyword.Get
			case "set":
				out.kind = Token_Keyword.Set
			}
		case Token_IntLit:
			v, ok := strconv.parse_i64(out.raw, 10)
			assert(ok)
			out.kind = i32(v)
		case Token_HexLit:
			v, ok := strconv.parse_u64(out.raw[1:], 16)
			assert(ok)
			out.kind = u32(v)
		case Token_FloatLit:
			v, _, ok := strconv.parse_f32_prefix(out.raw)
			assert(ok)
			out.kind = v
		}

		s.state = .EatWhitespace
		return
	}
	peek :: proc(s: ^Scanner) -> (c: u8, err: ScannerError) {
		if len(s.head) != 0 {
			return s.head[0], .None
		} else {
			return {}, .Unexpected_End_Of_File
		}
	}
	// unsafe
	advance :: proc(s: ^Scanner) {
		s.head = s.head[1:]
		s.col += 1
	}
}
