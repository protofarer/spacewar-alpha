package game

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/linalg"

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

is_set_fully_flagged :: proc(set: bit_set[$E]) -> bool {
    return card(set) == len(E)
}

is_mouse_over_rect :: proc(x,y,w,h: f32) -> bool {
	mouse_pos := rl.GetMousePosition()
	return mouse_pos.x >= x && mouse_pos.x <= x + w &&
	       mouse_pos.y >= y && mouse_pos.y <= y + h
}

rotate_vec2 :: proc(v: Vec2, angle: f32) -> Vec2 {
	rot_matrix := linalg.matrix2_rotate(angle)
	result := rot_matrix * v
	return result
}

vec2_from_rotation :: proc(rot: f32) -> Vec2 {
	return Vec2{
		math.cos(rot),
		math.sin(rot)
	}
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
