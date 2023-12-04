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
	parse(&reader, &g)
	output_file, _ := os.absolute_path_from_handle(g.out_channel)
	defer delete(output_file)

	nasm_argv := strings.clone_to_cstring(
		strings.concatenate({"-f", "elf64", output_file}),
	)
	os._unix_execvp("nasm", &nasm_argv)

	file := chop_extension(file_path)
	o_file := strings.concatenate({file, ".o"})
	gcc_argv := strings.clone_to_cstring(
		strings.concatenate({"-m32", "-o", file, o_file}),
	)
	defer delete(nasm_argv)
	os._unix_execvp("gcc", &gcc_argv)
	delete(o_file)
}

chop_extension :: proc(path: string) -> string {
	no_folders, _ := strings.split(path, "/")
	file_name := slice.last(no_folders)
	no_suffix, _ := strings.split(file_name, ".")
	defer delete(no_folders)
	defer delete(no_suffix)
	return slice.first(no_suffix)
}

parse :: proc(reader: ^strings.Reader, gen: ^Generator) {
	maybe_begin, b_err := scan_token(reader)
	if maybe_begin == .Begin {
		generate_begin(gen)
		statements(reader, gen)
		maybe_end, b_err := scan_token(reader)
		if maybe_end == .End {
			generate_end(gen)
		} else {
			panic("Program should end with `end` keyword")
		}
	} else {
		panic("Program should begin with `begin` keyword")
	}
}

statement :: proc(reader: ^strings.Reader, gen: ^Generator) -> bool {
	token, err := scan_token(reader)
	#partial switch v in token {
	case TokenSimple:
		#partial switch v {
		case .Read:
		// read(reader, gen)
		case .Write:
		// write(reader, gen)
		}
	case Identifier:
		assignment(v, reader, gen)
	case:
		return false
	}
	maybe_semicolon, _ := scan_token(reader)
	fmt.println(token, maybe_semicolon)
	if maybe_semicolon == .SemiColon {
		return false
	} else {
		panic("Statements must end with a semicolon")
	}
}

statements :: proc(reader: ^strings.Reader, gen: ^Generator) {
	if statement(reader, gen) {
		statements(reader, gen)
	}
}


expression :: proc(
	reader: ^strings.Reader,
	gen: ^Generator,
	d: int,
) -> (
	t: Token,
	err: ParseError,
) {
	primary: Token
	fmt.println("hej")
	next_token := scan_token(reader) or_return
	#partial switch t in next_token {
	case Identifier:
		fmt.println("aaxxy")
		primary = t
	case Literal:
		fmt.println("xxy")
		primary = scan_token(reader) or_return
	}
	fmt.println("1", next_token)
	// right_token := scan_token(reader) or_return
	fmt.println("2", primary)


	#partial switch t in primary {
	case TokenSimple:
		if t == .LeftParen {
			primary = expression(reader, gen, d + 1) or_return
			next_token := scan_token(reader) or_return
			if next_token != .RightParen {
				panic("Right paren expected")
			}
		} else if t == .AddOp {
			r := scan_token(reader) or_return
			fmt.println("xx")
			fmt.println(next_token, r, primary)
			return addop(gen, d + 1, next_token, r), .None
		}
	}
	fmt.println(primary, next_token)
	panic("idk")
}

assignment :: proc(id: Identifier, reader: ^strings.Reader, gen: ^Generator) {
	next_token, err := scan_token(reader)
	if next_token == .Assign {
		new_var := is_alloc_var(gen, id)
		fmt.println("heddj")

		id2, _ := expression(reader, gen, (1 + int(new_var)))
		#partial switch v in id2 {
		case Literal:
			generate_assign(gen, id, id2)
		case Identifier:
		case:
			panic("Literal or identifier expected")
		}
	} else {
		panic("Assignment symbol expected")
	}
}

new_generator :: proc(file: string) -> Generator {
	m := make(map[string]int)
	path := strings.concatenate({"./", chop_extension(file), ".s"})
	defer delete(path)
	fd, err := os.open(path, os.O_WRONLY | os.O_CREATE, 777)
	if err != 0 {
		fmt.println(err)
	}
	return Generator{m, fd}
}

close_generator :: proc(gen: ^Generator) {
	delete(gen.vars)
	os.close(gen.out_channel)
}

read_next_char :: proc(reader: ^strings.Reader) -> (rune, ParseError) {
	rr, size, err := strings.reader_read_rune(reader)
	if err != nil {
		return 0, .EOF
	}
	return rr, .None
}

scan_token :: proc(reader: ^strings.Reader) -> (Token, ParseError) {
	skip_blanks(reader)
	rr, err := read_next_char(reader)
	if err != nil {
		if err == .EOF {
			fmt.println(err)
			return .None, .EOF
		}
		return .None, .TokenParserError
	}
	if is_alpha(rr) {
		return scan_iden(reader)
	} else if is_digit(rr) {
		return scan_lit(reader)
	}
	switch rr {
	case '+':
		return .AddOp, .None
	case '-':
		return .SubOp, .None
	case ',':
		return .Comma, .None
	case ';':
		return .SemiColon, .None
	case '(':
		return .LeftParen, .None
	case ')':
		return .RightParen, .None
	case ':':
		rr2, _, err2 := strings.reader_read_rune(reader)
		if rr2 == '=' {
			return .Assign, .None
		}

	}
	return .None, .TokenScanError

}

scan_lit :: proc(reader: ^strings.Reader) -> (Token, ParseError) {
	strings.reader_unread_rune(reader)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for {
		rr, size, err := strings.reader_read_rune(reader)
		if err != nil {
			return .None, .LitScanError
		}
		if (is_digit(rr)) {
			strings.write_rune(&builder, rr)
		} else {
			strings.reader_unread_rune(reader)
			break
		}
	}

	return Literal{strconv.atoi(strings.to_string(builder))}, .None
}

scan_iden :: proc(reader: ^strings.Reader) -> (Token, ParseError) {
	strings.reader_unread_rune(reader)
	builder := strings.builder_make()
	for {
		rr, size, err := strings.reader_read_rune(reader)
		if err != nil && err != .EOF {
			return .None, .IdenScanError
		}
		if (is_alpha(rr) || is_digit(rr) || rr == '_') {
			strings.write_rune(&builder, rr)
		} else {
			break
		}
	}

	scan_iden := strings.to_string(builder)
	switch scan_iden {
	case "begin":
		defer delete(scan_iden)
		return .Begin, .None
	case "end":
		defer delete(scan_iden)
		return .End, .None
	case "read":
		defer delete(scan_iden)
		return .Read, .None
	case "write":
		defer delete(scan_iden)
		return .Write, .None
	case:
	}
	return Identifier{iden = scan_iden}, .None
}

skip_blanks :: proc(reader: ^strings.Reader) -> ^strings.Reader {
	for {
		ru, size, err := strings.reader_read_rune(reader)
		if err != .None {
			break
		}
		if ru == ' ' || ru == '\t' || ru == '\r' || ru == '\n' {
			continue
		} else {
			break
		}
	}
	strings.reader_unread_rune(reader)
	return reader
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
