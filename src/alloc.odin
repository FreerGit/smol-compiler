package smol

import "core:fmt"
import "core:strconv"
import "core:strings"

bottom_var :: proc(gen: ^Generator) -> int {
	acc := 0
	for _, v in gen.vars {
		if v >= acc {
			acc += v + 4
		}
	}
	return acc
}

temp_var :: proc(gen: ^Generator, i: int) -> Identifier {
	using strings
	buf: [8]u8
	return {concatenate({"__temp ", strconv.itoa(buf[:], empty_var(gen, i))})}
}

var_addr :: proc(id: Identifier, gen: ^Generator) -> string {

	if len(id.iden) > 6 && id.iden[0:6] == "__temp" {
		fmt.println("slice", id.iden[6:])
		sub := id.iden[6:][:len(id.iden) - 6]
		return strings.concatenate({"[esp+", sub, "]"})
	} else {
		var, ok := gen.vars[id.iden]
		if !ok {
			panic(
				strings.concatenate({"Identifier ", id.iden, " not defined"}),
			)
		}
		buf: [64]byte
		fmt.println("var", var)
		return strings.concatenate({"[esp+", strconv.itoa(buf[:], var), "]"})
	}
}


var :: proc(gen: ^Generator, id: Identifier) -> string {
	return strings.concatenate({"dword ", var_addr(id, gen)})
}

empty_var :: proc(gen: ^Generator, i: int) -> int {
	return bottom_var(gen) + (4 * (i - 1))
}

is_alloc_var :: proc(gen: ^Generator, id: Identifier) -> bool {
	_, ok := gen.vars[id.iden]
	return ok
}

alloc_var :: proc(gen: ^Generator, id: Identifier) -> string {
	if is_alloc_var(gen, id) {
		return var(gen, id)
	} else {
		gen.vars[id.iden] = empty_var(gen, 1)
		return var(gen, id)
	}
}
