#+build linux, darwin, windows
package game

import "core:fmt"
import "core:strings"
import "core:os"
import rl "vendor:raylib"

// Load a single texture with metadata tracking
load_texture :: proc(rm: ^Resource_Manager, id: Texture_ID) -> Resource_Load_Result {
    filename := get_name_from_id(id)
	filepath := fmt.tprintf("%v%v.png", rm.base_texture_path, filename)

	if !os.exists(filepath) do return .File_Not_Found

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

	filepath: string
	if wav := fmt.tprintf("%v%v.wav", rm.base_sound_path, filename); os.exists(wav) {
		filepath = wav
	} else if cap_wav := fmt.tprintf("%v%v.WAV", rm.base_sound_path, filename); os.exists(cap_wav) {
		filepath = cap_wav
	} else if mp3 := fmt.tprintf("%v%v.mp3", rm.base_sound_path, filename); os.exists(mp3) {
		filepath = mp3
	} else if ogg := fmt.tprintf("%v%v.ogg", rm.base_sound_path, filename); os.exists(ogg) {
		filepath = ogg
	} else {
		return .File_Not_Found
	}

	sound := rl.LoadSound(strings.clone_to_cstring(filepath))
	if sound.stream.buffer == nil {
			return .Load_Error
	}

    rm.sounds[id] = sound
    return .Success
}

