package game

import "core:math"
import "core:math/rand"
import sa "core:container/small_array"
import rl "vendor:raylib"

// For: thrust, ship destruction, hyperspace
Particle :: struct {
	type: Particle_Type,
	position, velocity: Vec2,
	color: rl.Color,
	lifetime: f32,
	max_lifetime: f32,
}

Particle_Type :: enum { 
	Thrust,
	Explosion,
	// Sparkle,
}

Particle_Emitter :: struct {
	type: Particle_Type,
	active: bool,

	position: Vec2,
	rotation: f32,

	particles_per_burst: int,
	// intensity?
	// owner?

	// Timing
	spawn_timer: Timer, // if no timer, then one-time spawn
	spawn_rate: f32, // partcles/sec
	lifetime: f32,
	max_lifetime: f32,
}

MAX_PARTICLES :: 8192
MAX_TRANSIENT_EMITTERS :: 8
Particle_System :: struct {
	particles: sa.Small_Array(MAX_PARTICLES, Particle),
	thrust_emitters: [Ship_Type]Particle_Emitter,
	transient_emitters: sa.Small_Array(MAX_TRANSIENT_EMITTERS, Particle_Emitter),
}

update_particle_system :: proc(gm: ^Game_Memory, dt: f32) {
	update_emitters(gm, dt)
	update_particles(gm.particle_system, dt)
}

update_emitters :: proc(gm: ^Game_Memory, dt: f32) {
	for &pe, ship_type in sa.slice(&gm.particle_system.transient_emitters) {
		if pe.active {
			if pe.spawn_timer.state != .Running {
				start_timer(&pe.spawn_timer)
				#partial switch pe.type {
				case .Explosion:
					spawn_explosion_particle(gm.particle_system, pe)
				}
			}

			process_timer(&pe.spawn_timer, dt)

			if is_timer_done(pe.spawn_timer) {
				#partial switch pe.type {
				case .Explosion:
					spawn_explosion_particle(gm.particle_system, pe)
				}
			}
		} else {
			reset_timer(&pe.spawn_timer)
		}
	}

	for &pe, ship_type in gm.particle_system.thrust_emitters {
		if ship, ok := get_ship_by_ship_type(gm^, ship_type); ok {
			update_thrust_emitter_for_ship(&pe, ship)

			if pe.active {
				if pe.spawn_timer.state != .Running {
					start_timer(&pe.spawn_timer)
					spawn_thrust_particle(gm.particle_system, pe)
				}

				process_timer(&pe.spawn_timer, dt)

				if is_timer_done(pe.spawn_timer) {
					spawn_thrust_particle(gm.particle_system, pe)
				}
			} else {
				reset_timer(&pe.spawn_timer)
			}
		}
	}
}

update_particles :: proc(ps: ^Particle_System, dt: f32) {
	// swap and pop removal
	i := 0
	particles := sa.slice(&ps.particles)

	for i < len(particles) {
		p := &particles[i]
		p.lifetime += dt

		if p.lifetime >= p.max_lifetime {
			sa.unordered_remove(&ps.particles, i)
			particles = sa.slice(&ps.particles)
			continue
		} 

		// linear fade
		life_ratio := p.lifetime / p.max_lifetime
		alpha := (1.0 - life_ratio)
		// CSDR fade curve (tween)
		// CSDR flicker
		p.color.a = u8(255.0 * alpha)

		switch p.type {
		case .Thrust:
			// update_thrust_particle(&p, dt)
			p.velocity *= 0.98
		case .Explosion:
			p.velocity *= 0.99
		}

		p.position += p.velocity * dt
		i += 1
	}
}

spawn_particle :: proc(ps: ^Particle_System, p: Particle) {
	if !can_spawn_particle(ps^) do return

	particle_count := sa.len(ps.particles)
	if particle_count >= MAX_PARTICLES do return
	sa.push(&ps.particles, p)
}

can_spawn_particle :: proc(ps: Particle_System) -> bool {
	particle_count := sa.len(ps.particles)
	if particle_count >= MAX_PARTICLES {
		return false
	}
	return true
}

THRUST_PARTICLE_DEFAULT_SPEED :: 150
THRUST_PARTICLE_LIFETIME :: 1.25
spawn_thrust_particle :: proc(ps: ^Particle_System, pe: Particle_Emitter) {
	p: Particle
	p.type = .Thrust

	exhaust_speed := THRUST_PARTICLE_DEFAULT_SPEED - rand.float32() * 30
	p.velocity = Vec2{exhaust_speed * math.cos(pe.rotation),
					  exhaust_speed * math.sin(pe.rotation)}
	// TODO: jitter

	// spread is perpendicular to exhaust
	spread := (rand.float32() - 0.5) * 8
	offset := Vec2{0, spread}
	rotated_offset := rotate_vec2(offset, pe.rotation)
	p.position = pe.position + rotated_offset

	p.lifetime = 0
	p.max_lifetime = THRUST_PARTICLE_LIFETIME + rand.float32() * 0.08

	p.color = rl.Color{255, 
					   u8(150 + rand.float32() * 80), 
					   u8(30 + rand.float32() * 50), 
					   255}

	spawn_particle(ps, p)
}

spawn_buncha_particles :: proc(ps: ^Particle_System, pe: ^Particle_Emitter) {
	if !can_spawn_particle(ps^) do return

	for i := 0; i < pe.particles_per_burst && sa.len(ps.particles) < MAX_PARTICLES; i += 1 {
		switch pe.type {
		case .Thrust:
			spawn_thrust_particle(ps, pe^)
		case .Explosion:
			spawn_explosion_particle(ps, pe^)
		}
	}

}

// at ship entry and later exit positions
// create_hyperspace_emitter :: proc(ps: ^Particle_System, position: Position) {}

// spawn at ship tail, depending on type/dims
THRUST_EMITTER_SPAWN_INTERVAL :: 0.1
THRUST_EMITTER_SPAWN_RATE :: 25
THRUST_EMITTER_PARTICLES_PER_BURST :: 10
THRUST_EMITTER_MAX_LIFETIME :: -1
make_thrust_emitter :: proc() -> Particle_Emitter {
	pe := Particle_Emitter{
		active = false,
		spawn_rate = THRUST_EMITTER_SPAWN_RATE,
		spawn_timer = create_timer(THRUST_EMITTER_SPAWN_INTERVAL),
		max_lifetime = THRUST_EMITTER_MAX_LIFETIME , // toggled on and off by ship thrust input
		particles_per_burst = THRUST_EMITTER_PARTICLES_PER_BURST,
	}
	return pe
}

EXPLOSION_PARTICLE_DEFAULT_SPEED :: 100
EXPLOSION_PARTICLE_LIFETIME :: 4
spawn_explosion_particle :: proc(ps: ^Particle_System, pe: Particle_Emitter) {
	p: Particle
	p.type = .Explosion

	speed := EXPLOSION_PARTICLE_DEFAULT_SPEED - rand.float32() * 75
	angular_velocity_spread := rand.float32() * 2 * math.PI
	p.velocity = Vec2{speed * math.cos(angular_velocity_spread),
					  speed * math.sin(angular_velocity_spread)}

	// circular spread
	radial_spread := rand.float32() * 10
	angular_spread := rand.float32() * 2 * math.PI

	offset := Vec2{radial_spread * math.cos(angular_spread),
				   radial_spread * math.sin(angular_spread)}
	p.position = pe.position + offset

	p.lifetime = 0
	p.max_lifetime = EXPLOSION_PARTICLE_LIFETIME + rand.float32() * 1

	p.color = rl.Color{u8(200 + rand.float32() * 55), // 200-255
					   u8(100 + rand.float32() * 100), // 100-200
					   u8(rand.float32() * 80), // 0-80
					   255}
	// more dramatic?
	// p.color = rl.Color{u8(180 + rand.float32() * 75),  // Red: 180-255
	//                   u8(80 + rand.float32() * 120),  // Green: 80-200
	//                   u8(20 + rand.float32() * 60),   // Blue: 20-80
	//                   255}
	spawn_particle(ps, p)
}

can_spawn_transient_emitter :: proc(ps: Particle_System) -> bool {
	if sa.len(ps.transient_emitters) >= MAX_TRANSIENT_EMITTERS {
		return false
	}
	return true
}

spawn_transient_emitter :: proc(ps: ^Particle_System, pe: Particle_Emitter) {
	if !can_spawn_transient_emitter(ps^) do return
	sa.push(&ps.transient_emitters, pe)
}

EXPLOSION_EMITTER_PARTICLES_PER_BURST :: 25
EXPLOSION_EMITTER_MAX_LIFETIME :: 0.01
make_explosion_emitter :: proc(position: Position) -> Particle_Emitter {
	pe := Particle_Emitter{
		type = .Explosion,
		position = position,
		// vel, rot,
		active = true,
		// spawn_timer, spawn_rate, lifetime
		max_lifetime = EXPLOSION_EMITTER_MAX_LIFETIME,
		particles_per_burst = EXPLOSION_EMITTER_PARTICLES_PER_BURST 
	}
	return pe
}

spawn_explosion_emitter :: proc(ps: ^Particle_System, position: Position) {
	pe := make_explosion_emitter(position)
	spawn_transient_emitter(ps, pe)
}

update_thrust_emitter_for_ship :: proc(pe: ^Particle_Emitter, ship: Ship) {
	if ship.is_thrusting  {
		pe.active = true
		pe.rotation = (ship.rotation + math.PI)
		tail_pos := get_ship_tail_position(ship)
		pe.position = tail_pos
	} else {
		pe.active = false
	}
}
