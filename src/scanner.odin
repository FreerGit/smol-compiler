package smol

import "core:fmt"
import "core:strconv"
import "core:strings"

Scanner :: struct {
	last_token: Maybe(Token),
	stm:        strings.Reader,
}

new_scanner :: proc(reader: strings.Reader) -> Scanner {
	return {nil, reader}
}

scan :: proc(s: ^Scanner) -> (Token, ParseError) {
	rr, _ := read_next_char(s)
	fmt.println("SCAN", rr)

	if is_alpha(rr) {
		return scan_iden(&s.stm)
	} else if is_digit(rr) {
		return scan_lit(&s.stm)
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
		rr2, _, err2 := strings.reader_read_rune(&s.stm)
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
			strings.reader_unread_rune(reader)
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


skip_blanks :: proc(s: ^Scanner) -> ^Scanner {
	for {
		ru, err := read_next_char(s)
		if ru == ' ' || ru == '\t' || ru == '\r' || ru == '\n' {
			continue
		} else {
			break
		}
	}
	strings.reader_unread_rune(&s.stm)
	return s
}

match_next :: proc(s: ^Scanner) -> (Token, ParseError) {
	t, ok := s.last_token.?
	if ok {
		s.last_token = nil
		return t, .None
	} else {
		skip_blanks(s)
		return scan(s)
	}
}

match_token :: proc(s: ^Scanner, t: Token) -> bool {
	next, _ := match_next(s)
	return next == t
}

next_token :: proc(s: ^Scanner) -> Token {
	t, ok := s.last_token.?
	if ok {
		return t
	} else {
		skip_blanks(s)
		t, _ = scan(s)
		s.last_token = t
		return t
	}
}
