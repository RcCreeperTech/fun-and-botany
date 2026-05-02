package vm

import "core:sort"
import "base:runtime"
import "core:slice"
import "core:log"
import "core:strings"
import "core:mem"
import "core:fmt"
import "core:reflect"

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
	Unable_To_Resolve_Ref_To_Value,
	Duplicate_Identifier,
}

Constant :: Value
BlockBuilder :: [dynamic]Instruction
RelocationKind :: enum { Label, Constant }
Relocation :: struct {
	kind: RelocationKind,
	path: []string,
	name: string,
	offset: int,
	pred: bool,
}
Assembler :: struct {
	using scanner: Scanner,
	arena: mem.Dynamic_Arena,
	allocator: mem.Allocator,
	blocks: map[string]Block,
	path_builder: strings.Builder,
	current_scope: [dynamic]string,
	constants: map[string]Constant,
	relocations: [dynamic]Relocation,
	block_name_table: map[string]Label
}
asm_init :: proc(self: ^Assembler, allocator := context.allocator) {
	mem.dynamic_arena_init(&self.arena, allocator, allocator, alignment=runtime.MAP_CACHE_LINE_SIZE)
	self.allocator = mem.dynamic_arena_allocator(&self.arena)
	self.blocks = make(map[string]Block, self.allocator)
	self.constants = make(map[string]Constant,  self.allocator)
	self.relocations = make([dynamic]Relocation,  self.allocator)
	self.block_name_table = make(map[string]Label, self.allocator)
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
asm_register_block :: proc(self: ^Assembler, path: []string, block: Block) -> ParserError {
	qualified_name := asm_get_path(self, path[:], "", ":")
	if qualified_name in self.blocks do return .Duplicate_Identifier
	log.infof("Registered block: %v[%v]", qualified_name, len(block))
	self.blocks[qualified_name] = block
	return nil
}
asm_resolve_entity_ref :: proc(self: ^Assembler, ref: Relocation) -> (constant: Value, found: bool) {
	seperator := "." if ref.kind == .Constant else ":"
	path := asm_get_path_tmp(self, ref.path, "", seperator)
	log.infof("Resolving %v_ref %v::<%v>`", ref.kind, path, ref.name)
	for i := len(ref.path); i >= 0; i -= 1 {
		candidate := asm_get_path_tmp(self, ref.path[:i], ref.name, seperator)
		log.debugf("\tChecking candidate %v", candidate)
		switch ref.kind {
		case .Constant:
			if value, found := self.constants[candidate]; found {
				log.debugf("\tFound match! %v = %v", candidate, value)
				return value, true
			}
		case .Label:
			if value, found := self.block_name_table[candidate]; found {
				log.debugf("\tFound match! %v", candidate)
				return value, true
			}
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
	program: Program,
	err: AssemblerError,
) {
	self.scanner.head = source

	lookup_parameter_by_name :: proc(name: string) -> (param: Param, err: ProgramError) {
		val, ok := reflect.enum_from_name(Param, name[1:]);
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

	if entry_block, found := self.blocks["Main"]; found {
		if len(entry_block) == 0 {
			return {}, ProgramError.No_Entrypoint_Found
		}
	} else {
		return {}, ProgramError.No_Entrypoint_Found
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
	program.blocks = make([]Block, len(valid_blocks), self.allocator)
	log.infof("Linearizing %v Blocks...", len(valid_blocks))
	for name in valid_blocks {
		log.infof("Block `%v` resolved to %v", name, block_id)
		self.block_name_table[name] = Label(block_id)

		program.blocks[block_id] = self.blocks[name]
		block_id += 1
	}


	// TODO: Here is where the constant folding will happen. This can also
	// fail. so we need to track that.
	for ref in self.relocations {
		if value, found := asm_resolve_entity_ref(self, ref); found {
			name := asm_get_path(self, ref.path, "", ":")
			block_id := self.block_name_table[name]
			block := &program.blocks[block_id]
			inst := &block[ref.offset]
			inst.imm[1 if ref.pred else 0] = value
		} else {
			return program, ParserError.Unable_To_Resolve_Ref_To_Value
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
			case Token_NumberLit:
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

			block := make([dynamic]Instruction, self.allocator)

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
			inst: Instruction,
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

					parse_inst_literal(self, &inst, offset, false) or_return

					tok := scanner_peek(self) or_return
					if check_token(tok, Token_Comma) {
						_ = expect(self, Token_Comma) or_return
						parse_inst_literal(self, &inst, offset, true) or_return
					}
				} else {
					parse_inst_literal(self, &inst, offset, false) or_return
				}

				_ = expect(self, Token_End_Of_Statement) or_return

				parse_inst_literal :: proc(self: ^Assembler, inst: ^Instruction, offset: int, pred: bool) -> (err: AssemblerError) {
					switch lit in parse_literal(self) or_return {
					case Parsed_ConstantRef:
						append(&self.relocations, Relocation{
							kind = .Constant,
							path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = pred,
							name = string(lit),
						})
					case Parsed_LabelRef:
						append(&self.relocations, Relocation{
							kind = .Label,
							path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = pred,
							name = string(lit[1:]),
						})
					case Value:
						inst.imm[1 if pred else 0] = lit
					}
					return
				}
			case .Call:
				inst.op = .Call
				tok := scanner_peek(self) or_return

				if check_token(tok, Token_Slash) {
					_ = expect(self, Token_Slash) or_return
					inst.precondition = parse_precondition(self) or_return

					l0 := expect(self, Token_Label) or_return
					append(&self.relocations, Relocation{
						kind = .Label,
						path = slice.clone(self.current_scope[:], self.allocator),
						offset = offset,
						pred = false,
						name = l0.raw[1:],
					})

					tok := scanner_peek(self) or_return
					if check_token(tok, Token_Comma) {
						_ = expect(self, Token_Comma) or_return

						l1 := expect(self, Token_Label) or_return
						append(&self.relocations, Relocation{
							kind = .Label,
							path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = true,
							name = l1.raw[1:],
						})
					}
				} else {
					l := expect(self, Token_Label) or_return
					append(&self.relocations, Relocation{
						kind = .Label,
						path = slice.clone(self.current_scope[:], self.allocator),
						offset = offset,
						pred = false,
						name = l.raw[1:],
					})
				}

				_ = expect(self, Token_End_Of_Statement) or_return

			case .Jump:
				inst.op = .Jump
				tok := scanner_peek(self) or_return
				if check_token(tok, Token_Slash) {
					_ = expect(self, Token_Slash) or_return
					inst.precondition = parse_precondition(self) or_return

					l0 := expect(self, Token_Label) or_return
					append(&self.relocations, Relocation{
						kind = .Label,
						path = slice.clone(self.current_scope[:], self.allocator),
						offset = offset,
						pred = false,
						name = l0.raw[1:],
					})

					tok := scanner_peek(self) or_return
					if check_token(tok, Token_Comma) {
						_ = expect(self, Token_Comma) or_return

						l1 := expect(self, Token_Label) or_return
						append(&self.relocations, Relocation{
							kind = .Label,
							path = slice.clone(self.current_scope[:], self.allocator),
							offset = offset,
							pred = true,
							name = l1.raw[1:],
						})
					}
				} else {
					l := expect(self, Token_Label) or_return
					append(&self.relocations, Relocation{
						kind = .Label,
						path = slice.clone(self.current_scope[:], self.allocator),
						offset = offset,
						pred = false,
						name = l.raw[1:],
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
			case .Ret:
				inst.op = .EarlyReturn
				parse_basic_instruction(self, &inst) or_return
			case .Spawn:
				inst.op = .Spawn
				parse_basic_instruction(self, &inst) or_return
			case .Const, .End:
				unreachable()
			}
			return
		}
		parse_basic_instruction :: proc(s: ^Scanner, inst: ^Instruction) -> AssemblerError {
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
		parse_precondition :: proc(s: ^Scanner) -> (cond: Precondition, err: AssemblerError) {
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

		Parsed_ConstantRef :: distinct string
		Parsed_LabelRef :: distinct string
		Parsed_Literal :: union {
			Value,
			Parsed_ConstantRef,
			Parsed_LabelRef,
		}
		parse_literal :: proc(self: ^Assembler) -> (
			result: Parsed_Literal,
			err: AssemblerError
		) {
			tok := scanner_next(self) or_return

			#partial switch k in tok.kind {
			case Token_NumberLit:
				result = Value(k)
			case Token_BoolLit:
				result = Value(k)
			case Token_HexLit:
				result = Value(rgba_u32_to_color(k))
			case Token_Identifier:
				lit := parse_constant_literal(self, tok.raw) or_return
				result = Parsed_ConstantRef(lit)
			case Token_Label:
				result = Parsed_LabelRef(tok.raw)
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

rgba_u32_to_color :: proc(c: u32) -> Color {
	r := u8(c >> 24)
	g := u8(c >> 16)
	b := u8(c >> 8)
	a := u8(c >> 0)
	return {r, g, b, a}
}

dump_program :: proc(p: Program) {
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)
	dump_program_sb(&sb, p)
	log.debug(strings.to_string(sb))
}

dump_program_sb :: proc(sb: ^strings.Builder, p: Program) {
	fmt.sbprintln(sb)
	fmt.sbprintln(sb, "// Program Output")
	fmt.sbprintln(sb, "program := Program {")
	fmt.sbprintln(sb, "    blocks = {")
	for block, i in p.blocks {
		fmt.sbprintfln(sb, "        {{ // %v", i)
		for inst in block {
			fmt.sbprint(sb, "            {")
			if inst.precondition != .None {
				fmt.sbprintf(sb, " precondition = .%v, ", inst.precondition)
			}
			fmt.sbprintf(sb, " op = .%v, ", inst.op)
			if inst.imm[0] != nil || inst.imm[1] != nil {
				fmt.sbprint(sb, " imm = { ")
				for val in inst.imm {
					print_vm_value(sb, val)
				}
				fmt.sbprint(sb, "} ")
			}
			fmt.sbprintln(sb, "},")
		}
		fmt.sbprintln(sb, "        },")
	}
	fmt.sbprintln(sb, "    }")
	fmt.sbprintln(sb, "}")

	print_vm_value :: proc(sb: ^strings.Builder, val: Value) {
		switch v in val {
		case nil:
			fmt.sbprint(sb, "nil, ")
		case Color:
			fmt.sbprint(sb, "Color { ")
			for channel in v {
				fmt.sbprint(sb, channel)
				fmt.sbprint(sb, ", ")
			}
			fmt.sbprint(sb, "}, ")
		case f32:
			fmt.sbprintf(sb, "f32(%v), ", v)
		case bool:
			fmt.sbprintf(sb, "%v, ", v)
		case Label:
			fmt.sbprintf(sb, "Label(%v), ", v)
		case Param:
			fmt.sbprintf(sb, "Param.%v, ", v)
		}
	}
}
