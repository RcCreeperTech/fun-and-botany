package web_testing

import "core:log"
import "core:fmt"
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
	Dye,
	End,
}
Token_Identifier :: struct {}
Token_Minus :: struct {}
Token_Colon :: struct {}
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
	AsmError,
	ParseError,
}

AsmError :: enum {
	None = 0,
	No_Entrypoint_Found,
}

ParseError :: enum {
	None = 0,
	Undefined_Predicate,
	Unexpected_End_Of_File,
	Unexpected_Token,
	Unexpected_Top_Level_Keyword,
}

// TODO: Error reporting needs to improve a lot. Currently the error value is
// just bubbled out to the caller of assemble but no context for the error is
// collected.
asm_assemble :: proc(
	source: string,
	allocator := context.allocator,
) -> (
	program: VM_Program,
	err: AssemblerError,
) {
	s: Scanner = {
		head = source,
	}

	BlockMap :: map[string][dynamic]VM_Instruction
	JumpTable :: struct {
		gid:   VM_Label,
		table: map[string]VM_Label,
	}
	make_jump_table :: proc(allocator := context.allocator) -> (jt: JumpTable) {
		jt.table = make(map[string]VM_Label, allocator)
		jt.table["Main"] = 0 // TODO: Add tagging to remove this special case
		jt.gid = 1
		return
	}
	// Tries to find the id associated with a jump label. Will automatically
	// create a new id if the label is not already in the table.
	jt_lookup_label :: proc(jt: ^JumpTable, label: string) -> VM_Label {
		// This is the easiest way to make sure that labels and blocks refer to the same thing
		label := label
		if label[0] == ':' do label = label[1:]

		if id, ok := jt.table[label]; ok {
			return id
		} else {
			next_id := jt.gid
			jt.gid += 1
			jt.table[label] = next_id
			return next_id
		}
	}
	blocks := make(BlockMap) // TODO: Arena?
	jump_table := make_jump_table() // TODO: cleanup

	parse(&s, &blocks, &jump_table) or_return

	program.blocks = make([]VM_Block, len(blocks), allocator)
	found_main := false
	for name, block in blocks {
		block_id := jt_lookup_label(&jump_table, name)
		program.blocks[block_id] = block[:]
		if name == "Main" {
			found_main = true
		}
	}

	if !found_main {
		return {}, AsmError.No_Entrypoint_Found
	}

	return program, AsmError.None

	parse :: proc(s: ^Scanner, blocks: ^BlockMap, jt: ^JumpTable) -> (t: Token, err: ParseError) {
		for {
			tok := scanner_next(s) or_break

			#partial switch k in tok.kind {
			case Token_Identifier:
				parse_block(s, blocks, jt, tok.raw) or_return
			case Token_Keyword:
				if k != .Const {
					return t, .Unexpected_Top_Level_Keyword
				}
				unimplemented("TODO: parse_const")
			case:
				fmt.panicf("ERROR: Unexpected Top Level token: %v", tok)
			}

		}
		return {}, .None


		parse_block :: proc(
			s: ^Scanner,
			blocks: ^BlockMap,
			jt: ^JumpTable,
			label: string,
		) -> (
			err: ParseError,
		) {
			block := make([dynamic]VM_Instruction) // TODO: Arena

			_ = expect(s, Token_Colon) or_return
			_ = expect(s, Token_End_Of_Statement) or_return

			loop: for {
				if tok, ok := scanner_next(s); ok {
					#partial switch k in tok.kind {
					case Token_Keyword:
						#partial switch k {
						case .End:
							_ = expect(s, Token_End_Of_Statement) or_return
							break loop
						case .Const:
							unimplemented("What to do here")
						case:
							inst := parse_instruction(s, k, jt) or_return
							append(&block, inst)
						}

					case Token_Identifier:
						sublabel := fmt.aprintf("%s:%s", label, tok.raw) // TODO: Arena
						parse_block(s, blocks, jt, sublabel) or_return

					case:
						return .Unexpected_Token

					}
				} else {
					return .Unexpected_End_Of_File
				}
			}

			blocks[label] = block

			return .None
		}
		parse_instruction :: proc(
			s: ^Scanner,
			keyword: Token_Keyword,
			jt: ^JumpTable,
		) -> (
			inst: VM_Instruction,
			err: ParseError,
		) {
			switch keyword {
			case .Push:
				inst.op = .Push

				if tok, ok := scanner_peek(s); ok {
					#partial switch k in tok.kind {
					case Token_Slash:
						_ = expect(s, Token_Slash) or_return
						inst.precondition = parse_precondition(s) or_return
						inst.imm[0] = parse_literal(s, jt) or_return
						_ = expect(s, Token_Comma) or_return
						inst.imm[1] = parse_literal(s, jt) or_return
					case:
						value := parse_literal(s, jt) or_return
						inst.imm[0] = value
					}
				} else {
					return {}, .Unexpected_End_Of_File
				}

				_ = expect(s, Token_End_Of_Statement) or_return
			case .Jump:
				inst.op = .Jump

				if tok, ok := scanner_peek(s); ok {
					#partial switch k in tok.kind {
					case Token_Slash:
						_ = expect(s, Token_Slash) or_return
						inst.precondition = parse_precondition(s) or_return
						inst.imm[0] = parse_literal(s, jt) or_return
						_ = expect(s, Token_Comma) or_return
						inst.imm[1] = parse_literal(s, jt) or_return
					case:
						value := parse_literal(s, jt) or_return
						inst.imm[0] = value
					}
				} else {
					return {}, .Unexpected_End_Of_File
				}

				_ = expect(s, Token_End_Of_Statement) or_return
			case .Pop:
				inst.op = .Pop
				parse_basic_instruction(s, &inst) or_return
			case .Add:
				inst.op = .Add
				parse_basic_instruction(s, &inst) or_return
			case .Sub:
				inst.op = .Subtract
				parse_basic_instruction(s, &inst) or_return
			case .Mul:
				inst.op = .Multiply
				parse_basic_instruction(s, &inst) or_return
			case .Div:
				inst.op = .Divide
				parse_basic_instruction(s, &inst) or_return
			case .Rand:
				inst.op = .Rand
				parse_basic_instruction(s, &inst) or_return
			case .Spawn:
				unimplemented()
			case .Dye:
				unimplemented()
			case .Const, .End:
				unreachable()
			}
			return inst, .None
		}
		parse_basic_instruction :: proc(s: ^Scanner, inst: ^VM_Instruction) -> ParseError {
			if tok, ok := scanner_next(s); ok {
				#partial switch k in tok.kind {
				case Token_Slash:
					inst.precondition = parse_precondition(s) or_return
					_ = expect(s, Token_End_Of_Statement) or_return
				case Token_End_Of_Statement:
				case:
					return .Unexpected_Token
				}
			} else {
				return .Unexpected_End_Of_File
			}
			return .None
		}
		parse_precondition :: proc(s: ^Scanner) -> (cond: VM_Precondition, err: ParseError) {
			predicate := expect(s, Token_Identifier) or_return
			switch predicate.raw {
			case "eq":
				return .Eq, .None
			case "neq":
				return .Neq, .None
			case "lt":
				return .Lt, .None
			case "leq":
				return .Leq, .None
			case "gt":
				return .Gt, .None
			case "geq":
				return .Geq, .None
			case:
				return {}, .Undefined_Predicate
			}
		}
		parse_literal :: proc(s: ^Scanner, jt: ^JumpTable) -> (VM_Value, ParseError) {
			if tok, ok := scanner_next(s); ok {
				#partial switch k in tok.kind {
				case Token_IntLit:
					return k, .None
				case Token_FloatLit:
					return k, .None
				case Token_BoolLit:
					return k, .None
				case Token_HexLit:
					return rgba_u32_to_color(k), .None
				case Token_Label:
					return jt_lookup_label(jt, tok.raw), .None
				case:
					return {}, .Unexpected_Token // Is there a better error I can put here?
				}
			} else {
				return {}, .Unexpected_End_Of_File
			}
		}

		check_token :: proc(token: Token, $T: typeid) -> ParseError {
			if _, ok := token.kind.(T); ok {
				return .None
			} else {
				return .Unexpected_Token
			}
		}
		@(require_results)
		expect :: proc(s: ^Scanner, $T: typeid) -> (Token, ParseError) {
			if tok, ok := scanner_next(s); ok {
				if _, ok := tok.kind.(T); ok {
					return tok, .None
				} else {
					return tok, .Unexpected_Token
				}
			} else {
				return {}, .Unexpected_End_Of_File
			}
		}
	}

}

ScannerState :: enum {
	EatWhitespace,
	Main,
	Identifier,
	Comment,
	Colon,
	Minus,
	Digits,
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
scanner_peek :: proc(s: ^Scanner) -> (next: Token, ok: bool) {
	tmp := s^
	defer s^ = tmp
	return scanner_next(s)
}
scanner_next :: proc(s: ^Scanner) -> (next: Token, ok: bool) {
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
					return out, true
				}
			case:
				s.state = .Main
			}
		case .Main:
			c := peek(s) or_return
			switch c {
			case ';':
				s.state = .Comment
			case '_', 'a' ..= 'z', 'A' ..= 'Z':
				next = begin_token(s)
				s.state = .Identifier
			case '/':
				next = begin_token(s)
				advance(s)
				return end_token(s, next, Token_Slash{}), true
			case ',':
				next = begin_token(s)
				advance(s)
				return end_token(s, next, Token_Comma{}), true
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
			case '.':
				next = begin_token(s)
				advance(s)
				s.state = .FloatLit
			case '0' ..= '9':
				next = begin_token(s)
				advance(s)
				s.state = .Digits
			case:
				fmt.panicf("Unimplemented: Head is at: [%v]\"%c\".", s.head[0], s.head[0])
			}
		case .Identifier:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_Identifier{}), true
			} else {
				switch c {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
					advance(s)
				case:
					return end_token(s, next, Token_Identifier{}), true
				}
			}
		case .Comment:
			if c, ok := peek(s); !ok {
				return {}, false
			} else {
				switch c {
				case '\n':
					s.state = .EatWhitespace
				case:
					advance(s)
				}
			}
		case .Minus:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_Minus{}), true
			} else {
				switch c {
				case '0' ..= '9', '.':
					s.state = .Digits
				case:
					return end_token(s, next, Token_Minus{}), true
				}
			}
		case .Digits:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_IntLit{}), true
			} else {
				switch c {
				case '.':
					advance(s)
					s.state = .FloatLit
				case '0' ..= '9', '_':
					advance(s)
				case:
					return end_token(s, next, Token_IntLit{}), true
				}
			}
		case .Colon:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_Colon{}), true
			} else {
				switch c {
				case 'a' ..= 'z', 'A' ..= 'Z':
					s.state = .Label
				case:
					return end_token(s, next, Token_Colon{}), true
				}
			}
		case .Label:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_Label{}), true
			} else {
				switch c {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', ':':
					advance(s)
				case:
					return end_token(s, next, Token_Label{}), true
				}
			}
		case .FloatLit:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_FloatLit{}), true
			} else {
				switch c {
				case '0' ..= '9', '_':
					advance(s)
				case:
					return end_token(s, next, Token_FloatLit{}), true
				}
			}
		case .HexLit:
			if c, ok := peek(s); !ok {
				return end_token(s, next, Token_HexLit{}), true
			} else {
				switch c {
				case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F', '_':
					advance(s)
				case:
					return end_token(s, next, Token_HexLit{}), true
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
			case "dye":
				out.kind = Token_Keyword.Dye
			case "end":
				out.kind = Token_Keyword.End
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
	peek :: proc(s: ^Scanner) -> (c: u8, ok: bool) {
		if len(s.head) != 0 {
			return s.head[0], true
		} else {
			return {}, false
		}
	}
	// unsafe
	advance :: proc(s: ^Scanner) {
		s.head = s.head[1:]
		s.col += 1
	}
}
