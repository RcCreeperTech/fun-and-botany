package compiler

import "core:strconv"
import "core:log"

Color :: [4]u8

SrcLoc :: struct {
	line, col: u32,
	raw: string,
}

Token_Kind :: enum {
	Invalid = 0,
	Keyword_End,
	Keyword_Def,
	Keyword_If,
	Keyword_Else,
	Keyword_Return,
	Keyword_And,
	Keyword_Or,

	Literal_Color,
	Literal_Number,
	Literal_State_Label,
	Literal_Boolean,

	Identifier,
	Builtin_Identifier,

	Plus, Minus,
	Asterisk, Forward_Slash,

	Less, Less_Equals,
	Greater, Greater_Equals,
	Equals, Equals_Equals,
	Exclamation, Exclamation_Equals,

	Colon, Period, Comma,
	Open_Paren, Close_Paren,
	At,

	Error,
	End_Of_Statement,
	End_Of_Stream,
}

Token :: struct {
	using loc:     SrcLoc,
	kind:          Token_Kind,
	literal_value: union {
		string,
		f32,
		Color,
		bool,
		ScannerError,
	}
}

Scanner :: struct {
	line, col: u32,
	source:    string,
	head:      string,
	prev:      Token_Kind,
	builder:   Token,
}
ScannerError :: enum {
	None = 0,
	Malformed_Builtin,
	Malformed_Number,
	Malformed_Color,
}

scanner_init :: proc(s: ^Scanner, source: string) {
	s.source = source
	s.head = source
}

scanner_collect :: proc(source: string, allocator := context.allocator) -> []Token {
	s: Scanner
	scanner_init(&s, source)
	tokens := make([dynamic]Token, allocator)
	for {
		tok := scanner_next(&s)
		append(&tokens, tok)
		if tok.kind == .End_Of_Stream do break
	}
	return tokens[:]
}

scanner_peek :: proc(s: ^Scanner) -> Token {
	tmp := s^
	defer s^ = tmp
	return scanner_next(s)
}
scanner_next :: proc(s: ^Scanner) -> Token {
	if t, emitted := skip_whitespace(s); emitted {
		return t
	}

	switch peek(s) {
	case 0:
	  	return { kind = .End_Of_Stream }
	case '@':
		begin_token(s)
		return end_token(s, .At)
	case ',':
		begin_token(s)
		return end_token(s, .Comma)
	case '(':
		begin_token(s)
		return end_token(s, .Open_Paren)
	case ')':
		begin_token(s)
		return end_token(s, .Close_Paren)
	case '*':
		begin_token(s)
		return end_token(s, .Asterisk)
	case '/':
		begin_token(s)
		return end_token(s, .Forward_Slash)
	case '+':
		begin_token(s)
		return end_token(s, .Plus)
	case '!':
		begin_token(s)
		if peek(s) == '=' {
			advance(s)
			return end_token(s, .Exclamation_Equals)
		} else {
			return end_token(s, .Exclamation)
		}
	case '=':
		begin_token(s)
		if peek(s) == '=' {
			advance(s)
			return end_token(s, .Equals_Equals)
		} else {
			return end_token(s, .Equals)
		}
	case '<':
		begin_token(s)
		if peek(s) == '=' {
			advance(s)
			return end_token(s, .Less_Equals)
		} else {
			return end_token(s, .Less)
		}
	case '>':
		begin_token(s)
		if peek(s) == '=' {
			advance(s)
			return end_token(s, .Greater_Equals)
		} else {
			return end_token(s, .Greater)
		}
	case '_', 'a' ..= 'z', 'A' ..= 'Z':
		begin_token(s)
		for do switch peek(s) {
		case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
			advance(s)
		case:
			return end_token(s, .Identifier)
		}
	case '$':
		begin_token(s)
		switch peek(s) {
		case 'a' ..= 'z', 'A' ..= 'Z':
			advance(s)
		case:
			err := end_token(s, .Error)
			err.literal_value = ScannerError.Malformed_Builtin
			return err
		}

		for do switch peek(s) {
		case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
			advance(s)
		case:
			return end_token(s, .Builtin_Identifier)
		}
	case ':':
		begin_token(s)
		switch peek(s) {
			case '_', 'a' ..= 'z', 'A' ..= 'Z':
				for do switch peek(s) {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
					advance(s)
				case:
					return end_token(s, .Identifier)
				}
			case:
				return end_token(s, .Colon)
		}
	case '-':
		begin_token(s)
		switch peek(s) {
			case '0' ..= '9', '.':
				return scan_number(s)
			case:
				return end_token(s, .Minus)
		}
	case '.':
		begin_token(s)
		switch peek(s) {
			case '0' ..= '9':
				return scan_number(s)
			case:
				return end_token(s, .Period)
		}
	case '0' ..= '9':
		begin_token(s)
		return scan_number(s)
	case '#':
		begin_token(s)
		counter: int = 8
		for do switch peek(s) {
		case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F', '_':
			advance(s)
		case:
			out := end_token(s, .Literal_Color)
			v, ok := strconv.parse_u64(s.builder.raw[1:], 16)
			if !ok {
				out.kind = .Error
				out.literal_value = ScannerError.Malformed_Color
			} else {
				r := u8(v >> 24)
				g := u8(v >> 16)
				b := u8(v >> 8)
				a := u8(v >> 0)
				out.literal_value =  Color {r, g, b, a}
			}
			return out
		}

	case:
		log.panicf("Unimplemented: Head is at: [%v]\"%c\".", s.head[0], s.head[0])
	}

	scan_number :: proc(s: ^Scanner) -> Token {
		for do switch peek(s) {
			case '0' ..= '9', '.', '_': advance(s)
			case:
				out := end_token(s, .Literal_Number)
				v, _, ok := strconv.parse_f32_prefix(s.builder.raw)
				if !ok {
					out.kind = .Error
					out.literal_value = ScannerError.Malformed_Number
				} else {
					out.literal_value = v
				}
				return out
		}
	}

	begin_token :: proc(s: ^Scanner) {
		s.builder = Token{ loc = {
				col = s.col,
				line = s.line,
				raw = s.head,
		} }
		advance(s)
	}
	end_token :: proc(s: ^Scanner, kind: Token_Kind) -> Token {
		if kind != .End_Of_Statement {
			s.prev = kind
		}
		s.builder.kind = kind

		token_len := len(s.builder.raw) - len(s.head)
		s.builder.raw = s.builder.raw[:token_len]

		#partial switch kind {
		case .Identifier:
			switch s.builder.raw {
			case "true":
				s.builder.kind = .Literal_Boolean
				s.builder.literal_value = true
			case "false":
				s.builder.kind = .Literal_Boolean
				s.builder.literal_value = false
			case "end":
				s.builder.kind = .Keyword_End
			case "def":
				s.builder.kind = .Keyword_Def
			case "if":
				s.builder.kind = .Keyword_If
			case "else":
				s.builder.kind = .Keyword_Else
			case "return":
				s.builder.kind = .Keyword_Return
			case "and":
				s.builder.kind = .Keyword_And
			case "or":
				s.builder.kind = .Keyword_Or
			}
		}

		return s.builder
	}
	peek :: proc(s: ^Scanner) -> (c: u8) {
		if len(s.head) == 0 {
			return 0
		}
		return s.head[0]
	}
	peek_next :: proc(s: ^Scanner) -> (c: u8) {
		if len(s.head) <= 1 {
			return 0
		}
		return s.head[1]
	}
	// unsafe
	advance :: proc(s: ^Scanner) -> u8 {
		c := s.head[0]
		s.head = s.head[1:]
		s.col += 1
		return c
	}

	skip_whitespace :: proc(s: ^Scanner) -> (t: Token, emitted_token: bool) {
		for do switch peek(s) {
		case 0:
			return { kind = .End_Of_Stream }, true
		case ' ', '\t', '\r', '\v', '\f':
			advance(s)
		case '/': // Comments
			if (peek_next(s) == '/') {
				for peek(s) != '\n' do advance(s)
			} else {
				return
			}
		case '\n':
			begin_token(s)
			out := end_token(s, .End_Of_Statement)
			s.line += 1
			s.col = 0
			if s.prev != nil {
				s.prev = nil
				return out, true
			}
		case:
			return
		}
	}
}
