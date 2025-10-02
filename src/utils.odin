package game

import rl "vendor:raylib"
import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/linalg"

pr :: fmt.println
Void :: struct{}
Vec2 :: [2]f32
Vec2i :: [2]i32
Rect :: rl.Rectangle

// Wraps os.read_entire_file and os.write_entire_file, but they also work with emscripten.
@(require_results)
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	return _read_entire_file(name, allocator, loc)
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return _write_entire_file(name, data, truncate)
}

pr_span :: proc(msg: Maybe(string) = nil) {
	if txt, ok := msg.?; ok {
		fmt.println("-----------------------", txt , "-----------------------")
	} else {
		fmt.println("----------------------------------------------")
	}
}

vec2_from_vec2i :: proc(v: Vec2i) -> Vec2 {
    return Vec2{f32(v.x), f32(v.y)}
}

vec2i_from_vec2 :: proc(v: Vec2) -> Vec2i {
    return Vec2i{i32(v.x), i32(v.y)}
}

rotate_vec2 :: proc(v: Vec2, angle: f32) -> Vec2 {
	rot_matrix := linalg.matrix2_rotate(angle)
	result := rot_matrix * v
	return result
}

vec2_from_rotation :: proc(rot: f32) -> Vec2 {
	return Vec2{math.cos(rot),
				math.sin(rot)}
}

is_set_fully_flagged :: proc(set: bit_set[$E]) -> bool {
    return card(set) == len(E)
}

circle_intersects:: proc(a_pos: Vec2, a_radius: f32, b_pos: Vec2, b_radius: f32) -> bool {
	return linalg.length2(a_pos - b_pos) < (a_radius + b_radius) * (a_radius + b_radius)
}

wraparound :: proc(position: ^Position, left,right,top,bottom: f32) {
	if position.x < left {
		position.x = right
	} else if position.x > right {
		position.x = left
	}
	if position.y < top {
		position.y = bottom
	} else if position.y > bottom {
		position.y = top
	}
}

get_centered_text_x_coord :: proc(text: string, font_size: i32, x_center: i32) -> i32 {
	cstr := fmt.ctprintf(text)
	text_length := rl.MeasureText(cstr, font_size)
	x := x_center - i32(f32(text_length) / 2)
	return x
}

draw_progress_bar :: proc(
	x,y,w,h: f32, 
	fill_pct: f32, 
	fill_color: rl.Color, border_color: Maybe(rl.Color), 
	label: Maybe(string), label_color: Maybe(rl.Color), label_font_size: Maybe(i32),
) {
	DEFAULT_LABEL_COLOR :: rl.WHITE
	DEFAULT_BORDER_THICKNESS :: 1
	if fill_pct > 1 || fill_pct < 0 {
		pr("ERROR, invalid fill_pct, must be 0 <= x <= 1:", fill_pct)
	}
	if bc, ok := border_color.?; ok {
		rect_border := Rect{f32(x), f32(y), f32(w), h}
		rect_fill := Rect{f32(x+1), f32(y+1), (w-2) * fill_pct, h-2}
		rl.DrawRectangleLinesEx(rect_border, DEFAULT_BORDER_THICKNESS, bc)
		rl.DrawRectangleRec(rect_fill, fill_color)
	}  else {
		rect_fill := Rect{f32(x), f32(y), (w) * fill_pct, h}
		rl.DrawRectangleRec(rect_fill, fill_color)
	}
	if lab, ok := label.?; ok {
		fs: i32
		if param_font_size, ok_font_size := label_font_size.?; ok_font_size {
			fs = param_font_size
		} else {
			fs = i32(h)
		}
		x_label := get_centered_text_x_coord(lab, fs, i32(x + w/2))
		if lab_col, ok_lab_col := label_color.?; ok_lab_col {
			rl.DrawText(fmt.ctprint(lab), i32(x_label), i32(y), fs, lab_col)
		} else {
			rl.DrawText(fmt.ctprint(lab), i32(x_label), i32(y), fs, DEFAULT_LABEL_COLOR)
		}
	}
}

// Letterboxing and viewport
LETTERBOX_COLOR :: rl.DARKGRAY
get_viewport_scale :: proc() -> f32 {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	scale := min(window_w / LOGICAL_SCREEN_WIDTH, window_h / LOGICAL_SCREEN_HEIGHT)
	return scale
}

get_viewport_size :: proc() -> (width, height: f32) {
	scale := get_viewport_scale()
	width = LOGICAL_SCREEN_WIDTH * scale
	height = LOGICAL_SCREEN_HEIGHT * scale
	return width, height
}

get_viewport_offset :: proc() -> (f32,f32) {
	window_w := f32(rl.GetScreenWidth())
	window_h := f32(rl.GetScreenHeight())
	viewport_width, viewport_height := get_viewport_size()
	off_x := -(window_w - viewport_width) / 2
	off_y := -(window_h - viewport_height) / 2
	return off_x, off_y
}

update_mouse_transform :: proc() {
	offx, offy := get_viewport_offset()
	scale := get_viewport_scale()
	rl.SetMouseOffset(i32(offx), i32(offy))
	rl.SetMouseScale(1/scale, 1/scale)
}
	
get_render_rects :: proc() -> (src: Rect, dst: Rect){
	viewport_width, viewport_height := get_viewport_size()
	offset_x, offset_y := get_viewport_offset()
	
	// Draw the render texture with letterboxing
	render_texture_width: f32 = LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE
	render_texture_height: f32 = LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE
	src = Rect{0, 0, render_texture_width, -render_texture_height} // negative height flips texture
	dst = Rect{-offset_x, -offset_y, viewport_width, viewport_height}
	return src, dst
}

is_real_gamepad :: proc(name: string) -> bool {
	keyboard_patterns := [?]string{
		"keyboard", "keychron", "ducky", "anne pro", "hhkb", "ergodox", "kinesis",
	}
	lower_name := strings.to_lower(name)
	for pattern in keyboard_patterns {
		if strings.contains(lower_name, pattern) {
			return false
		}
	}
	return true
}

// debug utils //////////////////////////////

debug_overlay_text_column :: proc(x,y: ^i32, slice_cstr: []string) {
	gy: i32 = 20
	for s in slice_cstr {
		cstr := fmt.ctprint(s)
		rl.DrawText(cstr, x^, y^, 20, rl.WHITE)
		y^ += gy
	}
}

draw_debug_overlay :: proc() {
	{
		player_id: Player_ID = .A
		input := g.players[player_id].input
		ship := g.players[player_id].ship
		x: i32 = 5
		y: i32 = 40

		rotating := .Rotate_Left in input ? "Left" : .Rotate_Right in input ? "Right" : "nil"

		arr := [?]string{
			fmt.tprintf("A"),
			fmt.tprintf("vel: %v", ship.velocity),
			fmt.tprintf("pos: %v", ship.position),
			fmt.tprintf("rot: %v", math.to_degrees(ship.rotation)),
			fmt.tprintf("mass: %v", ship.mass),
			fmt.tprintf("fuel: %v", ship.fuel),
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
		player_id: Player_ID = .B
		input := g.players[player_id].input
		ship := g.players[player_id].ship
		x: i32 = 5
		y: i32 = 400

		rotating := .Rotate_Left in input ? "Left" : .Rotate_Right in input ? "Right" : "nil"

		arr := [?]string{
			fmt.tprintf("B"),
			fmt.tprintf("vel: %v", ship.velocity),
			fmt.tprintf("pos: %v", ship.position),
			fmt.tprintf("rot: %v", math.to_degrees(ship.rotation)),
			fmt.tprintf("mass: %v", ship.mass),
			fmt.tprintf("fuel: %v", ship.fuel),
			fmt.tprintf("torp_count: %v", ship.torpedo_count),
			fmt.tprintf("hyperspace_count: %v", ship.hyperspace_count),
			fmt.tprintf("is_thrusting: %v", ship.is_thrusting),
			fmt.tprintf("rotating: %v", rotating),
			fmt.tprintf("is_hyperspacing: %v", ship.is_hyperspacing),
			fmt.tprintf("is_destroyed: %v", ship.is_destroyed),
		}
		debug_overlay_text_column(&x, &y, arr[:])
	}

	w, _ := get_viewport_size()
	off_x, _ := get_viewport_offset()
	{
		bsd := g.bloom_shader_data
		x: i32 = i32(-off_x + w)
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

draw_debug_origin_axes :: proc(left,right,top,bottom: f32) {
	rl.DrawLineV({left, 0}, {right, 0}, rl.BLUE)
	rl.DrawLineV({0, top}, {0, bottom}, rl.BLUE)
}
