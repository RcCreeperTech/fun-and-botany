package engine

import "base:intrinsics"
import la "core:math/linalg"
import "core:math"

Matrix3 :: la.Matrix3x3f32
Vec2 :: [2]f32
Vec3 :: [3]f32

@(private)
IS_FLOAT :: intrinsics.type_is_float
@(private)
ELEM_TYPE :: intrinsics.type_elem_type
@(private)
IS_ARRAY :: intrinsics.type_is_array

exp_decay :: proc {
	exp_decay_float,
	exp_decay_color,
}
// Lerp that respects delta time
// Useful range approx. 1 to 25, from slow to fast
exp_decay_float :: proc(a, b: $T, decay, dt: f32) -> (out: T) where IS_FLOAT(ELEM_TYPE(T)) {
	when IS_ARRAY(T) {
		for i in 0 ..< len(T) {
			out[i] = b[i] + (a[i] - b[i]) * math.exp(-decay * dt)
		}
	} else {
		out = b + (a - b) * math.exp(-decay * dt)
	}
	return
}
exp_decay_color :: proc(a, b: Color, decay, dt: f32) -> (color: Color) {
	fa, fb := to_fcolor(a), to_fcolor(b)
	for i in 0 ..< 4 {
		color[i] = u8(exp_decay_float(fa[i], fb[i], decay, dt) * 255)
	}
	return
}

cmplx_length2 :: proc(z: complex64) -> f32 {
	return real(z) * real(z) + imag(z) * imag(z)
}

cmplx_normalize :: proc(z: complex64) -> complex64 {
	l2 := cmplx_length2(z)
	if l2 <= 0 do return z
	inv_len := 1 / math.sqrt(l2)
	return complex(real(z) * inv_len, imag(z) * inv_len)
}

segment_intersect :: proc(p1, p2, p3, p4: Vec2) -> (pt: Vec2, element_t: f32, hit: bool) {
	v1, v2 := p2 - p1, p4 - p3
	denom := la.cross(v1, v2)
	if math.abs(denom) < 1e-6 do return {}, 0, false

	u := p3 - p1
	t := la.cross(u, v2) / denom
	s := la.cross(u, v1) / denom

	if t >= 0 && t <= 1 && s >= 0 && s <= 1 {
		return p1 + v1 * t, s, true
	}
	return {}, 0, false
}
