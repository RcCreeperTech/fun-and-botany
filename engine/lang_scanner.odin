package web_testing

import "core:strconv"
import "core:log"

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
	Ret,
	Call,
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
Token_NumberLit :: f32
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
	Token_NumberLit,
	Token_HexLit,
	Token_BoolLit,
	Token_Keyword,
	Token_End_Of_Statement,
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
				log.panicf("Unimplemented: Head is at: [%v]\"%c\".", s.head[0], s.head[0])
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
				return end_token(s, next, Token_NumberLit{}), .None
			} else {
				switch c {
				case '.':
					advance(s)
					s.state = .FloatLit
				case '0' ..= '9', '_':
					advance(s)
				case:
					return end_token(s, next, Token_NumberLit{}), .None
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
				return end_token(s, next, Token_NumberLit{}), .None
			} else {
				switch c {
				case '0' ..= '9', '_':
					advance(s)
				case:
					return end_token(s, next, Token_NumberLit{}), .None
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
			case "ret":
				out.kind = Token_Keyword.Ret
			case "call":
				out.kind = Token_Keyword.Call
			}
		case Token_HexLit:
			v, ok := strconv.parse_u64(out.raw[1:], 16)
			assert(ok)
			out.kind = u32(v)
		case Token_NumberLit:
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
