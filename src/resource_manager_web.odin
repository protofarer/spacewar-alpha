#+build wasm32, wasm64p32
package game

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Load a single texture with metadata tracking
load_texture :: proc(rm: ^Resource_Manager, id: Texture_ID) -> Resource_Load_Result {
    filename := get_name_from_id(id)
	filepath := fmt.tprintf("%v%v.png", rm.base_texture_path, filename)

    image := rl.LoadImage(strings.clone_to_cstring(filepath))

    if image.data == nil do return .Load_Error

    // Apply transparency processing
    // rl.ImageColorReplace(&image, rm.transparency_color, rl.BLANK)
    texture := rl.LoadTextureFromImage(image)
    if texture.id == 0 {
        rl.UnloadImage(image)
        return .Memory_Error
    }

	// rl.SetTextureFilter(texture, .BILINEAR)

    rm.textures[id] = texture
    rl.UnloadImage(image)
    return .Success
}

load_sound :: proc(rm: ^Resource_Manager, id: Sound_ID) -> Resource_Load_Result {
    filename := get_name_from_id(id)
	filepath_wav := fmt.ctprintf("%v%v.wav", rm.base_sound_path, filename)

	sound := rl.LoadSound(filepath_wav)
	if sound.stream.buffer == nil {
		filepath_WAV := fmt.ctprintf("%v%v.WAV", rm.base_sound_path, filename)
		sound = rl.LoadSound(filepath_WAV)
		if sound.stream.buffer == nil {
			filepath_mp3 := fmt.ctprintf("%v%v.mp3", rm.base_sound_path, filename)
			sound = rl.LoadSound(filepath_mp3)
			if sound.stream.buffer == nil {
				filepath_ogg := fmt.ctprintf("%v%v.ogg", rm.base_sound_path, filename)
				sound = rl.LoadSound(filepath_ogg)
				if sound.stream.buffer == nil {
					return .File_Not_Found
				}
			}
		}
	}

    rm.sounds[id] = sound
    return .Success
}

