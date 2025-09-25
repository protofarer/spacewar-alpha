package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:strings"
import "core:math"
import "core:time"
import "core:math/noise"
import "core:math/rand"
import sa "core:container/small_array"
import rl "vendor:raylib"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2
Rect :: rl.Rectangle

WINDOW_W :: 1600
WINDOW_H :: 900
TICK_RATE :: 120
BACKGROUND_COLOR :: rl.BLACK
RENDER_TEXTURE_SCALE :: 1

TOPBAR_PERCENT_LENGTH :: 0.05
LOGICAL_SCREEN_WIDTH :: 1080
LOGICAL_SCREEN_HEIGHT :: LOGICAL_SCREEN_WIDTH * (1 + TOPBAR_PERCENT_LENGTH)


TOPBAR_HEIGHT :: LOGICAL_SCREEN_HEIGHT - LOGICAL_SCREEN_WIDTH
TOPBAR_COLOR :: rl.DARKBROWN
TOPBAR_DEFAULT_TEXT_COLOR :: rl.WHITE

PLAYFIELD_LENGTH :: LOGICAL_SCREEN_WIDTH

CENTRAL_STAR_ROTATION_RATE :: 500
CENTRAL_STAR_RADIUS :: 20
CENTRAL_STAR_MASS :: 1000000000000000000000

SHIP_DEFAULT_MASS :: 100000000000
SHIP_DEFAULT_RADIUS :: 20
SHIP_DEFAULT_COLOR :: rl.WHITE
SHIP_DEFAULT_FUEL_COUNT :: 100
SHIP_DEFAULT_TORPEDO_COUNT :: 32
SHIP_NEEDLE_COLLISION_CIRCLE_RADIUS :: 5
SHIP_DEFAULT_ROTATION_RATE :: 4
SHIP_DEFAULT_THRUST_FORCE :: 5000000000000
SHIP_DEFAULT_TORPEDO_COOLDOWN :: 0.8
SHIP_DEFAULT_HYPERSPACE_DURATION :: 3
SHIP_DEFAULT_HYPERSPACE_COOLDOWN :: 12

SHIP_TORPEDO_INITIAL_COUNT :: 32
MAX_LIVE_TORPEDOS :: 2 * SHIP_TORPEDO_INITIAL_COUNT 
TORPEDO_SPEED :: 200
TORPEDO_LIFESPAN :: 4 * time.Second
TORPEDO_RADIUS :: 2
TORPEDO_COLOR :: rl.RED

END_ROUND_DURATION :: 4

Game_Memory :: struct {
	app_state: App_State,
	debug: bool,
	pause: bool,

	render_texture: rl.RenderTexture,
	resman: Resource_Manager,
	audman: Audio_Manager,

	scene: Scene,
	players: [Player_ID]Player,
	scores: [Player_ID]i32,
	central_star: Star,
	torpedos: Torpedos,

	n_rounds: i32,
	end_round_duration_timer: Timer,
	end_round_display: string,

	starfield: Starfield,
	shaders: Shaders,

	bloom_shader_data: Bloom_Shader,
	particle_system: ^Particle_System,
}

App_State :: enum {
	Running,
	Exit,
}

Shaders :: [Shader_Kind]rl.Shader

Shader_Kind :: enum {
	FX_Fade_Threshold,
	FX_Bloom,
}


get_ship_by_ship_type :: proc(gm: Game_Memory, ship_type: Ship_Type) -> (ship: Ship, ok: bool) {
	for player in gm.players {
		if player.ship.ship_type == ship_type {
			return player.ship, true
		}
	}
	pr("ERROR: no ship exists for ship_type", ship_type)
	return {}, false
}

Scene :: enum {
	Play,
	End_Round,
}

Player :: struct {
	id: Player_ID,
	ship: Ship,
}

Player_ID :: enum {A,B}

Torpedo :: struct {
	position: Position,
	velocity: Vec2,
	radius: f32,
	creation_time: time.Time,
	lifespan: time.Duration,
}

Torpedos :: sa.Small_Array(MAX_LIVE_TORPEDOS, Torpedo)

Star :: struct {
	position: Position,
	mass: f32,
	rotation: f32,
	rotation_rate: f32,
	radius: f32,
}

Starfield_Star :: struct {
	position: Position,
	color: rl.Color,
}

MAX_STARFIELD_STARS :: 1024
Starfield_Stars :: sa.Small_Array(MAX_STARFIELD_STARS, Starfield_Star)
Starfield :: struct {
	stars: Starfield_Stars,
	period: f32,
	timer: Timer,
	velocity: Vec2,
}

Circle :: struct {
	center: Vec2,
	radius: f32,
}

Collision_Circles :: sa.Small_Array(8, Circle)
Ship_Rotation_Direction :: enum {Left, Right}

Ship :: struct {
	ship_type: Ship_Type,
	position: Position,
	velocity: Vec2,
	mass: f32,
	collision_circles: Collision_Circles,
	rotation: f32,
	color: rl.Color,

	fuel_count: i32,
	torpedo_count: i32,
	hyperspace_count: i32,

	is_thrusting: bool,
	is_hyperspacing: bool,
	is_firing: bool,

	torpedo_cooldown_timer: Timer,

	is_destroyed: bool,
	hyperspace_duration_timer: Timer,
	hyperspace_cooldown_timer: Timer,

	input: bit_set[Play_Input],
}

g: ^Game_Memory

update :: proc() {
	dt := rl.GetFrameTime()

	if rl.IsWindowResized() do update_mouse_transform()

	update_audio_manager()
	process_global_input()

	if g.pause {
		return
	}

	// next_scene: Maybe(Scene) = nil
	switch g.scene {
	case .Play:
		update_play_scene(g, dt)
		
	case .End_Round:
		update_particle_system(g, dt)
		process_timer(&g.end_round_duration_timer, dt)
		if is_timer_done(g.end_round_duration_timer) {
			reset_timer(&g.end_round_duration_timer)
			g.end_round_display = ""

			// reset_playfield_objects ??
			reset_players(g)
			clear_torpedos(g)
			clear_particle_system(g)

			g.scene = .Play
		}
	}
}

draw :: proc() {
	begin_letterbox_rendering()

	switch g.scene {
	case .Play:
		draw_playfield(g^)
	case .End_Round:
		draw_playfield(g^)
		draw_end_round(g^)
	}

	if g.debug {
		// origin lines
		draw_debug_origin_axes()

		for player in g.players {
			ship_pos := player.ship.position
			rot := player.ship.rotation
			cc := player.ship.collision_circles
			for circle in sa.slice(&cc) {
				// circle center is already relative to ship's position, circle.center.x is relative to ship's position and oriented wrt to ship with zero rotation, thus x is horizontal or longitudinal wrt ship, y is vertical or perpendicular wrt to ship's longitude
				x := ship_pos.x + circle.center.x * math.cos(rot) - circle.center.y * math.sin(rot)
				y := ship_pos.y + circle.center.x * math.sin(rot) + circle.center.y * math.sin(rot)
				rl.DrawCircleLines(i32(x), i32(y), circle.radius, rl.GREEN)
			}
		}
	}

	if g.pause {
		rl.DrawRectangle(0, 0, 90, 90, {0, 0, 0, 180})
		rl.DrawText("PAUSED", 90, 90, 30, rl.WHITE)
	}

	draw_topbar(g^)

	end_letterbox_rendering()


	if g.debug {
		draw_debug_overlay() // outside of render texture scaling
	}

	rl.EndDrawing()
}

Bloom_Shader :: struct {
	shader: rl.Shader,
	resolution_loc: i32,
	threshold_loc: i32,
	intensity_loc: i32,
	spread_loc: i32,
	resolution: Vec2,
	threshold: f32,
	intensity: f32,
	spread: f32,
}

setup_bloom_shader :: proc() -> Bloom_Shader {
	shader := rl.LoadShader(nil, "assets/shaders/bloom.fs")

	bloom_shader_data: Bloom_Shader
	bloom_shader_data.shader = shader

    // Get uniform locations
    bloom_shader_data.resolution_loc = rl.GetShaderLocation(bloom_shader_data.shader, "resolution")
    bloom_shader_data.threshold_loc = rl.GetShaderLocation(bloom_shader_data.shader, "bloomThreshold")
    bloom_shader_data.intensity_loc = rl.GetShaderLocation(bloom_shader_data.shader, "bloomIntensity")
    bloom_shader_data.spread_loc = rl.GetShaderLocation(bloom_shader_data.shader, "bloomSpread")

	bloom_shader_data.resolution = {LOGICAL_SCREEN_WIDTH, LOGICAL_SCREEN_HEIGHT}
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.resolution_loc, &bloom_shader_data.resolution, rl.ShaderUniformDataType.VEC2)

    bloom_shader_data.intensity = 1.25
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.intensity_loc, &bloom_shader_data.intensity, rl.ShaderUniformDataType.FLOAT)

	bloom_shader_data.threshold = 0.9
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.threshold_loc, &bloom_shader_data.threshold, rl.ShaderUniformDataType.FLOAT)

    bloom_shader_data.spread = 1.1
    rl.SetShaderValue(bloom_shader_data.shader, bloom_shader_data.spread_loc, &bloom_shader_data.spread, rl.ShaderUniformDataType.FLOAT)

	return bloom_shader_data
}
 
// Run once: allocate, set global variable immutable values
setup :: proc() -> bool {
	g = new(Game_Memory)
	if g == nil {
		log.error("Failed to allocate game memory.")
		return false
	}

	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		log.warn("Failed to initialize raylib audio device.")
	}
	audman := init_audio_manager()

	resman: Resource_Manager
	setup_resource_manager(&resman)
	load_all_assets(&resman)

	// TODO: generate noised starfield objects
	// - sample to achieve desired density
	// - save star objects
	// - choose random starfield pan direction (heading)
	// - update_starfield :: translate stars by heading
	// - draw_starfield_star

	// gen starfield using organic noise

	starfield: Starfield
	seed:i64= 6
	sample_resolution: f32 = 64
	noise_scale: f32 = 0.02
	star_threshold: f32 = 0.0
	init_starfield(&starfield, 
				   seed, 
				   get_playfield_left(), 
				   get_playfield_top(), 
				   PLAYFIELD_LENGTH, 
				   PLAYFIELD_LENGTH, 
				   sample_resolution, 
				   star_threshold, 
				   noise_scale)

	shaders: Shaders
	shaders[.FX_Fade_Threshold] = rl.LoadShader(nil, "assets/shaders/threshold.fs")

	bloom_shader_data := setup_bloom_shader()

	shaders[.FX_Bloom] = bloom_shader_data.shader

	g^ = Game_Memory {
		resman = resman,
		audman = audman,
		render_texture = rl.LoadRenderTexture(LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, 
											  LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE),
		app_state = .Running,
		debug = true,
		starfield = starfield,
		end_round_duration_timer = create_timer(END_ROUND_DURATION),
		end_round_display = "",
		shaders = shaders,
		bloom_shader_data = bloom_shader_data,
	}

	return true
}

JITTER_NOISE_SCALE_FACTOR :: 0.1
JITTER_SCALE_FACTOR :: 0.4
init_starfield :: proc(
	starfield: ^Starfield,
	seed: i64,
	start_x, start_y: f32,
	width, height: f32,
	sample_resolution: f32 = 32.0,
	star_threshold: f32 = 0.0,
	noise_scale: f32 = 0.02
) {
	starfield_stars := &starfield.stars
	for y := start_y; y < start_y + height; y += sample_resolution {
		for x := start_x; x < start_x + width; x += sample_resolution {
			noise_coord := [2]f64{
				f64(x) * f64(noise_scale),
				f64(y) * f64(noise_scale),
			}
			noise_val := noise.noise_2d(seed, noise_coord)

			if noise_val > star_threshold {
				jitter_noise_x := noise.noise_2d(seed + 1000, 
					{f64(x) * JITTER_NOISE_SCALE_FACTOR, 
					f64(y) * JITTER_NOISE_SCALE_FACTOR})
				jitter_noise_y := noise.noise_2d(seed + 2000, 
					{f64(x) * JITTER_NOISE_SCALE_FACTOR, 
					f64(y) * JITTER_NOISE_SCALE_FACTOR})

				jitter_x := f32(jitter_noise_x) * sample_resolution * JITTER_SCALE_FACTOR
				jitter_y := f32(jitter_noise_y) * sample_resolution * JITTER_SCALE_FACTOR
				pos := Position{math.clamp(x + jitter_x, start_x, start_x + width),
								math.clamp(y + jitter_y, start_y, start_y + height)}
				sa.push(starfield_stars, Starfield_Star{position = pos, color = rl.WHITE})
				if sa.len(starfield_stars^) > MAX_STARFIELD_STARS {
					pr("WARN: exceeded max starfield stars of", MAX_STARFIELD_STARS)
					break
				}
			}
		}
	}
	starfield.period = 0.2
	starfield.timer = create_timer(starfield.period)
	starfield.velocity = {0.5,0.5}
	start_timer(&starfield.timer)
}

// clear collections, set initial values
init :: proc() -> bool {
	if g == nil {
		log.error("Failed to initialize app state, Game_Memory nil")
		return false
	}
	g.scene = .Play

	player_a: Player
	init_player(&player_a, .Wedge, {-50, -50})
	player_a.id = .A
	g.players[.A] = player_a

	player_b: Player
	init_player(&player_b, .Needle, {50, -50})
	player_b.id = .B
	g.players[.B] = player_b

	g.central_star = Star{
		position = {0,0},
		rotation = 0,
		mass = CENTRAL_STAR_MASS,
		rotation_rate = CENTRAL_STAR_ROTATION_RATE,
		radius = CENTRAL_STAR_RADIUS,
	}

	g.n_rounds = 1

	ps := new(Particle_System)
	ps.thrust_emitters[.Wedge] = make_thrust_emitter()
	ps.thrust_emitters[.Needle] = make_thrust_emitter()
	g.particle_system = ps

	return true
}

@(export)
game_update :: proc() {
	update()
	draw()
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(WINDOW_W, WINDOW_H, "Spacewar!")
	rl.SetWindowPosition(10, 125)
	rl.SetTargetFPS(TICK_RATE)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	log.info("Initializing game...")

	 // run once
	if !setup() {
		log.error("Setup failed, exiting")
		game_shutdown()
		game_shutdown_window()
		return
	}

	 // run after setup, then on game reset
	if !init() {
		log.error("Failed initialization")
		game_shutdown()
		game_shutdown_window()
		return
	}
	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.app_state != .Exit
}

@(export)
game_shutdown :: proc() {
	unload_all_assets(&g.resman)
	rl.UnloadRenderTexture(g.render_texture)
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseAudioDevice()
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

game_reset :: proc() {
	init()
}

///////////////////////////////////////////////////////////////////////////////
// Global Input
///////////////////////////////////////////////////////////////////////////////

Global_Input :: enum {
	Toggle_Debug,
	Exit,
	Exit2,
	Reset,
	Pause,
	Increase_Bloom_Intensity,
	Decrease_Bloom_Intensity,
	Increase_Bloom_Threshold,
	Decrease_Bloom_Threshold,
	Increase_Bloom_Spread,
	Decrease_Bloom_Spread,
}

GLOBAL_INPUT_LOOKUP := [Global_Input]rl.KeyboardKey{
	.Toggle_Debug = .GRAVE,
	.Exit = .ESCAPE,
	.Exit2 = .Q,
	.Reset = .R,
	.Pause = .P,
	.Decrease_Bloom_Intensity = .Y,
	.Increase_Bloom_Intensity = .U,
	.Decrease_Bloom_Threshold = .H,
	.Increase_Bloom_Threshold = .J,
	.Decrease_Bloom_Spread = .N,
	.Increase_Bloom_Spread = .M,
}

BLOOM_INTENSITY_INCR :: 0.25
BLOOM_THRESHOLD_INCR :: 0.025
BLOOM_SPREAD_INCR :: 0.1
process_global_input :: proc() {
	input: bit_set[Global_Input]
	for key, input_ in GLOBAL_INPUT_LOOKUP {
		if rl.IsKeyPressed(key) {
			input += {input_}
		}
	}
    if .Toggle_Debug in input {
        g.debug = !g.debug
    } else if .Exit in input || .Exit2 in input {
		g.app_state = .Exit
	} else if .Reset in input {
		game_reset()
	} else if .Pause in input {
		g.pause = !g.pause

	} else if .Increase_Bloom_Intensity in input {
		g.bloom_shader_data.intensity += BLOOM_INTENSITY_INCR
		rl.SetShaderValue(g.bloom_shader_data.shader, g.bloom_shader_data.intensity_loc, &g.bloom_shader_data.intensity, rl.ShaderUniformDataType.FLOAT)
	} else if .Decrease_Bloom_Intensity in input {
		g.bloom_shader_data.intensity -= BLOOM_INTENSITY_INCR
		rl.SetShaderValue(g.bloom_shader_data.shader, g.bloom_shader_data.intensity_loc, &g.bloom_shader_data.intensity, rl.ShaderUniformDataType.FLOAT)

	} else if .Increase_Bloom_Threshold in input {
		g.bloom_shader_data.threshold += BLOOM_THRESHOLD_INCR
		rl.SetShaderValue(g.bloom_shader_data.shader, g.bloom_shader_data.threshold_loc, &g.bloom_shader_data.threshold, rl.ShaderUniformDataType.FLOAT)
	} else if .Decrease_Bloom_Threshold in input {
		g.bloom_shader_data.threshold -= BLOOM_THRESHOLD_INCR
		rl.SetShaderValue(g.bloom_shader_data.shader, g.bloom_shader_data.threshold_loc, &g.bloom_shader_data.threshold, rl.ShaderUniformDataType.FLOAT)

	} else if .Increase_Bloom_Spread in input {
		g.bloom_shader_data.spread += BLOOM_SPREAD_INCR
		rl.SetShaderValue(g.bloom_shader_data.shader, g.bloom_shader_data.spread_loc, &g.bloom_shader_data.spread, rl.ShaderUniformDataType.FLOAT)
	} else if .Decrease_Bloom_Spread in input {
		g.bloom_shader_data.spread -= BLOOM_SPREAD_INCR
		rl.SetShaderValue(g.bloom_shader_data.shader, g.bloom_shader_data.spread_loc, &g.bloom_shader_data.spread, rl.ShaderUniformDataType.FLOAT)
	}
}

///////////////////////////////////////////////////////////////////////////////
// Play Scene
///////////////////////////////////////////////////////////////////////////////

Play_Input :: enum {
	Thrust,
	Rotate_Left,
	Rotate_Right,
	Fire,
	Hyperspace,
}

process_play_input :: proc(gm: ^Game_Memory) {
	input: bit_set[Play_Input]

	if rl.IsKeyDown(.S) {
		input += {.Thrust}
	}
	if rl.IsKeyDown(.W) {
		input += {.Fire}
	}
	if rl.IsKeyDown(.A) {
		input += {.Rotate_Left}
	}
	if rl.IsKeyDown(.D) {
		input += {.Rotate_Right}
	}
	if rl.IsKeyPressed(.SPACE) {
		input += {.Hyperspace}
	}

	ship := &g.players[.A].ship

	ship.input = input

	// Set necessary state here, including for render
	ship.is_thrusting = false
	ship.is_hyperspacing = false
	ship.is_firing = false
}

apply_ship_physics :: proc(ship: ^Ship, dt: f32) {
	if .Rotate_Left in ship.input {
		ship.rotation -= SHIP_DEFAULT_ROTATION_RATE * dt
	} else if .Rotate_Right in ship.input {
		ship.rotation += SHIP_DEFAULT_ROTATION_RATE * dt
	}

	if .Thrust in ship.input {
		heading := Vec2{
			math.cos(ship.rotation),
			math.sin(ship.rotation),
		}

		// make a thrust force vector: rotation vector * thrust_force
		thrust_force := heading * SHIP_DEFAULT_THRUST_FORCE

		// get an accel from: a = thrust_force_vector/ship_mass
		acc := thrust_force / ship.mass

		// apply to vel: vel += accel * dt
		d_vel := acc * dt

		ship.velocity += d_vel
		ship.is_thrusting = true
	}

	process_timer(&ship.hyperspace_cooldown_timer, dt)


	if .Hyperspace in ship.input {
		if is_timer_done(ship.hyperspace_cooldown_timer) {
			// hyperspace start anim
			// start timer
			// hyperspace end anim
			// move ship to rand pos
			if !is_timer_running(ship.hyperspace_duration_timer) {
				start_timer(&ship.hyperspace_duration_timer)
				ship.is_hyperspacing = true
			}

			process_timer(&ship.hyperspace_duration_timer, dt)

			if is_timer_done(ship.hyperspace_duration_timer) {
				rng_1 := rand.float32()
				rng_2 := rand.float32()
				w := get_playfield_width()
				h := get_playfield_height()

				possible_length_ratio: f32 = 0.85
				rand_x := get_playfield_left() + w * (1.0 - possible_length_ratio) + rng_1 * w * possible_length_ratio
				rand_y := get_playfield_top() + h * (1.0 - possible_length_ratio) + rng_2 * get_playfield_height() * possible_length_ratio

				ship.position.x = rand_x
				ship.position.y = rand_y
				ship.velocity = {}

				restart_timer(&ship.hyperspace_cooldown_timer)
				ship.is_hyperspacing = false
			}
		}
	}

}

GRAVITY_COEFFICIENT :: .0000000000667430
GRAVITY_FORCE_MAX :: 1000000000000000
METERS_PER_LOGICAL_UNIT_LENGTH :: 10000000
force_of_gravity :: proc(pos_ship: Vec2, pos_star: Vec2, mass_ship: f32, mass_star: f32) -> Vec2 {
	d_pos := pos_star - pos_ship
	distance := linalg.length(d_pos) * METERS_PER_LOGICAL_UNIT_LENGTH
	fg := clamp(GRAVITY_COEFFICIENT * mass_ship * mass_star / distance, 0, GRAVITY_FORCE_MAX)
	dir := linalg.normalize0(d_pos)
	force_vector := fg * dir
	return force_vector
}

apply_star_physics :: proc(ship: ^Ship, star: Star, dt: f32) {
	force_gravity := force_of_gravity(ship.position, star.position, ship.mass, star.mass)
	accel_gravity_ship := force_gravity / ship.mass
	d_vel := accel_gravity_ship * dt
	ship.velocity += d_vel
}

Ship_Type :: enum{Wedge, Needle}

init_player :: proc(p: ^Player, ship_type: Ship_Type, position: Position = {}) {
	p.ship = make_ship(ship_type, position)
	start_timer(&p.ship.torpedo_cooldown_timer)
	start_timer(&p.ship.hyperspace_cooldown_timer)
}

draw_sprite :: proc(texture_id: Texture_ID, pos: Vec2, size: Vec2, rotation: f32 = 0, scale: f32 = 1, tint: rl.Color = rl.WHITE) {
	tex := get_texture(texture_id)
	src_rect := Rect{
		0, 0, f32(tex.width), f32(tex.height),
	}
	dst_rect := Rect {
		pos.x, pos.y, size.x, size.y,
	}
	rl.DrawTexturePro(tex, src_rect, dst_rect, {}, rotation, tint)
}

debug_overlay_text_column :: proc(x,y: ^i32, slice_cstr: []string) {
	gy: i32 = 20
	for s in slice_cstr {
		cstr := strings.clone_to_cstring(s)
		rl.DrawText(cstr, x^, y^, 20, rl.WHITE)
		y^ += gy
	}
}

make_string_from_value :: proc(v: any) -> string {
	return fmt.tprintf("%v", v)
}

draw_debug_overlay :: proc() {
	{
		{
			ship := g.players[.A].ship
			x: i32 = 5
			y: i32 = 40

			rotating := .Rotate_Left in ship.input ? "Left" : .Rotate_Right in ship.input ? "Right" : "nil"

			arr := [?]string{
				fmt.tprintf("A"),
				fmt.tprintf("vel: %v", ship.velocity),
				fmt.tprintf("pos: %v", ship.position),
				fmt.tprintf("rot: %v", math.to_degrees(ship.rotation)),
				fmt.tprintf("mass: %v", ship.mass),
				fmt.tprintf("fuel_count: %v", ship.fuel_count),
				fmt.tprintf("torp_count: %v", ship.torpedo_count),
				fmt.tprintf("hyperspace_count: %v", ship.hyperspace_count),
				fmt.tprintf("is_thrusting: %v", ship.is_thrusting),
				fmt.tprintf("is_firing: %v", ship.is_firing),
				fmt.tprintf("rotating: %v", rotating),
				fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
				fmt.tprintf("is_destroyed: %v", ship.is_destroyed),
			}
			debug_overlay_text_column(&x, &y, arr[:])
		}
		{
			ship := g.players[.B].ship
			x: i32 = 5
			y: i32 = 400

			rotating := .Rotate_Left in ship.input ? "Left" : .Rotate_Right in ship.input ? "Right" : "nil"

			arr := [?]string{
				fmt.tprintf("B"),
				fmt.tprintf("vel: %v", ship.velocity),
				fmt.tprintf("pos: %v", ship.position),
				fmt.tprintf("rot: %v", math.to_degrees(ship.rotation)),
				fmt.tprintf("mass: %v", ship.mass),
				fmt.tprintf("fuel_count: %v", ship.fuel_count),
				fmt.tprintf("torp_count: %v", ship.torpedo_count),
				fmt.tprintf("hyperspace_count: %v", ship.hyperspace_count),
				fmt.tprintf("is_thrusting: %v", ship.is_thrusting),
				fmt.tprintf("rotating: %v", rotating),
				fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
				fmt.tprintf("is_destroyed: %v", ship.is_destroyed),
			}
			debug_overlay_text_column(&x, &y, arr[:])
		}

		{
			bsd := g.bloom_shader_data
			x: i32 = i32(get_playfield_right()) + 150
			y: i32 = 40

			arr := [?]string{
				fmt.tprintf("Bloom shader"),
				fmt.tprintf("intensity: %v", bsd.intensity),
				fmt.tprintf("threshold: %v", bsd.threshold),
				fmt.tprintf("spread: %v", bsd.spread),
			}
			debug_overlay_text_column(&x, &y, arr[:])
		}

	}
}

wraparound :: proc(position: ^Position) {
	if position.x < get_playfield_left() {
		position.x = get_playfield_right()
	} else if position.x > get_playfield_right() {
		position.x = get_playfield_left()
	}
	if position.y < get_playfield_top() {
		position.y = get_playfield_bottom()
	} else if position.y > get_playfield_bottom() {
		position.y = get_playfield_top()
	}
}

update_ship :: proc(gm: ^Game_Memory, ship: ^Ship, dt: f32) {
	ship.position.x += ship.velocity.x * dt
	ship.position.y += ship.velocity.y * dt

	// wraparound
	wraparound(&ship.position)

	process_timer(&ship.torpedo_cooldown_timer, dt) 
	if .Fire in ship.input {
		if is_timer_done(ship.torpedo_cooldown_timer) {
			pos_nose := get_ship_nose_position(ship^)
			torp_vel := ship.velocity + TORPEDO_SPEED * vec2_from_rotation(ship.rotation)
			spawn_torpedo(gm, pos_nose, torp_vel)
			ship.torpedo_count -= 1
			restart_timer(&ship.torpedo_cooldown_timer)
			ship.is_firing = true
		}
	}
}

make_torpedo :: proc(position: Position, velocity: Vec2) -> Torpedo {
	torp := Torpedo{
		position = position,
		velocity = velocity,
		lifespan = TORPEDO_LIFESPAN,
		creation_time = time.now(),
		radius = TORPEDO_RADIUS,
	}
	return torp
}

spawn_torpedo :: proc(gm: ^Game_Memory, position: Position, velocity: Vec2) {
	torp := make_torpedo(position, velocity)
	sa.push(&gm.torpedos, torp)
}

make_ship :: proc(ship_type: Ship_Type, position: Position = {-50, -50}, rotation: f32 = 0, mass: f32 = SHIP_DEFAULT_MASS) -> Ship {

	// collision_circles are relative to ship's position
	collision_circles: Collision_Circles

	switch ship_type {
	case .Wedge:
		cc_wedge := Circle{
			center = 0,
			radius = SHIP_DEFAULT_RADIUS,
		}
		sa.push(&collision_circles, cc_wedge)

	case .Needle:
		cc_r :f32= SHIP_DEFAULT_RADIUS * 0.35
		cc_1 := Circle{
			center = { 1.2 * SHIP_DEFAULT_RADIUS, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_1)
		cc_2 := Circle{
			center = { 0.6 * SHIP_DEFAULT_RADIUS, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_2)
		cc_3 := Circle{
			center = { -0.6 * SHIP_DEFAULT_RADIUS, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_3)
		cc_4 := Circle{
			center = { -1.2 * SHIP_DEFAULT_RADIUS, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_4)
		cc_5 := Circle{
			center = { 0, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_5)
	}

	return Ship{
		ship_type = ship_type,
		position = position,
		velocity = 0,
		rotation = 0,
		mass = SHIP_DEFAULT_MASS,
		collision_circles = collision_circles,
		color = SHIP_DEFAULT_COLOR,

		fuel_count = SHIP_DEFAULT_FUEL_COUNT,
		torpedo_count = SHIP_DEFAULT_TORPEDO_COUNT,
		hyperspace_count = 0,

		is_thrusting = false,
		is_hyperspacing = false,
		torpedo_cooldown_timer = create_timer(SHIP_DEFAULT_TORPEDO_COOLDOWN),
		hyperspace_duration_timer = create_timer(SHIP_DEFAULT_HYPERSPACE_DURATION),
		hyperspace_cooldown_timer = create_timer(SHIP_DEFAULT_HYPERSPACE_COOLDOWN)
	}
}

reset_players :: proc(gm: ^Game_Memory) {
	init_player(&gm.players[.A], .Wedge, {-50, -50})
	init_player(&gm.players[.B], .Needle, {50, -50})
}

clear_torpedos :: proc(gm: ^Game_Memory) {
	sa.clear(&gm.torpedos)
}

clear_particle_system :: proc(gm: ^Game_Memory) {
	sa.clear(&gm.particle_system.transient_emitters)
	sa.clear(&gm.particle_system.particles)
}

end_round :: proc(gm: ^Game_Memory, winner: Maybe(Player_ID)) {
	gm.n_rounds += 1
	gm.scene = .End_Round

	if winner, ok := winner.?; ok {
		ship_name := gm.players[winner].ship.ship_type
		gm.end_round_display = fmt.aprintf("%v wins the round!", ship_name)
	} else {
		gm.end_round_display = fmt.aprintf("Both ships were destroyed!")
	}

	start_timer(&gm.end_round_duration_timer)
}

update_starfield :: proc(gm: ^Game_Memory, dt: f32) {
	process_timer(&gm.starfield.timer, dt)
	if is_timer_done(gm.starfield.timer) {
		for &star in sa.slice(&gm.starfield.stars) {
			star.position += gm.starfield.velocity * dt
			wraparound(&star.position)
		}
		restart_timer(&gm.starfield.timer)
	}
}

update_play_scene :: proc(gm: ^Game_Memory, dt: f32) {
	process_play_input(gm)

	update_starfield(gm, dt)

	// Step physics and controls
	for &player in gm.players {
		if !player.ship.is_destroyed {
			apply_ship_physics(&player.ship, dt)
			// apply_star_physics(&player.ship, g.central_star, dt)
			update_ship(gm, &player.ship, dt)
		}
	}

	update_torpedos(&gm.torpedos, dt)


	// Collide
	// ship to ship

	cc_a := sa.get(gm.players[.A].ship.collision_circles, 0)
	ship_a := gm.players[.A].ship
	ship_b := gm.players[.B].ship

	for cc_b in sa.slice(&gm.players[.B].ship.collision_circles) {
		if circle_intersects(cc_a.center + ship_a.position, cc_a.radius, cc_b.center + ship_b.position, cc_b.radius) {
			destroy_ship(gm, &gm.players[.A].ship)
			destroy_ship(gm, &gm.players[.B].ship)

			end_round(gm, nil)
			break
		}
	}

	// torpedo to ship
	torp_collide_outer: for torp in sa.slice(&g.torpedos) {
		for cc_b in sa.slice(&g.players[.B].ship.collision_circles) {
			if circle_intersects(torp.position, torp.radius, cc_b.center + ship_b.position, cc_b.radius) {
				destroy_ship(gm, &gm.players[.B].ship)
				end_round(gm, .A)
				gm.scores[.A] += 1
				break torp_collide_outer
			}
		}
		if circle_intersects(torp.position, torp.radius, cc_a.center + ship_a.position, cc_a.radius) {
			destroy_ship(gm, &gm.players[.A].ship)
			end_round(gm, .B)
			gm.scores[.B] += 1
			break torp_collide_outer
		}
	}

	// Destroy and cleanup
	torp_indices_to_destroy: sa.Small_Array(MAX_LIVE_TORPEDOS, int)
	for torp, idx in sa.slice(&gm.torpedos) {
		if time.since(torp.creation_time) > torp.lifespan {
			sa.push(&torp_indices_to_destroy, idx)
		}
	}
	for index in sa.slice(&torp_indices_to_destroy) {
		destroy_torpedo(&gm.torpedos, index)
	}

	g.central_star.rotation += g.central_star.rotation_rate * dt

	update_particle_system(gm, dt)
}

destroy_ship :: proc(gm: ^Game_Memory, ship: ^Ship) {
	ship.is_destroyed = true
	spawn_explosion_emitter(gm.particle_system, ship.position)
}

update_torpedos :: proc(torpedos: ^Torpedos, dt: f32) {
	now := time.now()

	// Increment torpedo behavior
	for &torp, idx in sa.slice(torpedos) {
		// move
		torp.position += torp.velocity * dt
		wraparound(&torp.position)
	}
}

destroy_torpedo :: proc(torpedos: ^Torpedos, index: int) {
	sa.unordered_remove(torpedos, index)
}

draw_ship_wedge :: proc(ship: Ship) {
	pos_nose := Vec2{
		math.cos(ship.rotation) * SHIP_DEFAULT_RADIUS * 1.25,
		math.sin(ship.rotation) * SHIP_DEFAULT_RADIUS * 1.25,
	} + ship.position
	pos_left := Vec2{
		math.cos(ship.rotation - math.to_radians(f32(145))) * SHIP_DEFAULT_RADIUS,
		math.sin(ship.rotation - math.to_radians(f32(145))) * SHIP_DEFAULT_RADIUS,
	} + ship.position
	pos_right := Vec2{
		math.cos(ship.rotation + math.to_radians(f32(145))) * SHIP_DEFAULT_RADIUS,
		math.sin(ship.rotation + math.to_radians(f32(145))) * SHIP_DEFAULT_RADIUS,
	} + ship.position
	rl.DrawTriangle(pos_nose, pos_left, pos_right, rl.WHITE)
}

SHIP_NEEDLE_RADIUS_FACTOR :: 1.5
SHIP_WEDGE_RADIUS_FACTOR :: 1.25
get_ship_nose_position :: proc(ship: Ship) -> Position {
	ship_type_radius_factor: f32
	switch ship.ship_type {
	case .Needle:
		ship_type_radius_factor = SHIP_NEEDLE_RADIUS_FACTOR
	case .Wedge:
		ship_type_radius_factor =  SHIP_WEDGE_RADIUS_FACTOR
	}
	return Vec2{
			math.cos(ship.rotation) * SHIP_DEFAULT_RADIUS * ship_type_radius_factor,
			math.sin(ship.rotation) * SHIP_DEFAULT_RADIUS * ship_type_radius_factor,
		} + ship.position
}

get_ship_tail_position :: proc(ship: Ship) -> Position {
	ship_type_radius_factor: f32
	switch ship.ship_type {
	case .Needle:
		ship_type_radius_factor = SHIP_NEEDLE_RADIUS_FACTOR
	case .Wedge:
		ship_type_radius_factor =  SHIP_WEDGE_RADIUS_FACTOR
	}
	return Vec2{
			math.cos(ship.rotation + math.PI) * SHIP_DEFAULT_RADIUS * ship_type_radius_factor,
			math.sin(ship.rotation + math.PI) * SHIP_DEFAULT_RADIUS * ship_type_radius_factor,
		} + ship.position
}

draw_ship_needle :: proc(ship: Ship) {
	half_span_vector := Vec2{
		math.cos(ship.rotation) * SHIP_DEFAULT_RADIUS * 1.5,
		math.sin(ship.rotation) * SHIP_DEFAULT_RADIUS * 1.5,
	} 

	pos_nose := ship.position + half_span_vector
	pos_tail := ship.position - half_span_vector
	rl.DrawLineEx(pos_nose, pos_tail, 4, rl.WHITE)
}

draw_star :: proc(star: Star) {
	star_pos := star.position
	{
		p1 := Vec2{
			star_pos.x + star.radius * math.cos(math.to_radians(0 + star.rotation)),
			star_pos.y + star.radius * math.sin(math.to_radians(0 + star.rotation)),
		}
		p2 := Vec2{
			star_pos.x + star.radius * math.cos(math.to_radians(120 + star.rotation)),
			star_pos.y + star.radius * math.sin(math.to_radians(120 + star.rotation)),
		}
		p3 := Vec2{
			star_pos.x + star.radius * math.cos(math.to_radians(240 + star.rotation)),
			star_pos.y + star.radius * math.sin(math.to_radians(240 + star.rotation)),
		}
		rl.DrawTriangleLines(p1,p2,p3,rl.PURPLE)
	}
	{
		p1 := Vec2{
			star_pos.x + star.radius * math.cos(math.to_radians(180 + star.rotation)),
			star_pos.y + star.radius * math.sin(math.to_radians(180 + star.rotation)),
		}
		p2 := Vec2{
			star_pos.x + star.radius * math.cos(math.to_radians(180 - 120 + star.rotation)),
			star_pos.y + star.radius * math.sin(math.to_radians(180 - 120 + star.rotation)),
		}
		p3 := Vec2{
			star_pos.x + star.radius * math.cos(math.to_radians(180 - 240 + star.rotation)),
			star_pos.y + star.radius * math.sin(math.to_radians(180 - 240 + star.rotation)),
		}
		rl.DrawTriangleLines(p1,p2,p3,rl.PURPLE)
	}
}

get_screen_top :: proc() -> f32 {
	return -f32(LOGICAL_SCREEN_HEIGHT) / 2
}

get_screen_bottom :: proc() -> f32 {
	return f32(LOGICAL_SCREEN_HEIGHT) / 2
}

get_screen_left :: proc() -> f32 {
	return -f32(LOGICAL_SCREEN_WIDTH) / 2
}

get_screen_right :: proc() -> f32 {
	return f32(LOGICAL_SCREEN_WIDTH) / 2
}

get_playfield_top :: proc() -> f32 {
	return -f32(PLAYFIELD_LENGTH) / 2 + f32(TOPBAR_HEIGHT) / 2
}

get_playfield_bottom :: proc() -> f32 {
	return f32(PLAYFIELD_LENGTH) / 2 + f32(TOPBAR_HEIGHT) / 2
}

get_playfield_left :: proc() -> f32 {
	return -f32(PLAYFIELD_LENGTH) / 2
}

get_playfield_right :: proc() -> f32 {
	return f32(PLAYFIELD_LENGTH) / 2
}

get_playfield_width :: proc() -> f32 {
	return PLAYFIELD_LENGTH
}

get_playfield_height :: proc() -> f32 {
	return  PLAYFIELD_LENGTH
}

draw_topbar :: proc(gm: Game_Memory) {
	topbar_width := i32(math.round(f32(LOGICAL_SCREEN_WIDTH)))
	topbar_height := i32(math.round(f32(TOPBAR_HEIGHT)))
	screen_width := i32(math.round(f32(LOGICAL_SCREEN_WIDTH)))
	screen_height := i32(math.round(f32(LOGICAL_SCREEN_HEIGHT)))
	rl.DrawRectangle(-screen_width/2,
					-screen_height/2,
					topbar_width,
					topbar_height,
					TOPBAR_COLOR)

	fs: i32 = 20
	gap_x: i32 = 25
	gap_y: i32 = 20
	{
		// player a
		ship := gm.players[.A].ship
		x: i32 = i32(get_screen_left()) + 10
		y: i32 = i32(get_screen_top()) + 5

		torp_display := fmt.ctprintf("torpedos: %v", ship.torpedo_count)
		rl.DrawText(torp_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		hyperspace_display := fmt.ctprintf("hyperspace jumps: %v", ship.hyperspace_count)
		rl.DrawText(hyperspace_display, x, y + gap_y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		x += rl.MeasureText(torp_display, fs) + gap_x
		fuel_display := fmt.ctprintf("fuel: %v%%", ship.fuel_count)
		rl.DrawText(fuel_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
	}

	{
		// player b
		ship := gm.players[.B].ship
		x: i32 = i32(get_screen_right()) - 300
		y: i32 = i32(get_screen_top()) + 5

		torp_display := fmt.ctprintf("torpedos: %v", ship.torpedo_count)
		rl.DrawText(torp_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		hyperspace_display := fmt.ctprintf("hyperspace jumps: %v", ship.hyperspace_count)
		rl.DrawText(hyperspace_display, x, y + gap_y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		x += rl.MeasureText(torp_display, fs) + gap_x
		fuel_display := fmt.ctprintf("fuel: %v%%", ship.fuel_count)
		rl.DrawText(fuel_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
	}


	{
		x: i32 = i32(get_screen_left()) + i32((get_screen_right() - get_screen_left()) / 2) - 150
		y: i32 = i32(get_screen_top()) + 5

		round_display := fmt.ctprintf("round: %v", g.n_rounds)
		rl.DrawText(round_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		x += rl.MeasureText(round_display, fs) + gap_x * 2

		score_display := fmt.ctprintf("%v - %v", g.scores[.A], g.scores[.B])
		rl.DrawText(score_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
	}
}

draw_debug_origin_axes :: proc() {
	rl.DrawLine(i32(get_playfield_left()), 0, i32(get_playfield_right()), 0, rl.BLUE)
	rl.DrawLine(0, i32(get_playfield_top()), 0, i32(get_playfield_bottom()), rl.BLUE)
}

draw_torpedos :: proc(torps: Torpedos) {
	ts := torps
	for torp in sa.slice(&ts) {
		rl.DrawCircle(i32(torp.position.x), i32(torp.position.y), torp.radius, TORPEDO_COLOR)
	}
}

draw_starfield :: proc(starfield_stars: Starfield_Stars) {
	sf := starfield_stars
	for star in sa.slice(&sf) {
		rl.DrawCircleV(star.position, 1, star.color)
	}
}

draw_playfield :: proc(gm: Game_Memory) {
	draw_starfield(gm.starfield.stars)

	// rl.BeginBlendMode(.ADDITIVE)
	for player in gm.players {
		if player.ship.ship_type == .Wedge {
			draw_ship_wedge(player.ship)
		} else if player.ship.ship_type == .Needle {
			draw_ship_needle(player.ship)
		}
	}

	for particle in sa.slice(&gm.particle_system.particles) {
		rl.DrawPixel(i32(particle.position.x), i32(particle.position.y), particle.color)
	}
	// rl.EndBlendMode()

	// draw_star(g.central_star)
	draw_torpedos(gm.torpedos)
}

draw_end_round :: proc(gm: Game_Memory) {
	cstr := fmt.ctprintf(gm.end_round_display)
	text_length := rl.MeasureText(cstr, 32)
	x := get_playfield_left() + get_playfield_width() / 2 - f32(text_length) / 2
	y := get_playfield_top() + get_playfield_height() / 2 - 64
	rl.DrawText(cstr, i32(x), i32(y), 32, rl.RED)
}
