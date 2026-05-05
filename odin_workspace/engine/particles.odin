package engine

import "core:math"
import "core:math/rand"
import rg "renderer"

MAX_PARTICLES :: 4096

Particle :: struct {
	position:   [2]f32,
	velocity:   [2]f32,
	color:      Color,
	life:       f32,
	max_life:   f32,
}

Particle_System :: struct {
	particles: [MAX_PARTICLES]Particle,
	count:     int,
}

particle_system_init :: proc(ps: ^Particle_System) {
	ps.count = 0
}

particle_system_emit :: proc(ps: ^Particle_System, pos, vel: [2]f32, color: Color, life: f32) {
	if ps.count >= MAX_PARTICLES do return

	p := &ps.particles[ps.count]
	p.position = pos
	p.velocity = vel
	p.color    = color
	p.life     = life
	p.max_life = life

	ps.count += 1
}

sim_spawn_burst :: proc(self: ^Particle_System, position: Vec2, base_color: Color, amount: int) {
	for _ in 0..<amount {
		if self.count >= MAX_PARTICLES do break

		p := &self.particles[self.count]
		p.position = position

		angle := rand.float32() * math.PI
		speed := rand.float32() * 8.0 + 2.0
		s, c := math.sincos(angle)
		p.velocity = {c, s} * speed

		p.color = base_color
		p.life = rand.float32() * 0.4 + 0.2 // Live for 0.2 to 0.6 seconds
		p.max_life = p.life

		self.count += 1
	}
}

particle_system_update :: proc(ps: ^Particle_System, dt: f32) {
	for i := 0; i < ps.count; {
		p := &ps.particles[i]
		p.life -= dt

		if p.life <= 0.0 {
			ps.particles[i] = ps.particles[ps.count - 1]
			ps.count -= 1
		} else {
			p.position += p.velocity * dt
			p.velocity.y -= SIM_GRAVITY * 0.5 * dt
			p.color.a = u8((p.life / p.max_life) * 255)
			i += 1
		}
	}
}

particle_system_render :: proc(r: ^rg.Renderer_State, self: ^Particle_System) {
	for i in 0..<self.count {
		p := &self.particles[i]
		radius := (p.life / p.max_life) * 0.08
		rg.draw_circle(r, p.position, radius, color = p.color)
	}
}
