package smol

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

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
    sub   esp, 1000
`
	os.write_string(gen.out_channel, begin_assem)
}

generate_end :: proc(gen: ^Generator) {
	end_assem := `
    add   esp, 1000
exit:
    mov  eax, 1 ; sys_exit
    mov  ebx, 0
    int  80h
`
	os.write_string(gen.out_channel, end_assem)
}


op2 :: proc(gen: ^Generator, instr: string, reg1: string, reg2: string) {
	assem_instr := strings.concatenate({instr, " ", reg1, ", ", reg2})
	defer delete(assem_instr)
	fmt.println("hej")

	os.write_string(gen.out_channel, assem_instr)
}

generate_copy :: proc(gen: ^Generator, id: Identifier, id2: Token) {
	#partial switch v in id2 {
	case Identifier:
		op2(gen, "    mov", "eax", var(gen, v))
		op2(gen, "    mov", var(gen, id), "eax")
	case Literal:
		buf: [16]u8
		of_str := strconv.itoa(buf[:], v.lit)
		op2(gen, "    mov", var(gen, id), of_str)
	case:
		panic("Literal or identifier expected")
	}
}

generate_assign :: proc(gen: ^Generator, id: Identifier, id2: Token) {
	alloc_var(gen, id)
	generate_copy(gen, id, id2)
}


generate_add :: proc(gen: ^Generator, d: int, l: Token, r: Token) -> Token {
	#partial switch id1 in l {
	case Identifier:
		v := temp_var(gen, d)
		vi := var(gen, v)
		generate_copy(gen, v, id1)

		#partial switch id2 in r {
		case Identifier:
			op2(gen, "add", vi, var(gen, id2))
			return v
		case Literal:
			buf: [16]u8
			of_str := strconv.itoa(buf[:], id2.lit)
			op2(gen, "add", vi, of_str)
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
