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
	data1: f32, // thrust: flicker phase, explosion: spread speed, hyperspace: sparkle phase
	data2: f32, // thrust: fade curve, explosion: fragment type, hyperspace: warp intensity
}

Particle_Type :: enum { 
	Vector,
	Explosion,
	Sparkle,
}

Particle_Emitter_Type :: enum {
	Thrust,
	Ship_Destruction,
	Hyperspace,
}

Continuous_Emitter_Data :: struct {
	spawn_rate: f32, // particles/sec
	spawn_accumulator: f32, // accumulated fractional particles
}

Burst_Emitter_Data :: struct {
	spawn_timer: Timer,
	particles_per_burst: int,
	burst_on_first_frame: bool,
}

Emitter_Data :: union {
	Continuous_Emitter_Data,
	Burst_Emitter_Data,
}

Particle_Emitter :: struct {
	type: Particle_Emitter_Type,
	active: bool,

	position: Vec2,
	rotation: f32,

	data: Emitter_Data,
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

process_emitter :: proc(ps: ^Particle_System, pe: ^Particle_Emitter, dt: f32) {
	if !pe.active do return

	pe.lifetime += dt

	switch &data in &pe.data {
	case Continuous_Emitter_Data:
		// Continuous spawning mode (accumulation-based)
		data.spawn_accumulator += data.spawn_rate * dt
		particles_to_spawn := int(data.spawn_accumulator)
		data.spawn_accumulator -= f32(particles_to_spawn)

		for i := 0; i < particles_to_spawn && can_spawn_particle(ps^); i += 1 {
			#partial switch pe.type {
			case .Hyperspace:
				spawn_hyperspace_particle(ps, pe^)
			case .Thrust:
				spawn_thrust_particle(ps, pe^)
			}
		}

	case Burst_Emitter_Data:
		// Burst spawning mode (timer-based)
		if !is_timer_running(data.spawn_timer) {
			start_timer(&data.spawn_timer)
			if data.burst_on_first_frame {
				spawn_buncha_particles(ps, pe)
			}
		}

		process_timer(&data.spawn_timer, dt)
		if is_timer_done(data.spawn_timer) {
			spawn_buncha_particles(ps, pe)
			restart_timer(&data.spawn_timer)
		}
	}
}

update_emitters :: proc(gm: ^Game_Memory, dt: f32) {
	i := 0
	transient_emitters := sa.slice(&gm.particle_system.transient_emitters)
	for i < len(transient_emitters) {
		pe := &transient_emitters[i]

		if !pe.active do continue

		process_emitter(gm.particle_system, pe, dt)

		if pe.lifetime >= pe.max_lifetime {
			// TODO: spawn last burst of particles
			sa.unordered_remove(&gm.particle_system.transient_emitters, i)
			transient_emitters = sa.slice(&gm.particle_system.transient_emitters)
			continue
		}
		i += 1
	}

	for &pe, ship_type in gm.particle_system.thrust_emitters {
		if ship, ok := get_ship_by_ship_type(gm^, ship_type); ok {
			update_thrust_emitter_for_ship(&pe, ship)
			process_emitter(gm.particle_system, &pe, dt)
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

		update_vector_particle :: proc(p: ^Particle, dt: f32) {
			p.position += p.velocity * dt
			p.velocity *= 0.98

			p.data1 += dt * 12
			flicker := 0.8 + 0.2 * math.sin(p.data1)

			// apply fade out curve
			life_ratio := p.lifetime / p.max_lifetime
			fade_curve := p.data2
			alpha := (1.0 - math.pow(life_ratio, fade_curve)) * flicker

			p.color.a = u8(255.0 * alpha)
		}

		update_explosion_particle :: proc(p: ^Particle, dt: f32) {
			p.position += p.velocity * dt
			p.velocity *= 0.99

			// linear fade
			life_ratio := p.lifetime / p.max_lifetime
			alpha := (1.0 - life_ratio)
			p.color.a = u8(255.0 * alpha)
		}

		update_sparkle_particle :: proc(p: ^Particle, dt: f32) {
			p.position += p.velocity * dt
			p.velocity *= 0.97

			// sparkle effect
			p.data1 += dt * 15.0
			sparkle := 0.6 + 0.4 * math.sin(p.data1)

			// Pulsing size effect
			// TODO: particles with size?
			// p.data2 += dt * 8.0
			// pulse := 0.8 + 0.2 * math.sin(p.data2)

			// linear fade
			life_ratio := p.lifetime / p.max_lifetime
			fade_curve: f32 = 1.2 // slight curve
			alpha := (1.0 - math.pow(life_ratio, fade_curve)) * sparkle
			p.color.a = u8(255.0 * alpha)

		}

		switch p.type {
		case .Vector:
			// linear fade
			update_vector_particle(p, dt)
		case .Explosion:
			update_explosion_particle(p, dt)
		case .Sparkle:
			update_sparkle_particle(p, dt)
		}

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
	p.type = .Vector

	exhaust_speed := THRUST_PARTICLE_DEFAULT_SPEED - rand.float32() * 30
	exhaust_vel := rotate_vec2(Vec2{exhaust_speed, rand.float32_range(-10, 10)}, pe.rotation)
	p.velocity = exhaust_vel

	// lateral spread is perpendicular to exhaust
	lateral_spread := (rand.float32() - 0.5) * 8
	offset := Vec2{0, lateral_spread}
	rotated_offset := rotate_vec2(offset, pe.rotation)
	p.position = pe.position + rotated_offset

	p.lifetime = 0
	p.max_lifetime = THRUST_PARTICLE_LIFETIME + rand.float32() * 0.08

	p.data1 = rand.float32() * math.TAU // flicker phase
	p.data2 = 1.0 + rand.float32() * 0.5 // fade curve variation

	p.color = rl.Color{255, 
					   u8(150 + rand.float32() * 80), 
					   u8(30 + rand.float32() * 50), 
					   255}

	spawn_particle(ps, p)
}

spawn_buncha_particles :: proc(ps: ^Particle_System, pe: ^Particle_Emitter) {
	if !can_spawn_particle(ps^) do return

	burst_data, ok := pe.data.(Burst_Emitter_Data)
	if !ok do return // Only burst emitters can spawn bunches

	for i := 0; i < burst_data.particles_per_burst && sa.len(ps.particles) < MAX_PARTICLES; i += 1 {
		switch pe.type {
		case .Thrust:
			spawn_thrust_particle(ps, pe^)
		case .Ship_Destruction:
			spawn_explosion_particle(ps, pe^)
		case .Hyperspace:
			spawn_hyperspace_particle(ps, pe^)
		}
	}
}

// at ship entry and later exit positions
// create_hyperspace_emitter :: proc(ps: ^Particle_System, position: Position) {}

// spawn at ship tail, depending on type/dims
THRUST_EMITTER_SPAWN_RATE :: 25
THRUST_EMITTER_MAX_LIFETIME :: -1
make_thrust_emitter :: proc() -> Particle_Emitter {
	continuous_data := Continuous_Emitter_Data{
		spawn_rate = THRUST_EMITTER_SPAWN_RATE,
		spawn_accumulator = 0,
	}

	pe := Particle_Emitter{
		type = .Thrust,
		active = false,
		data = continuous_data,
		max_lifetime = THRUST_EMITTER_MAX_LIFETIME, // toggled on and off by ship thrust input
	}
	return pe
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

EXPLOSION_EMITTER_PARTICLES_PER_BURST :: 25
EXPLOSION_EMITTER_MAX_LIFETIME :: 0.01
EXPLOSION_EMITTER_BURST_INTERVAL :: 0.005
make_ship_destruction_emitter :: proc(position: Position) -> Particle_Emitter {
	burst_data := Burst_Emitter_Data{
		spawn_timer = create_timer(EXPLOSION_EMITTER_BURST_INTERVAL),
		particles_per_burst = EXPLOSION_EMITTER_PARTICLES_PER_BURST,
		burst_on_first_frame = true,
	}

	pe := Particle_Emitter{
		type = .Ship_Destruction,
		position = position,
		active = true,
		data = burst_data,
		max_lifetime = EXPLOSION_EMITTER_MAX_LIFETIME,
	}
	return pe
}

spawn_ship_destruction_emitter :: proc(ps: ^Particle_System, position: Position) {
	pe := make_ship_destruction_emitter(position)
	spawn_transient_emitter(ps, pe)
}


// HYPERSPACE

HYPERSPACE_PARTICLE_DEFAULT_SPEED :: 75
HYPERSPACE_PARTICLE_LIFETIME :: 0.8
spawn_hyperspace_particle :: proc(ps: ^Particle_System, pe: Particle_Emitter) {
	p: Particle
	p.type = .Sparkle

	speed := HYPERSPACE_PARTICLE_DEFAULT_SPEED + rand.float32_range(-25, 50)
	angular_velocity_spread := rand.float32() * 2 * math.PI
	p.velocity = Vec2{speed * math.cos(angular_velocity_spread),
					  speed * math.sin(angular_velocity_spread)}

	// circular spread
	radial_spread := rand.float32() * 15
	angular_spread := rand.float32() * 2 * math.PI

	offset := Vec2{radial_spread * math.cos(angular_spread),
				   radial_spread * math.sin(angular_spread)}
	p.position = pe.position + offset

	p.lifetime = 0
	p.max_lifetime = HYPERSPACE_PARTICLE_LIFETIME + rand.float32() * 0.3

	p.data1 = rand.float32() * math.TAU // sparkle phase aka twinkling
	p.data2 = rand.float32() * 2.0 + 0.5 // warp intensity for size pulsing

	color_variant := rand.float32()
	if color_variant < 0.4 {
		// Bright cyan
		p.color = rl.Color{u8(50 + rand.float32() * 100),   // Red: 50-150
		                   u8(200 + rand.float32() * 55),   // Green: 200-255
		                   u8(200 + rand.float32() * 55),   // Blue: 200-255
		                   255}
	} else if color_variant < 0.7 {
		// Electric white
		p.color = rl.Color{u8(220 + rand.float32() * 35),   // Red: 220-255
		                   u8(220 + rand.float32() * 35),   // Green: 220-255
		                   u8(220 + rand.float32() * 35),   // Blue: 220-255
		                   255}
	} else {
		// Electric blue
		p.color = rl.Color{u8(100 + rand.float32() * 50),   // Red: 100-150
		                   u8(150 + rand.float32() * 75),   // Green: 150-225
		                   u8(200 + rand.float32() * 55),   // Blue: 200-255
		                   255}
	}

	spawn_particle(ps, p)
}

HYPERSPACE_EMITTER_SPAWN_RATE :: 20
HYPERSPACE_EMITTER_MAX_LIFETIME :: 0.3
make_hyperspace_emitter :: proc(position: Position) -> Particle_Emitter {
	continuous_data := Continuous_Emitter_Data{
		spawn_rate = HYPERSPACE_EMITTER_SPAWN_RATE,
		spawn_accumulator = 0,
	}

	pe := Particle_Emitter{
		type = .Hyperspace,
		position = position,
		active = true,
		data = continuous_data,
		max_lifetime = HYPERSPACE_EMITTER_MAX_LIFETIME,
	}
	return pe
}

spawn_hyperspace_emitter :: proc(ps: ^Particle_System, position: Position) {
	pe := make_hyperspace_emitter(position)
	spawn_transient_emitter(ps, pe)
}
