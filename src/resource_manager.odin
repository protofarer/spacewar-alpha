package game

import "core:log"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

AUDIO_FILE_EXTENSIONS := [?]string{
	"wav", "WAV", "mp3", "ogg",
}
BASE_TEXTURE_PATH :: "assets/textures/"
BASE_SOUND_PATH :: "assets/sounds/"
BASE_MUSIC_PATH :: "assets/music/"

Resource_Load_Result :: enum {
    File_Not_Found,
	Load_Error,
    Success,
    Memory_Error,
    Invalid_Format,
}

Resource_Manager :: struct {
    textures: [Texture_ID]rl.Texture,
    sounds: [Sound_ID]rl.Sound,
	music: [Music_ID]rl.Music,
    // fonts: [Font_ID]rl.Font,
    // transparency_color: rl.Color,
}

load_all_assets :: proc(rm: ^Resource_Manager) -> bool {
    log.info("Loading game assets...")

    texture_success := load_all_textures(rm)
    sound_success := load_all_sounds(rm)
    music_success := load_all_music(rm)
    // font_success := load_all_fonts(rm)
    if texture_success && sound_success && music_success {
        log.infof("Asset loading complete")
        return true
    } else {
        log.errorf("Asset loading failed, there were some errors")
        return false
    }
}

load_all_textures :: proc(rm: ^Resource_Manager) -> bool {
    success := true
    for id in Texture_ID {
		texture, result := load_texture_by_id(id)
        if result != .Success {
            log.errorf("Failed to load texture %v: %v", id, result)
            success = false
			continue
        }
		rm.textures[id] = texture
    }
    return success
}

load_all_sounds :: proc(rm: ^Resource_Manager) -> bool {
    success := true
    for id in Sound_ID {
        sound, result := load_sound_by_id(id)
        if result != .Success {
            log.errorf("Failed to load sound %v: %v", id, result)
            success = false
			continue
        }
		rm.sounds[id] = sound
    }
    return success
}

load_all_music :: proc(rm: ^Resource_Manager) -> bool {
    success := true
    for id in Music_ID {
        music, result := load_music_by_id(id)
        if result != .Success {
            log.errorf("Failed to load music %v: %v", id, result)
            success = false
			continue
        }
		rm.music[id] = music
    }
    return success
}

// Load a single texture with metadata tracking
load_texture_by_id :: proc(id: Texture_ID) -> (texture: rl.Texture, result: Resource_Load_Result) {
	filepath := make_filepath_from_id_and_extension(id, "png")
	return load_texture(filepath)
}

load_texture :: proc(filepath: string) -> (texture: rl.Texture, result: Resource_Load_Result) {
	cfilepath := strings.clone_to_cstring(filepath, context.temp_allocator)

	if !rl.FileExists(cfilepath) do return {}, .File_Not_Found

    image := rl.LoadImage(cfilepath)
    defer rl.UnloadImage(image)

    if !rl.IsImageValid(image) do return {}, .Load_Error

    // rl.ImageColorReplace(&image, rm.transparency_color, rl.BLANK)

    texture = rl.LoadTextureFromImage(image)
	if !rl.IsTextureValid(texture) {
		rl.UnloadTexture(texture)
		return {}, .Load_Error
	}

	// rl.SetTextureFilter(texture, .BILINEAR)

	return texture, .Success
}

load_sound_by_id :: proc(id: Sound_ID) -> (sound: rl.Sound, result: Resource_Load_Result) {
	for ext in AUDIO_FILE_EXTENSIONS {
		filepath := make_filepath_from_id_and_extension(id, ext)
		sound, result = load_sound(filepath)
		if result == .Success {
			return sound, result
		} 
	}
	return {}, result
}

load_sound :: proc(filepath: string) -> (sound: rl.Sound, result: Resource_Load_Result) {
	cfilepath := strings.clone_to_cstring(filepath, context.temp_allocator)
	if !rl.FileExists(cfilepath) {
		return {}, .File_Not_Found
	}

	sound = rl.LoadSound(cfilepath)
	if !rl.IsSoundValid(sound) {
		rl.UnloadSound(sound)
		return sound, .Load_Error
	}

	return sound, .Success
}

load_music_by_id :: proc(id: Music_ID) -> (music: rl.Music, result: Resource_Load_Result) {
	last_result: Resource_Load_Result
	for ext in AUDIO_FILE_EXTENSIONS {
		filepath := make_filepath_from_id_and_extension(id, ext)
		music, result = load_music(filepath)
		if result == .Success {
			return music, result
		} 
		last_result = result
	}
	return {}, last_result
}

load_music :: proc(filepath: string) -> (music: rl.Music, result: Resource_Load_Result) {
	cfilepath := strings.clone_to_cstring(filepath, context.temp_allocator)
	if !rl.FileExists(cfilepath) {
		return {}, .File_Not_Found
	}

	music = rl.LoadMusicStream(cfilepath)
	if !rl.IsMusicValid(music) {
		rl.UnloadMusicStream(music)
		return music, .Load_Error
	}

	return music, .Success
}

make_filepath_from_id_and_extension :: proc {
    make_filepath_from_id_and_extension_texture,
    make_filepath_from_id_and_extension_sound,
	make_filepath_from_id_and_extension_music,
}

make_filepath_from_id_and_extension_texture :: proc(id: Texture_ID, ext: string) -> string {
    filename := get_name_from_id(id)
	filepath := fmt.tprintf("%v%v.%v", BASE_TEXTURE_PATH, filename, ext)
	return filepath
}

make_filepath_from_id_and_extension_sound :: proc(id: Sound_ID, ext: string) -> string {
    filename := get_name_from_id(id)
	filepath := fmt.tprintf("%v%v.%v", BASE_SOUND_PATH, filename, ext)
	return filepath
}

make_filepath_from_id_and_extension_music :: proc(id: Music_ID, ext: string) -> string {
    filename := get_name_from_id(id)
	filepath := fmt.tprintf("%v%v.%v", BASE_MUSIC_PATH, filename, ext)
	return filepath
}

// TODO: just make caall the strings/fmt procs at the call site for this proc group!
get_name_from_id :: proc {
    get_name_from_id_texture,
    get_name_from_id_sound,
	get_name_from_id_music,
}

get_name_from_id_texture :: proc(id: Texture_ID) -> string {
    return strings.to_lower(fmt.tprintf(("%v"), id), context.temp_allocator)
}

get_name_from_id_sound :: proc(id: Sound_ID) -> string {
    return strings.to_lower(fmt.tprintf("%v", id), context.temp_allocator)
}

get_name_from_id_music :: proc(id: Music_ID) -> string {
    return strings.to_lower(fmt.tprintf("%v", id), context.temp_allocator)
}

get_texture :: proc(id: Texture_ID) -> rl.Texture {
    tex := g.resman.textures[id]
    if tex == {} do log.error("Failed to get texture", id)
    return tex
}

get_sound :: proc(id: Sound_ID) -> rl.Sound {
    sound := g.resman.sounds[id]
    if sound == {} do log.error("Failed to get sound", id)
    return sound
}

get_music :: proc(id: Music_ID) -> Maybe(rl.Music) {
    music := g.resman.music[id]
    if music == {} {
		log.error("Failed to get music", id)
		return nil
	}
    return music
}

unload_all_assets :: proc(rm: ^Resource_Manager) {
    log.info("Unloading all assets...")
    for id in Texture_ID {
        rl.UnloadTexture(rm.textures[id])
    }
    for id in Sound_ID {
        rl.UnloadSound(rm.sounds[id])
    }
    for id in Music_ID {
        rl.UnloadMusicStream(rm.music[id])
    }
    // for id in Font_ID {
    //     rl.UnloadFont(rm.fonts[id])
    // }
    log.info("All assets unloaded")
}

// Load all fonts with error handling
// load_all_fonts :: proc(rm: ^Resource_Manager) -> bool {
//     success := true
//     for id in Font_ID {
//         result := load_font(rm, id)
//         if result != .Success {
//             log.errorf("Failed to load font %v: %v", id, result)
//             success = false
//         }
//     }
//     return success
// }

// Load a single font with metadata tracking
// load_font :: proc(rm: ^Resource_Manager, kind: Font_Kind) -> Resource_Load_Result {
//     file_path := get_font_file_path(kind)
//     font := rl.LoadFont(file_path)
//     if font.texture.id == 0 {
//         metadata.load_result = .File_Not_Found
//         return .File_Not_Found
//     }
//     rm.fonts[kind] = font
//     return .Success
// }

// get_font :: proc(rm: ^Resource_Manager, kind: Font_Kind) -> rl.Font {
//     if rm == nil {
//         log.errorf("get_font called with nil Resource_Manager for font: %v", kind)
//         return {} // Return empty font
//     }
//     metadata := rm.font_metadata[kind]
//     if !metadata.is_loaded {
//         log.warnf("Accessing unloaded font: %v", kind)
//         // Return a default/error font if available, or the unloaded font
//     }
//     return rm.fonts[kind]
// }
