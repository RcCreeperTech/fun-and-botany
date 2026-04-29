package engine

Color :: [4]u8

BG_COLOR :: Color{0x18, 0x18, 0x18, 255}
LIGHTGRAY :: Color{200, 200, 200, 255}
GRAY :: Color{130, 130, 130, 255}
DARKGRAY :: Color{80, 80, 80, 255}
YELLOW :: Color{253, 249, 0, 255}
GOLD :: Color{255, 203, 0, 255}
ORANGE :: Color{255, 161, 0, 255}
PINK :: Color{255, 109, 194, 255}
RED :: Color{230, 41, 55, 255}
MAROON :: Color{190, 33, 55, 255}
GREEN :: Color{0, 228, 48, 255}
LIME :: Color{0, 158, 47, 255}
DARKGREEN :: Color{0, 117, 44, 255}
SKYBLUE :: Color{102, 191, 255, 255}
BLUE :: Color{0, 121, 241, 255}
DARKBLUE :: Color{0, 82, 172, 255}
PURPLE :: Color{200, 122, 255, 255}
VIOLET :: Color{135, 60, 190, 255}
DARKPURPLE :: Color{112, 31, 126, 255}
BEIGE :: Color{211, 176, 131, 255}
BROWN :: Color{127, 106, 79, 255}
DARKBROWN :: Color{76, 63, 47, 255}

WHITE :: Color{255, 255, 255, 255}
BLACK :: Color{0, 0, 0, 255}
BLANK :: Color{0, 0, 0, 0}
MAGENTA :: Color{255, 0, 255, 255}

rand_color :: proc(rand_alpha := false) -> Color {
	R := rand.int63()
	r := u8(R >> 0)
	g := u8(R >> 8)
	b := u8(R >> 16)
	a := u8(R >> 24) if rand_alpha else 255
	return {r, g, b, a}
}

to_color :: proc {
	fcolor_to_color,
}


rgba_u32_to_color :: proc(c: u32) -> Color {
	r := u8(c >> 24)
	g := u8(c >> 16)
	b := u8(c >> 8)
	a := u8(c >> 0)
	return {r, g, b, a}
}

fcolor_to_color :: proc(c: FColor) -> Color {
	c := c
	c *= 255
	return Color{u8(c[0]), u8(c[1]), u8(c[2]), u8(c[3])}
}

FColor :: [4]f32

to_fcolor :: proc {
	color_to_fcolor,
}

color_to_fcolor :: proc(c: Color) -> FColor {
	return FColor{f32(c[0]), f32(c[1]), f32(c[2]), f32(c[3])} / 255
}

rand_fcolor :: proc(rand_alpha := false) -> FColor {
	r := rand.float32()
	g := rand.float32()
	b := rand.float32()
	a := rand.float32() if rand_alpha else 1
	return {r, g, b, a}
}

color_alpha :: proc(color: Color, alpha: f32) -> Color {
	return Color{color.r, color.g, color.b, u8(255 * alpha)}
}

import "core:math/rand"
