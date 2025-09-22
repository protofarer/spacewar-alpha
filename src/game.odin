package game

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:strings"
import "core:math"
import "core:time"
import "core:math/noise"
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

GRAVITY_COEFFICIENT :: .0000000000667430
GRAVITY_FORCE_MAX :: 1000000000000000

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

Player_ID :: enum {A,B}

SHIP_TORPEDO_INITIAL_COUNT :: 32
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

	starfield: Starfield,
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

	fuel_count: i32,
	torpedo_count: i32,
	hyperspace_count: i32,

	is_thrusting: bool,
	is_hyperspacing: bool,
	is_firing: bool,

	rotating: Maybe(Ship_Rotation_Direction),
	torpedo_cooldown_timer: Timer,

	is_destroyed: bool,
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

		fuel_count = SHIP_DEFAULT_FUEL_COUNT,
		torpedo_count = SHIP_DEFAULT_TORPEDO_COUNT,
		hyperspace_count = 0,

		is_thrusting = false,
		rotating = nil,
		is_hyperspacing = false,
		torpedo_cooldown_timer = create_timer(SHIP_DEFAULT_TORPEDO_COOLDOWN)
	}
}

g: ^Game_Memory

reset_players :: proc(gm: ^Game_Memory) {
	init_player(&gm.players[.A], .Wedge, {-50, -50})
	init_player(&gm.players[.B], .Needle, {50, -50})
}

clear_torpedos :: proc(gm: ^Game_Memory) {
	sa.clear(&gm.torpedos)
}

// TODO: delay before ending round -> let animations play out
end_round :: proc(gm: ^Game_Memory) {
	reset_players(gm)
	clear_torpedos(gm)
	gm.n_rounds += 1
}

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
		update_play_scene(g, dt)
	case:
	}

	// update_central_star
	g.central_star.rotation += g.central_star.rotation_rate * dt
}

update_play_scene :: proc(gm: ^Game_Memory, dt: f32) {
	scene := gm.scene.(Play_Scene)
	process_play_input(&scene)

	// update starfield
	process_timer(&gm.starfield.timer, dt)
	if is_timer_done(gm.starfield.timer) {
		for &star in sa.slice(&gm.starfield.stars) {
			star.position += gm.starfield.velocity * dt
			wraparound(&star.position)
		}
		restart_timer(&gm.starfield.timer)
	}

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
			destroy_ship(&gm.players[.A].ship)
			destroy_ship(&gm.players[.B].ship)
			end_round(gm)
			break
		}
	}
	//
	// // torpedo to ship
	torp_collide_outer: for torp in sa.slice(&g.torpedos) {
		for cc_b in sa.slice(&g.players[.B].ship.collision_circles) {
			if circle_intersects(torp.position, torp.radius, cc_b.center + ship_b.position, cc_b.radius) {
				destroy_ship(&gm.players[.B].ship)
				end_round(gm)
				gm.scores[.A] += 1
				break torp_collide_outer
			}
		}
		if circle_intersects(torp.position, torp.radius, cc_a.center + ship_a.position, cc_a.radius) {
			destroy_ship(&gm.players[.A].ship)
			end_round(gm)
			gm.scores[.B] += 1
			break torp_collide_outer
		}
	}

	// Destroy and cleanup
	torp_indices_to_destroy: sa.Small_Array(MAX_LIVE_TORPEDOS, int)
	for index in sa.slice(&torp_indices_to_destroy) {
		destroy_torpedo(&gm.torpedos, index)
	}

	if should_game_over() {
		unreachable()
		// next_scene = Game_Over_Scene{}
	}
}

destroy_ship :: proc(ship: ^Ship) {
	// TODO: ship explode animation
	ship.is_destroyed = true
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

get_nose_position :: proc(ship: Ship) -> Position {
	SHIP_NEEDLE_RADIUS_FACTOR :: 1.5
	SHIP_WEDGE_RADIUS_FACTOR :: 1.25
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

draw_topbar :: proc() {
	topbar_width := i32(math.round(f32(LOGICAL_SCREEN_WIDTH)))
	topbar_height := i32(math.round(f32(TOPBAR_HEIGHT)))
	screen_width := i32(math.round(f32(LOGICAL_SCREEN_WIDTH)))
	screen_height := i32(math.round(f32(LOGICAL_SCREEN_HEIGHT)))
	rl.DrawRectangle(-screen_width/2,
					-screen_height/2,
					topbar_width,
					topbar_height,
					TOPBAR_COLOR)

}
draw_debug_origin_axes :: proc() {
	rl.DrawLine(i32(get_playfield_left()), 0, i32(get_playfield_right()), 0, rl.BLUE)
	rl.DrawLine(0, i32(get_playfield_top()), 0, i32(get_playfield_bottom()), rl.BLUE)
}

draw_torpedos :: proc(torps: []Torpedo) {
	for torp in torps {
		rl.DrawCircle(i32(torp.position.x), i32(torp.position.y), torp.radius, TORPEDO_COLOR)
	}
}

draw_starfield :: proc(starfield_stars: Starfield_Stars) {
	sf := starfield_stars
	for star in sa.slice(&sf) {
		rl.DrawCircleV(star.position, 1, star.color)
	}
}

draw :: proc() {
	begin_letterbox_rendering()

	switch &s in g.scene {
	case Play_Scene:
		draw_starfield(g.starfield.stars)
		for player in g.players {
			if player.ship.ship_type == .Wedge {
				draw_ship_wedge(player.ship)
			} else if player.ship.ship_type == .Needle {
				draw_ship_needle(player.ship)
			}
		}

		draw_topbar()
		// draw_star(g.central_star)

		draw_torpedos(sa.slice(&g.torpedos))

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
	}

	// ui text
	rl.DrawText(fmt.ctprintf(""), 5, 5, 8, rl.BLUE)

	fs: i32 = 20
	gap_x: i32 = 25
	{
		// player a
		ship := g.players[.A].ship
		x: i32 = i32(get_screen_left()) + 10
		y: i32 = i32(get_screen_top()) + 5

		torp_count := fmt.ctprintf("torpedos: %v", ship.torpedo_count)
		rl.DrawText(torp_count, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		x += rl.MeasureText(torp_count, fs) + gap_x
		fuel_count := fmt.ctprintf("fuel: %v%%", ship.fuel_count)
		rl.DrawText(fuel_count, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
	}

	{
		// player b
		ship := g.players[.B].ship
		x: i32 = i32(get_screen_right()) - 300
		y: i32 = i32(get_screen_top()) + 5

		torp_count := fmt.ctprintf("torpedos: %v", ship.torpedo_count)
		rl.DrawText(torp_count, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)

		x += rl.MeasureText(torp_count, fs) + gap_x
		fuel_count := fmt.ctprintf("fuel: %v%%", ship.fuel_count)
		rl.DrawText(fuel_count, x, y, fs, TOPBAR_DEFAULT_TEXT_COLOR)
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
	init_starfield(&starfield, seed, get_playfield_left(), get_playfield_top(), PLAYFIELD_LENGTH, PLAYFIELD_LENGTH, sample_resolution, star_threshold, noise_scale)

	g^ = Game_Memory {
		resman = resman,
		audman = audman,
		render_texture = rl.LoadRenderTexture(LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE, LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE),
		app_state = .Running,
		debug = true,
		starfield = starfield,
	}
	return true
}

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
				JITTER_NOISE_SCALE_FACTOR :: 0.1
				JITTER_SCALE_FACTOR :: 0.4
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
	pr("starfield count", sa.len(starfield_stars^))
}

// clear collections, set initial values
init :: proc() -> bool {
	if g == nil {
		log.error("Failed to initialize app state, Game_Memory nil")
		return false
	}
	g.scene = Play_Scene{}

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

	// test that playfield width and height are same
	// w := get_playfield_right() - get_playfield_left()
	// h := get_playfield_bottom() - get_playfield_top()
	// pr("playfield w", w)
	// pr("playfield h", h)
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

process_play_input :: proc(s: ^Play_Scene) {
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

	player.ship.is_firing = false
	if .Fire in input {
		player.ship.is_firing = true
	}
}

apply_ship_physics :: proc(ship: ^Ship, dt: f32) {
	if rotation, rotation_ok := ship.rotating.?; rotation_ok {
		if rotation == .Left {
			ship.rotation -= SHIP_DEFAULT_ROTATION_RATE * dt
		} else {
			ship.rotation += SHIP_DEFAULT_ROTATION_RATE * dt
		}
	}

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
				fmt.tprintf("fuel_count: %v", ship.fuel_count),
				fmt.tprintf("torp_count: %v", ship.torpedo_count),
				fmt.tprintf("hyperspace_count: %v", ship.hyperspace_count),
				fmt.tprintf("is_thrusting: %v", ship.is_thrusting),
				fmt.tprintf("is_firing: %v", ship.is_firing),
				fmt.tprintf("rotating: %v", ship.rotating),
				fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
				fmt.tprintf("is_destroyed: %v", ship.is_destroyed),
			}
			debug_overlay_text_column(&x, &y, arr[:])
		}
		{
			ship := g.players[.B].ship
			x: i32 = 5
			y: i32 = 400

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
				fmt.tprintf("rotating: %v", ship.rotating),
				fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
				fmt.tprintf("is_destroyed: %v", ship.is_destroyed),
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
	if ship.is_firing {
		if is_timer_done(ship.torpedo_cooldown_timer) {
			pos_nose := get_nose_position(ship^)
			torp_vel := ship.velocity + TORPEDO_SPEED * vector_from_rotation(ship.rotation)
			pr("pos nose", pos_nose)
			spawn_torpedo(gm, pos_nose, torp_vel)
			restart_timer(&ship.torpedo_cooldown_timer)
		}
	}
}

vector_from_rotation :: proc(rot: f32) -> Vec2 {
	return Vec2{
		math.cos(rot),
		math.sin(rot)
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
