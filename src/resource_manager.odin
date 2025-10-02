package game

import "core:log"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Resource_Load_Result :: enum {
    Success,
    File_Not_Found,
    Invalid_Format,
    Memory_Error,
	Load_Error,
}

Resource_Manager :: struct {
    textures:[Texture_ID]rl.Texture,
    base_texture_path: string,
    sounds:[Sound_ID]rl.Sound,
    base_sound_path: string,
    // fonts: [Font_ID]rl.Font,
    // base_font_path: string,
    // transparency_color: rl.Color,
}

setup_resource_manager :: proc(rm: ^Resource_Manager) {
    log.info("Setup resource manager...")
    rm.base_texture_path = "assets/"
    rm.base_sound_path = "assets/sounds/"
    // rm.base_font_path = "assets/fonts/"
    // rm.transparency_color = rl.WHITE
}

load_all_assets :: proc(rm: ^Resource_Manager) -> bool {
    log.info("Loading game assets...")

    texture_success := load_all_textures(rm)
    sound_success := load_all_sounds(rm)
    // font_success := load_all_fonts(rm)
    if texture_success && sound_success {
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
		result := load_texture(rm, id)
        if result != .Success {
            log.errorf("Failed to load texture %v: %v", id, result)
            success = false
        }
    }
    return success
}

load_all_sounds :: proc(rm: ^Resource_Manager) -> bool {
    success := true
    for id in Sound_ID {
        result := load_sound(rm, id)
        if result != .Success {
            log.errorf("Failed to load sound %v: %v", id, result)
            success = false
        }
    }
    return success
}

get_name_from_id_texture :: proc(id: Texture_ID) -> string {
    return strings.to_lower(fmt.tprintf(("%v"), id), context.temp_allocator)
}

get_name_from_id_sound :: proc(id: Sound_ID) -> string {
    return strings.to_lower(fmt.tprintf("%v", id), context.temp_allocator)
}

get_name_from_id :: proc {
    get_name_from_id_texture,
    get_name_from_id_sound,
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

unload_all_assets :: proc(rm: ^Resource_Manager) {
    log.info("Unloading all assets...")
    for id in Texture_ID {
        rl.UnloadTexture(rm.textures[id])
    }
    for id in Sound_ID {
        rl.UnloadSound(rm.sounds[id])
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
