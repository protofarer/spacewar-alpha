package game

import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import "core:math/linalg"
import "core:math/noise"
import "core:math/rand"
import "core:strings"
import sa "core:container/small_array"
import rl "vendor:raylib"

Position :: Vec2

RAYLIB_TRACELOGLEVEL :: rl.TraceLogLevel.WARNING

WINDOW_W :: 1600
WINDOW_H :: 900
TICK_RATE :: 120
RENDER_TEXTURE_SCALE :: 1

TOPBAR_PERCENT_LENGTH :: 0.05
LOGICAL_SCREEN_WIDTH :: 1080
LOGICAL_SCREEN_HEIGHT :: LOGICAL_SCREEN_WIDTH * (1 + TOPBAR_PERCENT_LENGTH)

TOPBAR_HEIGHT :: LOGICAL_SCREEN_HEIGHT - LOGICAL_SCREEN_WIDTH
TOPBAR_COLOR :: rl.DARKBROWN
TOPBAR_DEFAULT_TEXT_COLOR :: rl.WHITE

PLAYFIELD_LENGTH :: LOGICAL_SCREEN_WIDTH

END_ROUND_DURATION :: 4
END_MATCH_DURATION :: 4

Game_Memory :: struct {
	app_state: App_State,
	debug: bool,
	pause: bool,

	render_texture: rl.RenderTexture,
	resman: Resource_Manager,
	audman: Audio_Manager,

	shaders: Shaders,
	bloom_shader_data: Bloom_Shader,

	particle_system: ^Particle_System,
	scene: Scene,
	scores: [Player_ID]i32,

	players: [Player_ID]Player,
	torpedos: Torpedos,

	central_star: Star,
	central_star_rays: Central_Star_Rays,
	starfield: Starfield,

	n_rounds: i32,

	end_round_duration_timer: Timer,
	end_round_display: string,
	has_end_round_mid_action_played: bool,

	end_match_duration_timer: Timer,
	end_match_display: string,
}

App_State :: enum {
	Running,
	Exit,
}

Scene :: enum {
	Title,
	Play,
	End_Round,
	End_Match,
}

Player_ID :: enum {A,B}
Player :: struct {
	id: Player_ID,
	input: Play_Input_Flags,
	ship: Ship,
	gamepad_id: i32,
}

Circle :: struct {
	center: Vec2,
	radius: f32,
}
Collision_Circles :: sa.Small_Array(8, Circle)

Star :: struct {
	position: Position,
	radius: f32,
	rotation: f32,
	rotation_rate: f32,
	mass: f32,
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

CENTRAL_STAR_ROTATION_RATE :: 100
CENTRAL_STAR_RADIUS :: 20
CENTRAL_STAR_MASS :: 500000000000000000000
CENTRAL_STAR_RAY_COUNT :: 64
Star_Ray :: struct {
	angle, length, phase_offset: f32,
}
Central_Star_Rays :: sa.Small_Array(CENTRAL_STAR_RAY_COUNT, Star_Ray)

SHIP_DEFAULT_MASS :: 100000000000
SHIP_DEFAULT_RADIUS :: 20
SHIP_DEFAULT_COLOR :: rl.GREEN
SHIP_DEFAULT_FUEL_MAX :: 100
SHIP_DEFAULT_TORPEDO_COUNT :: 32
SHIP_NEEDLE_COLLISION_CIRCLE_RADIUS :: 5
SHIP_DEFAULT_ROTATION_RATE :: 4
SHIP_DEFAULT_THRUST_FORCE :: 1000000000000
SHIP_DEFAULT_TORPEDO_COOLDOWN :: 0.8
SHIP_DEFAULT_HYPERSPACE_DURATION :: 3
SHIP_DEFAULT_HYPERSPACE_COOLDOWN :: 12
SHIP_TORPEDO_INITIAL_COUNT :: 32
SHIP_FUEL_BURN_RATE :: 1

Ship_Rotation_Direction :: enum {Left, Right}
Ship_Type :: enum{Wedge, Needle}

Ship :: struct {
	ship_type: Ship_Type,
	position: Position,
	velocity: Vec2,
	mass: f32,
	collision_circles: Collision_Circles,
	rotation: f32,
	color: rl.Color,

	fuel: f32,
	max_fuel: f32,
	torpedo_count: i32,
	hyperspace_count: i32,

	is_thrusting: bool,
	is_hyperspacing: bool,
	is_firing: bool,

	torpedo_cooldown_timer: Timer,

	is_destroyed: bool,
	hyperspace_duration_timer: Timer,
	hyperspace_cooldown_timer: Timer,
	has_hyperspace_available_sound_played: bool,
	r: f32, // canonical length for scaling
}

MAX_LIVE_TORPEDOS :: 2 * SHIP_TORPEDO_INITIAL_COUNT 
TORPEDO_SPEED :: 200
TORPEDO_LIFESPAN :: 4 * time.Second
TORPEDO_RADIUS :: 2
TORPEDO_COLOR :: rl.RED
Torpedo :: struct {
	position: Position,
	velocity: Vec2,
	radius: f32,
	creation_time: time.Time,
	lifespan: time.Duration,
}

Torpedos :: sa.Small_Array(MAX_LIVE_TORPEDOS, Torpedo)

g: ^Game_Memory

update :: proc() {
	dt := rl.GetFrameTime()

	process_global_input(g)

	if g.pause {
		return
	}

	update_audio_manager()

	switch g.scene {
	case .Title:
		if rl.IsKeyPressed(.ENTER) {
			g.scene = .Play
		}
	case .Play:
		update_play_scene(g, dt)
		
	case .End_Round:
		update_particle_system(g, dt)

		process_timer(&g.end_round_duration_timer, dt)
		if get_timer_progress(g.end_round_duration_timer) >= 0.5 && !g.has_end_round_mid_action_played {
			play_sfx(.End_Round)
			g.has_end_round_mid_action_played = true
		}

		if is_timer_done(g.end_round_duration_timer) {

			if end_match_condition(g) {
				start_end_match(g)
			} else {
				reset_end_round_state(g)
				reset_playfield_objects(g)
				g.scene = .Play
			}
		}

	case .End_Match:
		process_timer(&g.end_match_duration_timer, dt)
		if is_timer_done(g.end_match_duration_timer) {
			reset_end_match_state(g)
			reset_playfield_objects(g)
			reset_scores(g)
			g.scene = .Play
		}
	}
}

reset_scores :: proc(gm: ^Game_Memory) {
	gm.scores = {}
}

draw :: proc() {
	rl.BeginTextureMode(g.render_texture)
	rl.DrawRectangle(0,0,LOGICAL_SCREEN_WIDTH,LOGICAL_SCREEN_HEIGHT, rl.Fade(rl.BLACK, 0.08))
	
	camera := rl.Camera2D{
		zoom = RENDER_TEXTURE_SCALE,
		offset = { 
			get_playfield_right() * RENDER_TEXTURE_SCALE,
			get_playfield_bottom() * RENDER_TEXTURE_SCALE,
		},
	}
	rl.BeginMode2D(camera)

	switch g.scene {
	case .Title:
		draw_title(g^)
	case .Play:
		draw_playfield(g^)
		draw_topbar(g^)
	case .End_Round:
		draw_playfield(g^)
		draw_topbar(g^)
		if g.has_end_round_mid_action_played do draw_end_round(g^)
	case .End_Match:
		draw_playfield(g^)
		draw_topbar(g^)
		draw_end_match(g^)
	}

	if g.debug {
		draw_debug_origin_axes(get_playfield_left(),
							   get_playfield_right(),
							   get_playfield_top(),
							   get_playfield_bottom())

		for player in g.players {
			ship_pos := player.ship.position
			rot := player.ship.rotation
			cc := player.ship.collision_circles
			for circle in sa.slice(&cc) {
				// circle center is already relative to ship's position, circle.center.x is relative to ship's position and oriented wrt to ship with zero rotation, thus x is horizontal or longitudinal wrt ship, y is vertical or perpendicular wrt to ship's longitude
				x := ship_pos.x + circle.center.x * math.cos(rot) - circle.center.y * math.sin(rot)
				y := ship_pos.y + circle.center.x * math.sin(rot) + circle.center.y * math.sin(rot)
				rl.DrawCircleLines(i32(x), i32(y), circle.radius, rl.BLUE)
			}
		}
	}

	if g.pause {
		left := get_playfield_left()
		top := get_playfield_top()
		rl.DrawRectangleV({left, top}, {get_playfield_width(), get_playfield_height()}, {0, 0, 0, 128})
		x := get_centered_text_x_coord("PAUSED", 60, 0)
		rl.DrawText("PAUSED", x, -30, 60, rl.WHITE)
	}

	rl.EndMode2D()  // End the scale transform
	rl.EndTextureMode()
	
	rl.BeginDrawing()
		rl.ClearBackground(LETTERBOX_COLOR)
		rl.BeginShaderMode(g.shaders[.FX_Bloom])
			src, dst := get_render_rects()
			rl.DrawTexturePro(g.render_texture.texture, src, dst, {}, 0, rl.WHITE)
		rl.EndShaderMode()

		if g.debug {
			draw_debug_overlay() // outside of render texture scaling
		}
	rl.EndDrawing()
}
 
TITLE_DURATION :: 6
// Run once: allocate, set global variable immutable values
setup :: proc() -> bool {
	g = new(Game_Memory)
	if g == nil {
		log.error("Failed to allocate game memory.")
		return false
	}

	// Use latest SDL 2 mappings rather than outdated glfw
	mappings := rl.LoadFileText(fmt.ctprintf("assets/gamecontrollerdb.txt"))
	rl.SetGamepadMappings(cstring(mappings))

	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		log.warn("Failed to initialize raylib audio device")
	}
	audman := init_audio_manager()

	resman: Resource_Manager
	setup_resource_manager(&resman)
	load_all_assets(&resman)

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
	bloom_shader_data := setup_bloom_shader()
	shaders[.FX_Bloom] = bloom_shader_data.shader

	g^ = Game_Memory {
		app_state = .Running,
		debug = false,

		resman = resman,
		audman = audman,
		render_texture = rl.LoadRenderTexture(LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, 
											  LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE),

		shaders = shaders,
		bloom_shader_data = bloom_shader_data,

		starfield = starfield,
		end_round_duration_timer = create_timer(END_ROUND_DURATION),
		end_round_display = "",

		end_match_duration_timer = create_timer(END_MATCH_DURATION),
		end_match_display = "",
	}
	play_music(.Background)

	return true
}

// clear collections, set initial values
init :: proc() -> bool {
	if g == nil {
		log.error("Failed to initialize app state, Game_Memory nil")
		return false
	}
	g.scene = .Title

	player_a: Player
	init_player(&player_a, .A, .Wedge, {-200, -200})
	g.players[.A] = player_a

	player_b: Player
	init_player(&player_b, .B, .Needle, {200, -200})
	g.players[.B] = player_b
	// reset_players(g)

	g.central_star = Star{
		position = {0,0},
		rotation = 0,
		mass = CENTRAL_STAR_MASS,
		rotation_rate = CENTRAL_STAR_ROTATION_RATE,
		radius = CENTRAL_STAR_RADIUS,
	}

	g.central_star_rays = make_central_star_animation_rays(0)

	g.n_rounds = 1

	ps := new(Particle_System)
	ps.thrust_emitters[.Wedge] = make_thrust_emitter()
	ps.thrust_emitters[.Needle] = make_thrust_emitter()
	g.particle_system = ps

	// tmp
	g.scores[.A] = 9

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
	rl.SetTraceLogLevel(RAYLIB_TRACELOGLEVEL)
	rl.InitWindow(WINDOW_W, WINDOW_H, "Spacewar!")
	when ODIN_OS == .Linux {
		rl.SetWindowPosition(10, 125)
	}
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
	// rl.UnloadFileText(mappings)
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




// Global Input ///////////////////////////////////////////////////////////////////////////
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
process_global_input :: proc(gm: ^Game_Memory) {
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
	} else if .Pause in input && gm.scene == .Play {
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




// Play Input //////////////////////////////////////////////////////////////////////////

Play_Input :: enum {
	Thrust,
	Rotate_Left,
	Rotate_Right,
	Fire,
	Hyperspace,
}
Play_Input_Flags :: bit_set[Play_Input]

process_play_input :: proc(gm: ^Game_Memory) {
	input_a, input_b := get_play_input(gm)

	player_a := &gm.players[.A]
	player_a.input = input_a

	player_b := &gm.players[.B]
	player_b.input = input_b
}

get_play_input :: proc(gm: ^Game_Memory) -> (input_a: Play_Input_Flags, input_b: Play_Input_Flags) {
	gamepad_input_a, gamepad_input_b := get_gamepad_inputs()
	input_a = gamepad_input_a
	input_b = gamepad_input_b

	kbd_input_a, kbd_input_b := get_keyboard_inputs()
	input_a += kbd_input_a
	input_b += kbd_input_b

	return input_a, input_b
}

get_keyboard_inputs :: proc() -> (input_a: Play_Input_Flags, input_b: Play_Input_Flags) {
	if rl.IsKeyDown(.S) {
		input_a += {.Thrust}
	}
	if rl.IsKeyDown(.SPACE) {
		input_a += {.Fire}
	}
	if rl.IsKeyDown(.A) {
		input_a += {.Rotate_Left}
	}
	if rl.IsKeyDown(.D) {
		input_a += {.Rotate_Right}
	}
	if rl.IsKeyPressed(.LEFT_SHIFT) {
		input_a += {.Hyperspace}
	}

	if rl.IsKeyDown(.DOWN) {
		input_b += {.Thrust}
	}
	if rl.IsKeyDown(.RIGHT_CONTROL) {
		input_b += {.Fire}
	}
	if rl.IsKeyDown(.LEFT) {
		input_b += {.Rotate_Left}
	}
	if rl.IsKeyDown(.RIGHT) {
		input_b += {.Rotate_Right}
	}
	if rl.IsKeyPressed(.RIGHT_SHIFT) {
		input_b += {.Hyperspace}
	}

	return input_a, input_b
}

GAMEPAD1 :: 0
GAMEPAD2 :: 1
get_gamepad_input :: proc(gamepad_id: i32) -> Play_Input_Flags {
	if gamepad_id == -1 do return {}
	input: Play_Input_Flags
	if rl.IsGamepadButtonDown(gamepad_id, rl.GamepadButton.RIGHT_FACE_DOWN) {
		input += {.Thrust}
	}
	if rl.IsGamepadButtonDown(gamepad_id, rl.GamepadButton.RIGHT_FACE_LEFT) {
		input += {.Fire}
	}
	if rl.IsGamepadButtonDown(gamepad_id, rl.GamepadButton.RIGHT_FACE_RIGHT) {
		input += {.Hyperspace}
	}
	if rl.IsGamepadButtonDown(gamepad_id, rl.GamepadButton.LEFT_FACE_LEFT) {
		input += {.Rotate_Left}
	}
	if rl.IsGamepadButtonDown(gamepad_id, rl.GamepadButton.LEFT_FACE_RIGHT) {
		input += {.Rotate_Right}
	}
	// left stick for rotation, as digital
	left_x := rl.GetGamepadAxisMovement(gamepad_id, rl.GamepadAxis.LEFT_X)
	if left_x < -0.5 do input += {.Rotate_Left}
	if left_x > 0.5 do input += {.Rotate_Right}

	return input
}

get_gamepad_inputs :: proc() -> (gamepad_input_a: Play_Input_Flags, gamepad_input_b: Play_Input_Flags) {
	@(static) detected := false
	@(static) gamepad1: i32 = -1
	@(static) gamepad2: i32 = -1

	// detect & assign
	if !detected {
		for i in 0..<4 {
			if rl.IsGamepadAvailable(i32(i)) {
				name := string(rl.GetGamepadName(i32(i)))
				if is_real_gamepad(name) {
					pr("Found gamepad", i, name)
					if gamepad1 == -1 {
						pr("assigned",name,"to gamepad1")
						gamepad1 = i32(i)
						detected = true
					} else {
						pr("assigned",name,"to gamepad2")
						gamepad2 = i32(i)
					}
					if gamepad1 != -1 && gamepad2 != -1 {
						break

					}
				}
			}
		}
	}

	gamepad_input_a = get_gamepad_input(gamepad1)
	gamepad_input_b = get_gamepad_input(gamepad2)

	return gamepad_input_a, gamepad_input_b
}




// UPDATE PLAY ////////////////////////////////////////////////////////////////////////////////

update_play_scene :: proc(gm: ^Game_Memory, dt: f32) {
	process_play_input(gm)
	update_starfield(gm, dt)
	g.central_star.rotation += g.central_star.rotation_rate * dt

	for &player in gm.players {
		if !player.ship.is_destroyed {
			update_ship(gm, &player.ship, player.input, dt)
		}
	}

	update_torpedos(&gm.torpedos, dt)

	// Collisions

	ship_a := &gm.players[.A].ship
	ship_b := &gm.players[.B].ship

	// ship to ship
	if !ship_a.is_hyperspacing && !ship_b.is_hyperspacing {
		for cc_b in sa.slice(&ship_b.collision_circles) {
			for cc_a in sa.slice(&ship_a.collision_circles) {
				if circle_intersects(cc_a.center + ship_a.position,
									 cc_a.radius,
									 cc_b.center + ship_b.position,
									 cc_b.radius) {
					destroy_ship(gm, ship_a)
					destroy_ship(gm, ship_b)
					start_end_round(gm, nil)
					break
				}
			}
		}
	}

	// torpedo to ship
	torp_collide_outer: for torp in sa.slice(&g.torpedos) {
		if !ship_b.is_hyperspacing {
			for cc_b in sa.slice(&g.players[.B].ship.collision_circles) {
				if circle_intersects(torp.position,
									torp.radius,
									cc_b.center + ship_b.position,
									cc_b.radius) {
					destroy_ship(gm, ship_b)
					start_end_round(gm, .A)
					gm.scores[.A] += 1
					break torp_collide_outer
				}
			}
		}
		if !ship_a.is_hyperspacing {
			for cc_a in sa.slice(&g.players[.A].ship.collision_circles) {
				if circle_intersects(torp.position,
									 torp.radius,
									 cc_a.center + ship_a.position,
									 cc_a.radius) {
					destroy_ship(gm, ship_a)
					start_end_round(gm, .B)
					gm.scores[.B] += 1
					break torp_collide_outer
				}
			}
		}
	}

	// collision with central star
	cs := gm.central_star
	if !ship_b.is_hyperspacing {
		for cc_b in sa.slice(&ship_b.collision_circles) {
			if circle_intersects(cs.position,
								 cs.radius,
								 cc_b.center + ship_b.position,
								 cc_b.radius) {
				destroy_ship(gm, ship_b)
				start_end_round(gm, .A)
				gm.scores[.A] += 1
				break
			}
		}
	}
	if !ship_a.is_hyperspacing {
		for cc_a in sa.slice(&ship_a.collision_circles) {
			if circle_intersects(cs.position,
								 cs.radius,
								 cc_a.center + ship_a.position,
								 cc_a.radius) {
				destroy_ship(gm, ship_a)
				start_end_round(gm, .B)
				gm.scores[.B] += 1
				break
			}
		}
	}

	// Destroy
	torp_indices_to_destroy: sa.Small_Array(MAX_LIVE_TORPEDOS, int)
	for torp, idx in sa.slice(&gm.torpedos) {
		if time.since(torp.creation_time) > torp.lifespan {
			sa.push(&torp_indices_to_destroy, idx)
		}
	}
	for index in sa.slice(&torp_indices_to_destroy) {
		destroy_torpedo(&gm.torpedos, index)
	}
	///////////////////////////////////////////////////////////////////////////////////

	update_particle_system(gm, dt)
}




// SHIP /////////////////////////////////////////////////////////////////////////////

make_ship :: proc(
	ship_type: Ship_Type,
	position: Position = {-50, -50},
	rotation: f32 = 0,
	mass: f32 = SHIP_DEFAULT_MASS,
) -> Ship {
	r: f32
	// collision_circles are relative to ship's position
	collision_circles: Collision_Circles

	switch ship_type {
	case .Wedge:
		r = WEDGE_RADIUS

		cc_r_1 :f32= r * 0.25
		cc_1 := Circle{
			center = { r * 0.85, 0 },
			radius = cc_r_1,
		}
		sa.push(&collision_circles, cc_1)
		cc_r_2: f32 = r * 0.40
		cc_2 := Circle{
			center = { r * 0.25, 0 },
			radius = cc_r_2,
		}
		sa.push(&collision_circles, cc_2)
		cc_r_3: f32 = r * 0.55
		cc_3 := Circle{
			center = { -r * 0.6, 0 },
			radius = cc_r_3,
		}
		sa.push(&collision_circles, cc_3)

	case .Needle:
		r = NEEDLE_RADIUS

		cc_r: f32 = SHIP_DEFAULT_RADIUS * 0.25
		cc_1 := Circle{
			center = { r * 0.8, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_1)
		cc_2 := Circle{
			center = { r * 0.4, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_2)
		cc_3 := Circle{
			center = { 0, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_3)
		cc_4 := Circle{
			center = { r * -0.4, 0 },
			radius = cc_r,
		}
		sa.push(&collision_circles, cc_4)
		cc_5 := Circle{
			center = { r * -0.8  , 0 },
			radius = cc_r * 1.4,
		}
		sa.push(&collision_circles, cc_5)
	}

	return Ship{
		ship_type = ship_type,
		position = position,
		velocity = 0,
		rotation = rotation,
		mass = SHIP_DEFAULT_MASS,
		collision_circles = collision_circles,
		color = SHIP_DEFAULT_COLOR,

		max_fuel = SHIP_DEFAULT_FUEL_MAX,
		fuel = SHIP_DEFAULT_FUEL_MAX,
		torpedo_count = SHIP_DEFAULT_TORPEDO_COUNT,
		hyperspace_count = 0,

		is_thrusting = false,
		is_hyperspacing = false,
		torpedo_cooldown_timer = create_timer(SHIP_DEFAULT_TORPEDO_COOLDOWN),
		hyperspace_duration_timer = create_timer(SHIP_DEFAULT_HYPERSPACE_DURATION),
		hyperspace_cooldown_timer = create_timer(SHIP_DEFAULT_HYPERSPACE_COOLDOWN),
		has_hyperspace_available_sound_played = true,
		r = r,
	}
}

MIN_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO :: 0.2
MAX_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO :: 0.8
find_random_ship_position :: proc() -> (position: Position, angle: f32) {
	w := get_playfield_width()
	r := w / 2
	// dont spawn close to central star
	min_r := r * MIN_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO 
	max_r := r * MAX_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO 

	rng_dir := rand.float32() * math.TAU

	rng_dist := min_r + rand.float32() * (max_r - min_r)

	return Position{rng_dist * math.cos(rng_dir),
					rng_dist * math.sin(rng_dir)}, rng_dir
}

find_opposing_ship_position_random_distance :: proc(other_ship_angle: f32) -> Position {
	// put at: other ship + 180deg +/- 45deg AND some rng_dist
	dir_a := other_ship_angle
	dir_b := dir_a + math.PI + (rand.float32() - 0.5) * math.PI/6
	w := get_playfield_width()
	r := w / 2
	// dont spawn close to central star
	min_r := r * MIN_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO 
	max_r := r * MAX_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO 
	rng_dist := min_r + rand.float32() * (max_r - min_r)

	return Position{rng_dist * math.cos(dir_b),
					rng_dist * math.sin(dir_b)}
}

find_ship_spawn_positions_random_distance :: proc() -> (a: Position, b: Position) {
	pos_a, angle_a := find_random_ship_position()
	pos_b := find_opposing_ship_position_random_distance(angle_a)
	return pos_a, pos_b
}

find_opposing_ship_position_same_distance :: proc(other_ship_position: Position, other_ship_angle: f32) -> Position {
	// put at: other ship + 180deg +/- 45deg AND some rng_dist
	dir_a := other_ship_angle
	dir_b := dir_a + math.PI + (rand.float32() - 0.5) * math.PI/6
	w := get_playfield_width()
	r := w / 2
	// dont spawn close to central star
	min_r := r * MIN_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO 
	max_r := r * MAX_RANDOM_SHIP_SPAWN_RADIUS_WIDTH_RATIO 

	dist := linalg.length(other_ship_position)

	return Position{dist * math.cos(dir_b),
					dist * math.sin(dir_b)}
}

find_ship_spawn_positions_same_distance :: proc() -> (a: Position, b: Position) {
	pos_a, angle_a := find_random_ship_position()
	pos_b := find_opposing_ship_position_same_distance(pos_a, angle_a)
	return pos_a, pos_b
}

get_ship_tail_position :: proc(ship: Ship) -> Position {
	distance := ship.r
	return Vec2{
			math.cos(ship.rotation + math.PI) * distance,
			math.sin(ship.rotation + math.PI) * distance,
		} + ship.position
}

destroy_ship :: proc(gm: ^Game_Memory, ship: ^Ship) {
	ship.is_destroyed = true
	spawn_ship_destruction_emitter(gm.particle_system, ship.position)
	play_sfx(.Ship_Destruction)
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

update_ship :: proc(gm: ^Game_Memory, ship: ^Ship, input: Play_Input_Flags, dt: f32) {
	apply_ship_physics(gm, ship, input, dt)

	ship.position += ship.velocity * dt

	wraparound_spacewar(&ship.position)

	process_timer(&ship.torpedo_cooldown_timer, dt) 
	if .Fire in input {
		if is_timer_done(ship.torpedo_cooldown_timer) {
			if ship.torpedo_count > 0 {
				pos_torpedo := get_torpedo_fire_position(ship^)
				torp_vel := ship.velocity + TORPEDO_SPEED * vec2_from_rotation(ship.rotation)
				ship.torpedo_count -= 1
				spawn_torpedo(gm, pos_torpedo, torp_vel)
				restart_timer(&ship.torpedo_cooldown_timer)

				ship.is_firing = true
				play_sfx(.Fire_Torpedo)
			} else {
				// play empty sound
				play_sfx(.Empty_Fire)
			}
		}
	}

	if ship.is_thrusting {
		if ship.ship_type == .Wedge {
			play_continuous_sfx(.Thruster_Wedge)
		} else {
			play_continuous_sfx(.Thruster_Needle)
		}
	} else {
		if ship.ship_type == .Wedge {
			if is_sfx_playing(.Thruster_Wedge) {
				stop_sfx(.Thruster_Wedge)
			}
		} else {
			if is_sfx_playing(.Thruster_Needle) {
				stop_sfx(.Thruster_Needle)
			}
		}
	}
}

apply_ship_physics :: proc(gm: ^Game_Memory, ship: ^Ship, input: Play_Input_Flags, dt: f32) {
	// Set necessary state here, eg: rendering related
	ship.is_thrusting = false
	ship.is_firing = false

	if !ship.is_hyperspacing {
		if .Rotate_Left in input {
			ship.rotation -= SHIP_DEFAULT_ROTATION_RATE * dt
		} else if .Rotate_Right in input {
			ship.rotation += SHIP_DEFAULT_ROTATION_RATE * dt
		}

		if .Thrust in input {
			heading := Vec2{
				math.cos(ship.rotation),
				math.sin(ship.rotation),
			}

			// make a thrust force vector: rotation vector * thrust_force
			thrust_force := heading * SHIP_DEFAULT_THRUST_FORCE

			// get an accel from: a = thrust_force_vector/ship_mass
			acc := thrust_force / ship.mass

			// apply to vel: vel += accel * dt
			dvel_acc := acc * dt

			ship.velocity += dvel_acc
			ship.is_thrusting = true

			ship.fuel = max(ship.fuel - SHIP_FUEL_BURN_RATE * dt, 0)
		} 

		// Central star gravity
		acc_star := accel_of_gravity(ship.position, gm.central_star.position, gm.central_star.mass)
		dvel_acc_star := acc_star * dt
		ship.velocity += dvel_acc_star
	}

	process_timer(&ship.hyperspace_cooldown_timer, dt)
	if is_timer_done(ship.hyperspace_cooldown_timer) && !ship.has_hyperspace_available_sound_played && !ship.is_hyperspacing {
		play_sfx(.Hyperspace_Ready)
		ship.has_hyperspace_available_sound_played = true
	}

	if .Hyperspace in input && !ship.is_hyperspacing && is_timer_done(ship.hyperspace_cooldown_timer) { 
		restart_timer(&ship.hyperspace_duration_timer)
		ship.is_hyperspacing = true
		ship.hyperspace_count += 1
		ship.has_hyperspace_available_sound_played = false
		ship.hyperspace_count += 1
		play_sfx(.Hyperspace_Entry)
		spawn_hyperspace_emitter(gm.particle_system, ship.position)
	}

	if ship.is_hyperspacing {
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
			play_sfx(.Hyperspace_Exit)
			spawn_hyperspace_emitter(gm.particle_system, ship.position)
		}
	}
}

GRAVITY_COEFFICIENT :: .0000000000667430
GRAVITY_FORCE_MAX :: 1000000000000000
METERS_PER_LOGICAL_UNIT_LENGTH :: 10000000
accel_of_gravity :: proc(pos_ship: Vec2, pos_star: Vec2, mass_other_object: f32) -> Vec2 {
	d_pos := pos_star - pos_ship
	distance := linalg.length(d_pos) * METERS_PER_LOGICAL_UNIT_LENGTH
	magnitude := clamp(GRAVITY_COEFFICIENT * mass_other_object / distance, 0, GRAVITY_FORCE_MAX)
	dir := linalg.normalize0(d_pos)
	accel_vector := magnitude * dir
	return accel_vector
}

WEDGE_RADIUS_FACTOR :: .9
WEDGE_RADIUS :: SHIP_DEFAULT_RADIUS * WEDGE_RADIUS_FACTOR
WEDGE_HALF_BERTH :: WEDGE_RADIUS * 0.25
WEDGE_POINTS_BODY := [?]Vec2{
	{SHIP_DEFAULT_RADIUS, 0},
	{0, -WEDGE_HALF_BERTH},
	{-SHIP_DEFAULT_RADIUS, 0},
	{0, WEDGE_HALF_BERTH},
	{SHIP_DEFAULT_RADIUS, 0},
}

WEDGE_FIN_HALF_BERTH :: WEDGE_HALF_BERTH * 2
WEDGE_FIN_OUTER_EDGE_LENGTH :: SHIP_DEFAULT_RADIUS * 0.45
WEDGE_POINTS_LEFT_FIN := [?]Vec2{
	{-WEDGE_RADIUS * 0.05,				-WEDGE_RADIUS * 0.25},
	{-WEDGE_RADIUS * 0.6,				-WEDGE_FIN_HALF_BERTH},
	{-WEDGE_RADIUS,	-WEDGE_FIN_HALF_BERTH},
	{-WEDGE_RADIUS + 5,	-2},
}

draw_ship_wedge :: proc(ship: Ship) {
	bp := WEDGE_POINTS_BODY
	for i in 0..<len(bp)-1 {
		p1 := rotate_vec2(bp[i], ship.rotation)
		p2 := rotate_vec2(bp[i+1], ship.rotation)
		world_p1 := p1 + ship.position
		world_p2 := p2 + ship.position
		rl.DrawLineV(world_p1, world_p2, ship.color)
	}

	lf := WEDGE_POINTS_LEFT_FIN
	for i in 0..<len(lf)-1 {
		p1 := rotate_vec2(lf[i], ship.rotation)
		p2 := rotate_vec2(lf[i+1], ship.rotation)
		world_p1 := p1 + ship.position
		world_p2 := p2 + ship.position
		rl.DrawLineV(world_p1, world_p2, ship.color)
	}
	// right fin
	for i in 0..<len(lf)-1 {
		o1 := Vec2{lf[i].x, -lf[i].y}
		o2 := Vec2{lf[i+1].x, -lf[i+1].y}
		p1 := rotate_vec2(o1, ship.rotation)
		p2 := rotate_vec2(o2, ship.rotation)
		world_p1 := p1 + ship.position
		world_p2 := p2 + ship.position
		rl.DrawLineV(world_p1, world_p2, ship.color)
	}
}

NEEDLE_RADIUS_FACTOR :: 1.2
NEEDLE_RADIUS :: SHIP_DEFAULT_RADIUS * NEEDLE_RADIUS_FACTOR
NEEDLE_HALF_BERTH :: NEEDLE_RADIUS * .1
NEEDLE_POINTS_BODY := [?]Vec2{
	{NEEDLE_RADIUS,		0},
	{NEEDLE_RADIUS-4,	-NEEDLE_HALF_BERTH},
	{-NEEDLE_RADIUS,	-NEEDLE_HALF_BERTH},
	{-NEEDLE_RADIUS,	NEEDLE_HALF_BERTH},
	{NEEDLE_RADIUS-4,	NEEDLE_HALF_BERTH},
	{NEEDLE_RADIUS,		0},
}

NEEDLE_FIN_HALF_BERTH :: NEEDLE_HALF_BERTH * 2.5
NEEDLE_FIN_OUTER_EDGE_LENGTH :: NEEDLE_RADIUS * 0.35
NEEDLE_POINTS_LEFT_FIN := [?]Vec2{
	{-0.5 * NEEDLE_RADIUS,				-NEEDLE_HALF_BERTH},
	{-0.5 * NEEDLE_RADIUS - 2,			-NEEDLE_FIN_HALF_BERTH},
	{-NEEDLE_RADIUS,					-NEEDLE_FIN_HALF_BERTH},
	{-NEEDLE_RADIUS,					-NEEDLE_HALF_BERTH},
}

draw_ship_needle :: proc(ship: Ship) {
	bp := NEEDLE_POINTS_BODY
	for i in 0..<len(bp)-1 {
		p1 := rotate_vec2(bp[i], ship.rotation)
		p2 := rotate_vec2(bp[i+1], ship.rotation)
		world_p1 := p1 + ship.position
		world_p2 := p2 + ship.position
		rl.DrawLineV(world_p1, world_p2, ship.color)
	}

	lf := NEEDLE_POINTS_LEFT_FIN
	for i in 0..<len(lf)-1 {
		p1 := rotate_vec2(lf[i], ship.rotation)
		p2 := rotate_vec2(lf[i+1], ship.rotation)
		world_p1 := p1 + ship.position
		world_p2 := p2 + ship.position
		rl.DrawLineV(world_p1, world_p2, ship.color)
	}
	// right fin
	for i in 0..<len(lf)-1 {
		o1 := Vec2{lf[i].x, -lf[i].y}
		o2 := Vec2{lf[i+1].x, -lf[i+1].y}
		p1 := rotate_vec2(o1, ship.rotation)
		p2 := rotate_vec2(o2, ship.rotation)
		world_p1 := p1 + ship.position
		world_p2 := p2 + ship.position
		rl.DrawLineV(world_p1, world_p2, ship.color)
	}
}




// TORPEDOS /////////////////////////////////////////////////////////////////////////

make_torpedo :: proc(position: Position, velocity: Vec2) -> Torpedo {
	return Torpedo{
		position = position,
		velocity = velocity,
		lifespan = TORPEDO_LIFESPAN,
		creation_time = time.now(),
		radius = TORPEDO_RADIUS,
	}
}

spawn_torpedo :: proc(gm: ^Game_Memory, position: Position, velocity: Vec2) {
	torp := make_torpedo(position, velocity)
	sa.push(&gm.torpedos, torp)
}

clear_torpedos :: proc(gm: ^Game_Memory) {
	sa.clear(&gm.torpedos)
}

update_torpedos :: proc(torpedos: ^Torpedos, dt: f32) {
	for &torp in sa.slice(torpedos) {
		torp.position += torp.velocity * dt
		wraparound_spacewar(&torp.position)
	}
}

destroy_torpedo :: proc(torpedos: ^Torpedos, index: int) {
	sa.unordered_remove(torpedos, index)
}

TORPEDO_SPACING_FACTOR :: 1.5
get_torpedo_fire_position :: proc(ship: Ship) -> Position {
	distance := ship.r * TORPEDO_SPACING_FACTOR
	return Vec2{
			math.cos(ship.rotation) * distance,
			math.sin(ship.rotation) * distance,
		} + ship.position
}

draw_torpedos :: proc(torps: Torpedos) {
	ts := torps
	for torp in sa.slice(&ts) {
		rl.DrawCircle(i32(torp.position.x), i32(torp.position.y), torp.radius, TORPEDO_COLOR)
	}
}





// STARS ////////////////////////////////////////////////////////////////////////////

STARFIELD_JITTER_NOISE_SCALE_FACTOR :: 0.1
STARFIELD_JITTER_SCALE_FACTOR :: 0.4
STARFIELD_VELOCITY :: Vec2{50,0}
STARFIELD_STAR_BRIGHTNESS_MIN :: 0.2
STARFIELD_STAR_BRIGHTNESS_MAX :: 1.0
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
					{f64(x) * STARFIELD_JITTER_NOISE_SCALE_FACTOR, 
					f64(y) * STARFIELD_JITTER_NOISE_SCALE_FACTOR})
				jitter_noise_y := noise.noise_2d(seed + 2000, 
					{f64(x) * STARFIELD_JITTER_NOISE_SCALE_FACTOR, 
					f64(y) * STARFIELD_JITTER_NOISE_SCALE_FACTOR})

				jitter_x := f32(jitter_noise_x) * sample_resolution * STARFIELD_JITTER_SCALE_FACTOR
				jitter_y := f32(jitter_noise_y) * sample_resolution * STARFIELD_JITTER_SCALE_FACTOR
				pos := Position{math.clamp(x + jitter_x, start_x, start_x + width),
								math.clamp(y + jitter_y, start_y, start_y + height)}
				brightness_val := (noise.noise_2d(seed + 500, noise_coord) + 1) / 2
				star := Starfield_Star{position = pos,
									   color = rl.Color{u8(255 * brightness_val),
													    u8(255 * brightness_val),
														u8(255 * brightness_val),
														u8(255 * brightness_val)}}
				sa.push(starfield_stars, star)
				if sa.len(starfield_stars^) > MAX_STARFIELD_STARS {
					pr("WARN: exceeded max starfield stars of", MAX_STARFIELD_STARS)
					break
				}
			}
		}
	}
	starfield.period = 0.2
	starfield.timer = create_timer(starfield.period)
	starfield.velocity = STARFIELD_VELOCITY
	start_timer(&starfield.timer)
}

update_starfield :: proc(gm: ^Game_Memory, dt: f32) {
	process_timer(&gm.starfield.timer, dt)
	if is_timer_done(gm.starfield.timer) {
		for &star in sa.slice(&gm.starfield.stars) {
			star.position += gm.starfield.velocity * dt
			wraparound_spacewar(&star.position)
		}
		restart_timer(&gm.starfield.timer)
	}
}

draw_starfield :: proc(starfield_stars: Starfield_Stars) {
	sf := starfield_stars
	for star in sa.slice(&sf) {
		rl.DrawCircleV(star.position, 1, star.color)
	}
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

make_central_star_animation_rays :: proc(seed: u64) -> sa.Small_Array(CENTRAL_STAR_RAY_COUNT, Star_Ray) {
	rays: sa.Small_Array(CENTRAL_STAR_RAY_COUNT, Star_Ray)
	for i := 0; i < CENTRAL_STAR_RAY_COUNT; i += 1 {
		ray := Star_Ray{
			angle = rand.float32() * math.TAU,
			length = 10 + rand.float32() * 20,
			phase_offset = rand.float32() * math.TAU,
		}
		sa.push(&rays, ray)
	}
	return rays
}

CENTRAL_STAR_COLOR :: rl.RED
draw_central_star_rays :: proc(central_star: Star, rays: Central_Star_Rays) {
	time := f32(rl.GetTime())
	rays := rays
	for ray in sa.slice(&rays) {
		pulse := math.sin(time * 7 + ray.phase_offset)
		length := ray.length * (.3 + pulse * 0.7)
		x := central_star.position.x + length * math.cos(ray.angle + math.to_radians(central_star.rotation))
		y := central_star.position.y + length * math.sin(ray.angle + math.to_radians(central_star.rotation))
		rl.DrawLine(i32(central_star.position.x),
					i32(central_star.position.y),
					i32(x),
					i32(y),
					CENTRAL_STAR_COLOR)
	}
}




// DRAW /////////////////////////////////////////////////////////////////////////////////

draw_playfield :: proc(gm: Game_Memory) {
	draw_starfield(gm.starfield.stars)

	for player in gm.players {
		if player.ship.is_hyperspacing do continue
		if player.ship.ship_type == .Wedge {
			draw_ship_wedge(player.ship)
		} else if player.ship.ship_type == .Needle {
			draw_ship_needle(player.ship)
		}
	}

	for particle in sa.slice(&gm.particle_system.particles) {
		rl.DrawPixel(i32(particle.position.x), i32(particle.position.y), particle.color)
	}

	draw_central_star_rays(g.central_star, g.central_star_rays)
	draw_torpedos(gm.torpedos)
}

TITLE_BACKGROUND_COLOR :: rl.BLACK
draw_title :: proc(gm: Game_Memory) {
	// draw background overlay
	screen_width := i32(math.round(f32(LOGICAL_SCREEN_WIDTH)))
	screen_height := i32(math.round(f32(LOGICAL_SCREEN_HEIGHT)))
	rl.DrawRectangle(-screen_width/2,
					-screen_height/2,
					screen_width,
					screen_height,
					TITLE_BACKGROUND_COLOR)

	// draw title
	// TODO: magic numbers
	{
		fs :i32= 92
		title := "Spacewar!"
		x := get_centered_text_x_coord(title, fs, 0)
		y := i32(get_screen_top() + 25)
		rl.DrawText(strings.clone_to_cstring(title, context.temp_allocator), x, y, fs, rl.RED)
	}

	// draw wedge and needle controls
	{
		x: i32 = i32(get_screen_left()) + 50
		y: i32 = i32(get_screen_top() + 200)

		arr := [?]string{
			fmt.tprintf("Wedge Controls:"),
			fmt.tprintf("Rotate: A/D or Gamepad Joystick/D-pad"),
			fmt.tprintf("Thrust: S or Gamepad A"),
			fmt.tprintf("Fire: Space or Gamepad X"),
			fmt.tprintf("Hyperspace: Left-Shift or Gamepad B"),
			fmt.tprintf(""),
			fmt.tprintf("Needle Controls:"),
			fmt.tprintf("Rotate: Left/Right or Gamepad Joystick/D-pad"),
			fmt.tprintf("Thrust: Down or Gamepad A"),
			fmt.tprintf("Fire: Right-Control or Gamepad X"),
			fmt.tprintf("Hyperspace: Right-Shift or Gamepad B"),
		}
		debug_overlay_text_column(&x, &y, arr[:], 32, 48)
	}
	{
		y: i32 = i32(get_screen_bottom()) - 300
		bottom_text := fmt.tprintf("First to 10 wins")
		x := get_centered_text_x_coord(bottom_text, 72, 0)

		cstr := fmt.ctprint(bottom_text)
		rl.DrawText(cstr, x, y, 72, rl.YELLOW)

		start_text := fmt.tprintf("Press Enter to start!")
		x2 := get_centered_text_x_coord(start_text, 72, 0)
		y += 120

		cstr2 := fmt.ctprint(start_text)
		rl.DrawText(cstr2, x2, y, 72, rl.RED)
	}
}



// Rounds and Match ///////////////////////////////////////////////////////////////////////

start_end_match :: proc(gm: ^Game_Memory) {
	gm.scene = .End_Match
	match_winner :Player_ID= gm.scores[.A] > gm.scores[.B] ? .A : .B
	gm.end_match_display = fmt.aprintf("%v wins the match!", gm.players[match_winner].ship.ship_type)
	play_sfx(.Game_Over)
	start_timer(&gm.end_match_duration_timer)
}

start_end_round :: proc(gm: ^Game_Memory, winner: Maybe(Player_ID)) {
	gm.n_rounds += 1
	gm.scene = .End_Round

	// reset ship state, (avoid "hanging" sounds and animations)
	for &player in gm.players {
		ship := &player.ship
		ship.is_thrusting = false
		ship.is_hyperspacing = false
		ship.is_firing = false
	}

	if winner, ok := winner.?; ok {
		ship_name := gm.players[winner].ship.ship_type
		gm.end_round_display = fmt.aprintf("%v wins the round!", ship_name)
	} else {
		gm.end_round_display = fmt.aprintf("Both ships were destroyed!")
	}

	start_timer(&gm.end_round_duration_timer)
}

reset_end_round_state :: proc(gm: ^Game_Memory) {
	reset_timer(&g.end_round_duration_timer)
	g.end_round_display = ""
	g.has_end_round_mid_action_played = false
}

reset_end_match_state :: proc(gm: ^Game_Memory) {
	reset_timer(&g.end_match_duration_timer)
	g.end_match_display = ""
}

end_match_condition :: proc(gm: ^Game_Memory) -> bool {
	return gm.scores[.A] == 10 || gm.scores[.B] == 10
}

END_ROUND_FONT_SIZE :: 48
END_ROUND_TEXT_COLOR :: rl.BLUE
END_ROUND_TEXT_OFFSET_Y :: -96
draw_end_round :: proc(gm: Game_Memory) {
	x := get_centered_text_x_coord(gm.end_round_display, END_ROUND_FONT_SIZE, i32(get_playfield_left() + get_playfield_width() / 2))
	cstr := fmt.ctprintf(gm.end_round_display)
	y := get_playfield_top() + get_playfield_height() / 2 + END_ROUND_TEXT_OFFSET_Y
	rl.DrawText(cstr, i32(x), i32(y), END_ROUND_FONT_SIZE, END_ROUND_TEXT_COLOR )
}

END_MATCH_TEXT_COLOR :: rl.YELLOW
END_MATCH_TEXT_Y_OFFSET :: 16
draw_end_match :: proc(gm: Game_Memory) {
	x := get_centered_text_x_coord(gm.end_match_display, END_ROUND_FONT_SIZE, i32(get_playfield_left() + get_playfield_width() / 2))
	y := get_playfield_top() + get_playfield_height() / 2 + END_MATCH_TEXT_Y_OFFSET
	cstr := fmt.ctprintf(gm.end_match_display)
	rl.DrawText(cstr, i32(x), i32(y), END_ROUND_FONT_SIZE, END_MATCH_TEXT_COLOR )
}

FUEL_BAR_FILL_COLOR :: rl.GREEN
FUEL_BAR_BORDER_COLOR :: rl.WHITE
FUEL_BAR_LABEL_COLOR :: rl.WHITE
HYPERSPACE_BAR_FILL_COLOR :: rl.SKYBLUE
HYPERSPACE_BAR_BORDER_COLOR :: rl.WHITE
HYPERSPACE_BAR_LABEL_COLOR :: rl.WHITE
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

	fs: i32 : 20
	gap_x: i32 : 25
	gap_y: i32 : 20
	draw_player_display :: proc(ship: Ship, x0, y0: i32, fs: i32, gap_x: i32) {
		gap_y: i32 : 20

		x := x0
		y := y0
		draw_progress_bar(f32(x), f32(y),
						  200, 18,
						  ship.fuel/ship.max_fuel,
						  rl.RED, rl.WHITE,
						  "FUEL", FUEL_BAR_LABEL_COLOR, nil)

		hyperspace_cd_pct := get_timer_progress(ship.hyperspace_cooldown_timer)
		draw_progress_bar(f32(x), f32(y+gap_y+3), 
						  200, 16, 
						  hyperspace_cd_pct, 
						  HYPERSPACE_BAR_FILL_COLOR, HYPERSPACE_BAR_BORDER_COLOR, 
						  "HYPERSPACE", HYPERSPACE_BAR_LABEL_COLOR, nil)

		x += 200 + gap_x
		torp_display := fmt.ctprintf("torpedos x%v", ship.torpedo_count)
		rl.DrawText(torp_display, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		// hyperspace_count_display := fmt.ctprintf("hspace jumps: %v", ship.hyperspace_count)
		// rl.DrawText(hyperspace_count_display, x, y + gap_y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
	}

	draw_player_display(gm.players[.A].ship,
						i32(get_screen_left()) + 10,
						i32(get_screen_top()) + 5,
						fs, gap_x)
	draw_player_display(gm.players[.B].ship,
						i32(get_screen_right()) - 400,
						i32(get_screen_top()) + 5,
						fs, gap_x)

	{
		x: i32 = i32(get_screen_left()) + i32((get_screen_right() - get_screen_left()) / 2) - 150
		y: i32 = i32(get_screen_top()) + 5
		score_display := fmt.ctprintf("%v - %v", g.scores[.A], g.scores[.B])
		rl.DrawText(score_display, x + 100, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
	}
}




// INIT ////////////////////////////////////////////////////////////////////////////////////////

init_player :: proc(p: ^Player, player_id: Player_ID, ship_type: Ship_Type, position: Position = {}, rotation: f32 = 0) {
	p.ship = make_ship(ship_type, position, rotation)
	p.id = player_id
	clear_timer(&p.ship.torpedo_cooldown_timer)
	clear_timer(&p.ship.hyperspace_cooldown_timer)
}




// MISC ///////////////////////////////////////////////////////////////////////////

reset_players :: proc(gm: ^Game_Memory) {
	// pos_a, pos_b := find_ship_spawn_positions_random_distance()
	pos_a, pos_b := find_ship_spawn_positions_same_distance()
	rng_dir1 := rand.float32() * math.TAU
	rng_dir2 := rand.float32() * math.TAU
	init_player(&gm.players[.A], .A, .Wedge, pos_a, rng_dir1)
	init_player(&gm.players[.B], .B, .Needle, pos_b, rng_dir2)
}

reset_playfield_objects :: proc(gm: ^Game_Memory) {
	reset_players(gm)
	clear_torpedos(gm)
	clear_particle_system(gm)
}

wraparound_spacewar :: proc(position: ^Position) {
	wraparound(position, 
			   get_playfield_left(),
			   get_playfield_right(),
			   get_playfield_top(),
			   get_playfield_bottom())

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
	return PLAYFIELD_LENGTH
}
