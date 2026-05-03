package compiler

import "base:intrinsics"

contains :: proc (array: $T/[]$E, f: proc(E) -> bool) -> bool
	where intrinsics.type_is_comparable(E)
{
	for x in array do if f(x) do return true

	return false
}
