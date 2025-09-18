package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:strings"
import "core:math"
import sa "core:container/small_array"
import rl "vendor:raylib"

pr :: fmt.println
prf :: fmt.printfln

Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Position :: Vec2
Rect :: rl.Rectangle

LOGICAL_SCREEN_HEIGHT :: 1080
LOGICAL_SCREEN_WIDTH :: 1080
RENDER_TEXTURE_SCALE :: 1

WINDOW_W :: 1080
WINDOW_H :: 1080
TICK_RATE :: 120

BACKGROUND_COLOR :: rl.BLACK

Player_ID :: enum {A,B}

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
}

Star :: struct {
	position: Position,
	mass: f32,
}

App_State :: enum {
	Running,
	Exit
}

Scene :: union {
	// Menu_Scene,
	Play_Scene,
	// Game_Over_Scene,
}

Play_Scene :: struct {
}

should_game_over :: proc() -> bool {
	return false
}

Entity :: struct {
	pos: Position,
	size: Vec2,
	rotation: f32,
	color: rl.Color,
}

Player :: struct {
	id: Player_ID,
	ship: Ship
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

	fuel_remaining: i32,
	torpedoes_remaining: i32,
	hyperspace_count: i32,

	is_thrusting: bool,
	rotating: Maybe(Ship_Rotation_Direction),
	is_hyperspacing: bool,
}

SHIP_DEFAULT_MASS :: 100
SHIP_DEFAULT_RADIUS :: 20
SHIP_DEFAULT_COLOR :: rl.WHITE
SHIP_DEFAULT_FUEL_COUNT :: 100
SHIP_DEFAULT_TORPEDO_COUNT :: 32
SHIP_NEEDLE_COLLISION_CIRCLE_RADIUS :: 5
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
		cc_r :f32= SHIP_DEFAULT_RADIUS * 0.20
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

		fuel_remaining = SHIP_DEFAULT_FUEL_COUNT,
		torpedoes_remaining = SHIP_DEFAULT_TORPEDO_COUNT,
		hyperspace_count = 0,

		is_thrusting = false,
		rotating = nil,
		is_hyperspacing = false,
	}
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
	switch &s in g.scene {
	case Play_Scene:
		process_play_input(&s)
		for &player in g.players {
			apply_ship_physics(&player.ship, dt)
			apply_star_physics(&player.ship, g.central_star, dt)
			player.ship.position.x += player.ship.velocity.x * dt
			player.ship.position.y += player.ship.velocity.y * dt
		}
		if should_game_over() {
			unreachable()
			// next_scene = Game_Over_Scene{}
		}
	case:
	}
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
	STAR_RADIUS :: 20
	star_pos := star.position
	{
		p1 := Vec2{
			star_pos.x + STAR_RADIUS,
			star_pos.y,
		}
		p2 := Vec2{
			star_pos.x + STAR_RADIUS * math.cos(math.to_radians(f32(120))),
			star_pos.y + STAR_RADIUS * math.sin(math.to_radians(f32(120))),
		}
		p3 := Vec2{
			star_pos.x + STAR_RADIUS * math.cos(math.to_radians(f32(240))),
			star_pos.y + STAR_RADIUS * math.sin(math.to_radians(f32(240))),
		}
		rl.DrawTriangleLines(p1,p2,p3,rl.PURPLE)
	}
	{
		p1 := Vec2{
			star_pos.x - STAR_RADIUS,
			star_pos.y,
		}
		p2 := Vec2{
			star_pos.x + STAR_RADIUS * math.cos(math.to_radians(f32(180 - 120))),
			star_pos.y + STAR_RADIUS * math.sin(math.to_radians(f32(180 - 120))),
		}
		p3 := Vec2{
			star_pos.x + STAR_RADIUS * math.cos(math.to_radians(f32(180 - 240))),
			star_pos.y + STAR_RADIUS * math.sin(math.to_radians(f32(180 - 240))),
		}
		rl.DrawTriangleLines(p1,p2,p3,rl.PURPLE)
	}
}

draw :: proc() {
	begin_letterbox_rendering()

	switch &s in g.scene {
	case Play_Scene:
		for player in g.players {
			if player.ship.ship_type == .Wedge {
				draw_ship_wedge(player.ship)
			} else if player.ship.ship_type == .Needle {
				draw_ship_needle(player.ship)
			}
		}


		draw_star(g.central_star)
		if g.debug {
			// origin lines
			rl.DrawLine(-WINDOW_W/2, 0, WINDOW_W/2, 0, rl.BLUE)
			rl.DrawLine(0, -WINDOW_H/2, 0, WINDOW_H/2, rl.BLUE)

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
	}

	rl.DrawText(fmt.ctprintf("UI TEXT"), 5, 5, 8, rl.BLUE)

	end_letterbox_rendering()

	if g.debug {
		draw_debug_overlay() // outside of render texture scaling
	}

	rl.EndDrawing()
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

	g^ = Game_Memory {
		resman = resman,
		audman = audman,
		render_texture = rl.LoadRenderTexture(LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE),
		app_state = .Running,
		debug = true,
	}
	return true
}

// clear collections, set initial values
init :: proc() {
	if g == nil {
		log.error("Failed to initialize app state, Game_Memory nil")
		// TODO: is return correct op?
		return
	}
	g.scene = Play_Scene{}

	player_a: Player
	init_player(&player_a, .Wedge, {-100, -100})
	player_a.id = .A
	g.players[.A] = player_a

	player_b: Player
	init_player(&player_b, .Needle, {-100, -100})
	player_b.id = .B
	g.players[.B] = player_b

	g.central_star = Star{
		position = {0,0},
		mass = 1000,
	}
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
	rl.InitWindow(WINDOW_W, WINDOW_H, "Odin Gamejam Template")
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
	init() // run after setup, then on game reset
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
}

GLOBAL_INPUT_LOOKUP := [Global_Input]rl.KeyboardKey{
	.Toggle_Debug = .GRAVE,
	.Exit = .ESCAPE,
	.Exit2 = .Q,
	.Reset = .R,
	.Pause = .P,
}

process_global_input :: proc() {
	input: bit_set[Global_Input]
	for key, input_ in GLOBAL_INPUT_LOOKUP {
		switch input_ {
		case .Toggle_Debug, .Exit, .Exit2, .Reset, .Pause:
			if rl.IsKeyPressed(key) {
				input += {input_}
			}
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

// PLAY_INPUT_LOOKUP := [Play_Input][]rl.KeyboardKey{
// 	.Thrust = {.DOWN, .S},
// 	.Rotate_Left = {.LEFT, .A},
// 	.Rotate_Right = {.RIGHT, .D},
// 	.Fire = {.UP, .W},
// 	.Hyperspace = {.SPACE},
// }

process_play_input :: proc(s: ^Play_Scene) {
	input: bit_set[Play_Input]

	if rl.IsKeyDown(.S) {
		input += {.Thrust}
	}
	if rl.IsKeyPressed(.W) {
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

	player := &g.players[.A]

	// Set necessary state here, including for render
	player.ship.is_thrusting = false
	if .Thrust in input {
		player.ship.is_thrusting = true
	}

	player.ship.rotating = nil
	if .Rotate_Left in input {
		player.ship.rotating = .Left
	} 
	if .Rotate_Right in input {
		player.ship.rotating = .Right
	}

	if .Hyperspace in input {
		player.ship.is_hyperspacing = true
	}
	if .Fire in input {
		// TODO: create torpedo
	}
}

apply_ship_physics :: proc(ship: ^Ship, dt: f32) {
	SHIP_DEFAULT_ROTATION_RATE :: 10
	if rotation, rotation_ok := ship.rotating.?; rotation_ok {
		if rotation == .Left {
			ship.rotation -= SHIP_DEFAULT_ROTATION_RATE * dt
		} else {
			ship.rotation += SHIP_DEFAULT_ROTATION_RATE * dt
		}
	}

	SHIP_DEFAULT_THRUST_FORCE :: 10000
	if ship.is_thrusting == true {
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
	}
}

// TODO: lookup coeff, then tweak star mass
GRAVITY_COEFFICIENT :: 10
GRAVITY_FORCE_MAX :: 100000
force_of_gravity :: proc(pos_ship: Vec2, pos_star: Vec2, mass_ship: f32, mass_star: f32) -> Vec2 {
	d_pos := pos_star - pos_ship
	distance := linalg.length(d_pos)
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

aabb_intersects :: proc(a_x, a_y, a_w, a_h: f32, b_x, b_y, b_w, b_h: f32) -> bool {
    return !(a_x + a_w < b_x ||
           b_x + b_w < a_x ||
           a_y + a_h < b_y ||
           b_y + b_h < a_y)
}

circle_intersects:: proc(a_pos: Vec2, a_radius: f32, b_pos: Vec2, b_radius: f32) -> bool {
	return linalg.length2(a_pos - b_pos) < (a_radius + b_radius) * (a_radius + b_radius)
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

			arr := [?]string{
				fmt.tprintf("A"),
				fmt.tprintf("vel: %v", ship.velocity),
				fmt.tprintf("pos: %v", ship.position),
				fmt.tprintf("rot: %v", math.to_degrees(ship.rotation)),
				fmt.tprintf("mass: %v", ship.mass),
				fmt.tprintf("fuel_count: %v", ship.fuel_remaining),
				fmt.tprintf("torp_count: %v", ship.torpedoes_remaining),
				fmt.tprintf("hyperspace_count: %v", ship.hyperspace_count),
				fmt.tprintf("is_thrusting: %v", ship.is_thrusting),
				fmt.tprintf("rotating: %v", ship.rotating),
				fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
			}
			debug_overlay_text_column(&x, &y, arr[:])
		}
		{
			ship := g.players[.B].ship
			x: i32 = 5
			y: i32 = 300

			arr := [?]string{
				fmt.tprintf("B"),
				fmt.tprintf("vel: %v", ship.velocity),
				fmt.tprintf("pos: %v", ship.position),
				fmt.tprintf("rot: %v", math.to_degrees(ship.rotation)),
				fmt.tprintf("mass: %v", ship.mass),
				fmt.tprintf("fuel_count: %v", ship.fuel_remaining),
				fmt.tprintf("torp_count: %v", ship.torpedoes_remaining),
				fmt.tprintf("hyperspace_count: %v", ship.hyperspace_count),
				fmt.tprintf("is_thrusting: %v", ship.is_thrusting),
				fmt.tprintf("rotating: %v", ship.rotating),
				fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
			}
			debug_overlay_text_column(&x, &y, arr[:])
		}

	}
}
