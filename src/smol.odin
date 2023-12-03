package smol

import "core:builtin"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
// (* stream *)
// type stream = { mutable chr: char option; mutable line_num: int; chan: in_channel }

// let open_stream file = { chr=None; line_num=1; chan=open_in file }
// let close_stream stm = close_in stm.chan
// let read_char stm = match stm.chr with
//                         None -> let c = input_char stm.chan in
//                                 if c = '\n' then
//                                     let _ = stm.line_num <- stm.line_num + 1 in c
//                                 else c
//                       | Some c -> stm.chr <- None; c
// let unread_char stm c = stm.chr <- Some c

// (* character *)
// let is_digit c = let code = Char.code c in
//                  code >= Char.code('0') && code <= Char.code('9')

// let is_alpha c = let code = Char.code c in
//                  (code >= Char.code('A') && code <= Char.code('Z')) ||
//                  (code >= Char.code('a') && code <= Char.code('z'))


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
	lit: i32,
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
	stream, err := open_stream("./smol-programs/arith.smol")
	gen := new_generator()
	reader: strings.Reader
	strings.reader_init(&reader, stream.in_channel)
	for {
		x, p_err := scan_token(&reader)
		fmt.printf("%v %v\n", x, p_err)
		if p_err == .EOF || p_err != nil {
			break
		}
	}
}

new_generator :: proc() -> Generator {
	m := make(map[string]int)
	fd, err := os.open("./a.out", os.O_WRONLY | os.O_CREATE, 777)
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
	cstring := strings.clone_to_cstring(strings.to_string(builder))
	return Literal{lit = libc.atoi(cstring)}, .None
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
	l := len(scan_iden)
	switch scan_iden {
	case "begin":
		return .Begin, .None
	case "end":
		return .End, .None
	case "read":
		return .Read, .None
	case "write":
		return .Write, .None
	case:
		return Identifier{iden = scan_iden}, .None
	}
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
	data, ok := os.read_entire_file(file_path, context.allocator)
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
