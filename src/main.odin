package smol

import "core:builtin"
import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:testing"

Stream :: struct {
	line_num:   int,
	in_channel: string,
}

Generator :: struct {
	vars:        map[string]int,
	out_channel: os.Handle,
}


IOError :: enum {
	None,
	CouldNotReadFile,
}

Identifier :: struct {
	iden: string,
}
Literal :: struct {
	lit: int,
}

TokenSimple :: enum {
	Begin,
	End,
	Read,
	Write,
	Literal,
	Assign,
	LeftParen,
	RightParen,
	AddOp,
	SubOp,
	Comma,
	SemiColon,
	None,
}

Token :: union {
	TokenSimple,
	Identifier,
	Literal,
}

ParseError :: enum {
	None,
	EOF,
	TokenParserError,
	IdenScanError,
	TokenScanError,
	LitScanError,
}


main :: proc() {
	when ODIN_DEBUG {
		check_for_leaks()
	}

	path_to_code, ok := slice.get(os.args, 1)
	if !ok {
		fmt.eprintln(
			"Please provide a file to compile, visit /smol-programs for examples. \nRun as:\n	odin run <path_to_smol.odin> -file -- <path_to_your_smol_file>",
		)
	} else {
		compile(path_to_code)
	}
}

compile :: proc(file_path: string) {
	g := new_generator(file_path)
	stream, _ := open_stream(file_path)
	reader: strings.Reader
	defer delete(g.vars)
	defer delete(stream.in_channel)

	strings.reader_init(&reader, stream.in_channel)
	parse(reader, &g)
	output_file, _ := os.absolute_path_from_handle(g.out_channel)
	defer delete(output_file)

	nasm_argv := strings.clone_to_cstring(
		strings.concatenate({"nasm -f elf ", output_file}),
	)

	libc.system(nasm_argv)

	file := chop_extension(file_path)
	gcc_argv := strings.clone_to_cstring(
		strings.concatenate({"gcc -m32 -o ", file, " ", file, ".o"}),
	)
	defer delete(nasm_argv)

	libc.system(gcc_argv)
}

chop_extension :: proc(path: string) -> string {
	no_folders, _ := strings.split(path, "/")
	file_name := slice.last(no_folders)
	no_suffix, _ := strings.split(file_name, ".")
	defer delete(no_folders)
	defer delete(no_suffix)
	return slice.first(no_suffix)
}

parse :: proc(reader: strings.Reader, gen: ^Generator) {
	s := new_scanner(reader)
	if match_token(&s, .Begin) {
		generate_begin(gen)
		statements(&s, gen)
		fmt.println("T", s)
		if match_token(&s, .End) {
			generate_end(gen)
		} else {
			panic("Program should end with `end` keyword")
		}
	} else {
		panic("Program should begin with `begin` keyword")
	}
}

statement :: proc(s: ^Scanner, gen: ^Generator) -> bool {
	t := next_token(s)
	stmt := false
	#partial switch v in t {
	case TokenSimple:
		#partial switch v {
		case .Read:
			stmt = read(s, gen)
		case .Write:
		// write(reader, gen)
		}
	case Identifier:
		stmt = assignment(s, gen)
		fmt.println("here", v, stmt)

	case:
		fmt.println("HERExx")
		stmt = false
	}
	if stmt {
		if match_token(s, .SemiColon) {
			fmt.println("HERE", s)
			return true
		} else {
			panic("Statements must end with a semicolon")
		}
	} else {
		return false
	}
}

statements :: proc(s: ^Scanner, gen: ^Generator) {
	if statement(s, gen) {
		statements(s, gen)
	}
}

primary :: proc(
	s: ^Scanner,
	gen: ^Generator,
	d: int,
) -> (
	t: Maybe(Token),
	err: ParseError,
) {
	n := next_token(s)
	if n == .LeftParen {
		match_token(s, .LeftParen)
		e := expression(s, gen, d + 1) or_return
		if match_token(s, .RightParen) {
			return e, .None
		} else {
			panic("Right paren expected in expression")
		}
	} else {
		#partial switch i in n {
		case Identifier:
			match_token(s, Identifier{i.iden})
			return Identifier{i.iden}, .None
		case Literal:
			match_token(s, Literal{i.lit})
			return Literal{i.lit}, .None
		case:
			return nil, .None
		}
	}
}

expression :: proc(
	s: ^Scanner,
	gen: ^Generator,
	d: int,
) -> (
	t: Token,
	err: ParseError,
) {
	lp := primary(s, gen, d) or_return
	l, ok := lp.?
	fmt.println(lp, l, ok)
	if ok {
		next := next_token(s)
		fmt.println(next)
		if next == .AddOp {
			match_token(s, .AddOp)
			e := expression(s, gen, (d + 1)) or_return
			return addop(gen, d, l, e), .None
		}
		return l, .None
	}
	panic("Literal or Identifier expected")
}

assignment :: proc(s: ^Scanner, gen: ^Generator) -> bool {
	id, err := match_next(s)
	fmt.println(id)
	#partial switch i in id {
	case Identifier:
		if match_token(s, .Assign) {
			new_var := is_alloc_var(gen, i.iden)
			id2, _ := expression(s, gen, (1 + int(new_var)))
			fmt.println("after exp", id2)
			#partial switch i2 in id2 {
			case Literal:
				generate_assign(gen, id, id2)
				return true
			case Identifier:
				generate_assign(gen, id, id2)
				return true
			case:
				fmt.println("assignment: ", i2)
				panic("Identifier or Literal expected")
			}
		}
	}
	panic("Identifier expected")
}

identifiers :: proc(s: ^Scanner) -> [dynamic]Identifier {
	idens: [dynamic]Identifier
	for {
		token := next_token(s)
		#partial switch t in token {
		case Identifier:
			_, err := match_next(s)
			n := next_token(s)
			if n == .Comma {
				match_token(s, .Comma)
				append_elem(&idens, t)
			} else {
				append_elem(&idens, t)
			}
		case:
			return idens
		}
	}
}

read_next_char :: proc(s: ^Scanner) -> (rune, ParseError) {
	rr, size, err := strings.reader_read_rune(&s.stm)
	if err != nil {
		return 0, .EOF
	}
	return rr, .None
}

open_stream :: proc(file_path: string) -> (Stream, IOError) {
	data, ok := os.read_entire_file(file_path)
	if !ok {
		return {}, .CouldNotReadFile
	}

	return Stream{line_num = 0, in_channel = string(data)}, .None
}

is_digit :: proc(char: rune) -> bool {
	return char >= '0' && char <= '9'
}


is_alpha :: proc(char: rune) -> bool {
	return (char >= 'A' && char <= 'z') || (char >= 'a' && char <= 'z')
}

@(test)
test_is_digit :: proc(t: ^testing.T) {
	for c in '0' ..= '9' {
		assert(is_digit(c))
		assert(!is_alpha(c))
	}
}

@(test)
test_is_alpha :: proc(t: ^testing.T) {
	for c in 'A' ..= 'Z' {
		assert(is_alpha(c))
	}
	for c in 'a' ..= 'z' {
		assert(is_alpha(c))
	}
}
