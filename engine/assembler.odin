package web_testing

import "core:fmt"
import "core:strconv"
import "core:testing"

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
	End,
}
Token_Identifier :: struct {}
Token_Minus :: struct {}
Token_Colon :: struct {}
Token_IntLit :: i32
Token_FloatLit :: f32
Token_HexLit :: u32

Token_Kind :: union {
	Token_Identifier,
	Token_Minus,
	Token_Colon,
	Token_IntLit,
	Token_FloatLit,
	Token_HexLit,
}

asm_assemble :: proc(source: string, allocator := context.allocator) -> bool {
	tokens := make([dynamic]Token, allocator)
	t: Tokenizer = {
		head = source,
	}
	ok := tokenize(&t, &tokens)
	assert(ok)
	fmt.printfln("We got the tokens: %v")

	BlockMap :: map[string]VM_Block
	blocks := make(BlockMap)
	parse(&tokens, &blocks)

	unimplemented("We cannot assemble yet :(")

	parse :: proc(tokens: ^[dynamic]Token, ast: ^BlockMap) {
		unimplemented("We dont do that here...")
	}

	TokenizerState :: enum {
		EatWhitespace,
		Main,
		Identifier,
		Comment,
		Minus,
		Digits,
		FloatLit,
		HexLit,
	}
	Tokenizer :: struct {
		state:     TokenizerState,
		line, col: u32,
		head:      string,
		tmp_token: Token,
		ok:        bool,
	}
	tokenize :: proc(t: ^Tokenizer, tokens: ^[dynamic]Token) -> bool {
		step: for {
			switch t.state {
			case .EatWhitespace:
				c, ok := next_rune(t)
				// If we run out of runes when in whitespace mode that is valid
				// stopping point for the tokenizer
				if !ok {
					t.ok = true
					break step
				}
				switch c {
				case '\n':
					advance(t)
					t.line += 1
					t.col = 0
				case ' ', '\t', '\r':
					advance(t)
				case:
					t.state = .Main
				}
			case .Main:
				c := next_rune(t) or_break step
				switch c {
				case ';':
					t.state = .Comment
				case '_', 'a' ..= 'z', 'A' ..= 'Z':
					begin_token(t)
					t.state = .Identifier
				case ':':
					begin_token(t)
					end_token(t, tokens, Token_Colon{})
				case '-':
					begin_token(t)
					t.state = .Minus
				case '#':
					begin_token(t)
					t.state = .HexLit
				case '.':
					begin_token(t)
					t.state = .FloatLit
				case '0' ..= '9':
					begin_token(t)
					t.state = .Digits
				case:
					fmt.panicf(
						"Unimplemented: Head is at: [%v]\"%c\".\nTokens = %v",
						t.head[0],
						t.head[0],
						tokens^,
					)
				}
			case .Identifier:
				c := next_rune(t) or_break step
				switch c {
				case '_', 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9':
					advance(t)
				case:
					end_token(t, tokens, Token_Identifier{})
				}
			case .Comment:
				c := next_rune(t) or_break step
				switch c {
				case '\n':
					advance(t)
					t.line += 1
					t.col = 0
					t.state = .EatWhitespace
				case:
					advance(t)
				}
			case .Minus:
				c := next_rune(t) or_break step
				switch c {
				case '0' ..= '9', '.':
					t.state = .Digits
				case:
					end_token(t, tokens, Token_Minus{})
				}
			case .Digits:
				c := next_rune(t) or_break step
				switch c {
				case '.':
					advance(t)
					t.state = .FloatLit
				case '0' ..= '9', '_':
					advance(t)
				case:
					end_token(t, tokens, Token_IntLit{})
				}
			case .FloatLit:
				c := next_rune(t) or_break step
				switch c {
				case '0' ..= '9', '_':
					advance(t)
				case:
					end_token(t, tokens, Token_FloatLit{})
				}
			case .HexLit:
				c := next_rune(t) or_break step
				switch c {
				case '0' ..= '9', 'a' ..= 'f', 'A' ..= 'F', '_':
					advance(t)
				case:
					end_token(t, tokens, Token_HexLit{})
				}
			}

		}

		return t.ok

		begin_token :: proc(t: ^Tokenizer) {
			t.ok = false
			t.tmp_token = Token {
				line = t.line,
				col  = t.col,
				raw  = t.head,
			}
			advance(t)
		}
		end_token :: proc(t: ^Tokenizer, tokens: ^[dynamic]Token, kind: Token_Kind) {
			t.tmp_token.kind = kind

			token_len := len(t.tmp_token.raw) - len(t.head)
			t.tmp_token.raw = t.tmp_token.raw[:token_len]

			#partial switch &k in t.tmp_token.kind {
			case Token_IntLit:
				v, ok := strconv.parse_i64(t.tmp_token.raw, 10)
				assert(ok)
				k = i32(v)
			case Token_HexLit:
				v, ok := strconv.parse_u64(t.tmp_token.raw[1:], 16)
				assert(ok)
				k = u32(v)
			case Token_FloatLit:
				v, _, ok := strconv.parse_f32_prefix(t.tmp_token.raw)
				assert(ok)
				k = v
			}

			fmt.printfln("Formed a token: %v", t.tmp_token)
			append(tokens, t.tmp_token)

			t.state = .EatWhitespace
			t.ok = true
		}
		next_rune :: proc(t: ^Tokenizer) -> (u8, bool) {
			if len(t.head) != 0 {
				return t.head[0], true
			} else {
				return {}, false
			}
		}
		// unsafe
		advance :: proc(t: ^Tokenizer) {
			t.head = t.head[1:]
			t.col += 1
		}
	}
}

@(test)
debug_harness :: proc(t: ^testing.T) {
	asm_assemble(i_want_to_compile_this)
}

i_want_to_compile_this :: `
; This is a test of pushing literal values.

; I like writing comments

Main:
	push .1
	push 1_2_3_4
	push -1_2_3_4
	push 0.1
	push -.12
	push 1
	push 0
	push true
	push false
	push #181818ff ; Random Comment
	push #281858fF
	push :Main
`
