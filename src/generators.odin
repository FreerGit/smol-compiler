package smol

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

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


generate_begin :: proc(gen: ^Generator) {
	begin_assem := `
extern printf
extern scanf

section .data
    inf: db '%d', 0
    ouf: db '%d', 10, 0

section .text
    global main

main:
    sub    esp, 1000
`
	os.write_string(gen.out_channel, begin_assem)
}

generate_end :: proc(gen: ^Generator) {
	end_assem := `
    add    esp, 1000
exit:
    mov    eax, 1 ; sys_exit
    mov    ebx, 0
    int    80h
`
	os.write_string(gen.out_channel, end_assem)
}


op2 :: proc(gen: ^Generator, instr: string, reg1: string, reg2: string) {
	assem_instr := strings.concatenate({instr, " ", reg1, ", ", reg2, "\n"})
	defer delete(assem_instr)
	os.write_string(gen.out_channel, assem_instr)
}

op :: proc(gen: ^Generator, instr: string, a: string) {
	assem_instr := strings.concatenate({instr, a, "\n"})
	defer delete(assem_instr)
	os.write_string(gen.out_channel, assem_instr)
}

push :: proc(gen: ^Generator, a: string) {
	op(gen, "    push   ", a)
}

generate_copy :: proc(gen: ^Generator, id: Token, id2: Token) {
	#partial switch i in id {
	case Identifier:
		#partial switch i2 in id2 {
		case Identifier:
			op2(gen, "    mov   ", "eax", var(gen, i2))
			op2(gen, "    mov   ", var(gen, i), "eax")
		case Literal:
			buf: [16]u8
			of_str := strconv.itoa(buf[:], i2.lit)
			op2(gen, "    mov   ", var(gen, i), of_str)
		case:
			panic("Literal or identifier expected")
		}
	case:
		panic("Generate copy called with invalid argument")
	}

}

generate_assign :: proc(gen: ^Generator, id: Token, id2: Token) {
	#partial switch i in id {
	case Identifier:
		alloc_var(gen, i)
		generate_copy(gen, id, id2)

	}
}


generate_add :: proc(gen: ^Generator, d: int, l: Token, r: Token) -> Token {
	#partial switch id1 in l {
	case Identifier:
		v := temp_var(gen, d)
		vi := var(gen, v)
		generate_copy(gen, v, id1)

		#partial switch id2 in r {
		case Identifier:
			op2(gen, "	add   ", vi, var(gen, id2))
			return v
		case Literal:
			buf: [16]u8
			of_str := strconv.itoa(buf[:], id2.lit)
			op2(gen, "	add   ", vi, of_str)
			return v
		}
	}
	panic("generate add called with invalid args")
}

addop :: proc(gen: ^Generator, d: int, l: Token, r: Token) -> Token {
	#partial switch left in l {
	case Literal:
		#partial switch right in r {
		case Literal:
			fmt.println("addop", l, r)
			return Literal{left.lit + right.lit}
		case Identifier:
			return generate_add(gen, d, r, l)
		}
	case Identifier:
		#partial switch right in r {
		case Literal:
			return generate_add(gen, d, l, r)
		}
	}

	panic("Expected literal or identifier for add op")
}

generate_reads :: proc(gen: ^Generator, idens: ^[dynamic]Identifier) {
	for id in idens {
		op2(gen, "    lea", "   eax", var(gen, id))
		push(gen, "eax")
		push(gen, "inf")
		op(gen, "    call   ", "scanf")
		op2(gen, "    add   ", "esp", "8")
	}
}

read :: proc(s: ^Scanner, gen: ^Generator) -> bool {
	if match_token(s, .Read) {
		fmt.println("IN HERE", s)
		if match_token(s, .LeftParen) {
			ids := identifiers(s)
			if len(ids) == 0 {
				panic("Read statement expects comma seperated identifier(s)")
			} else if match_token(s, .RightParen) {
				generate_reads(gen, &ids)
				return true
			} else {
				panic("Right paren expected in read statement")
			}
		} else {
			panic("Left paren expected in read statement")
		}
	} else {
		panic("Read statement expected")
	}
}
