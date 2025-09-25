package game

import rl "vendor:raylib"

LETTERBOX_COLOR :: rl.DARKGRAY

begin_letterbox_rendering :: proc() {
	rl.BeginTextureMode(g.render_texture)
	// rl.ClearBackground(BACKGROUND_COLOR)
	rl.DrawRectangle(0,0,LOGICAL_SCREEN_WIDTH,LOGICAL_SCREEN_HEIGHT, rl.Fade(rl.BLACK, 0.08))
	
	// Scale all drawing by RENDER_TEXTURE_SCALE for higher resolution
	camera := rl.Camera2D{
		zoom = RENDER_TEXTURE_SCALE,
		offset = { 
			get_playfield_right() * RENDER_TEXTURE_SCALE,
			f32(PLAYFIELD_LENGTH) / 2 + f32(TOPBAR_HEIGHT) / 2 * RENDER_TEXTURE_SCALE,
		},
	}
	rl.BeginMode2D(camera)
}

end_letterbox_rendering :: proc() {
	rl.EndMode2D()  // End the scale transform
	rl.EndTextureMode()
	
	rl.BeginDrawing()
	rl.ClearBackground(LETTERBOX_COLOR)
	
	// Calculate letterbox dimensions
	viewport_width, viewport_height := get_viewport_size()
	offset_x, offset_y := get_viewport_offset()
	
	// Draw the render texture with letterboxing
	render_texture_width: f32 = LOGICAL_SCREEN_WIDTH * RENDER_TEXTURE_SCALE
	render_texture_height: f32 = LOGICAL_SCREEN_HEIGHT * RENDER_TEXTURE_SCALE
	src := Rect{0, 0, render_texture_width, -render_texture_height} // negative height flips texture
	dst := Rect{-offset_x, -offset_y, viewport_width, viewport_height}

	rl.BeginShaderMode(g.shaders[.FX_Bloom])
	rl.DrawTexturePro(g.render_texture.texture, src, dst, {}, 0, rl.WHITE)
	rl.EndShaderMode()
	// rl.EndDrawing() // moved outside for debug overlay
}

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
