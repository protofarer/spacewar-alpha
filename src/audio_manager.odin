package game

import "core:log"
import rl "vendor:raylib"

Audio_Manager :: struct {
    master_volume: f32,
	muted: bool,
    sfx_volume: f32,
    music_volume: f32,
    current_music: Maybe(Sound_ID),
    music_state: Music_State,
    music_loop: bool,
}

Music_State :: enum {
    Stopped,
    Playing,
    Paused,
}

init_audio_manager :: proc() -> Audio_Manager {
    return Audio_Manager{
        master_volume = 1.0,
        sfx_volume = 1.0,
        music_volume = 1.0,
        muted = false,
        current_music = nil,
        music_state = .Stopped,
        music_loop = true,
    }
}

set_master_volume :: proc(volume: f32) {
	am := g.audman
    am.master_volume = clamp(volume, 0.0, 1.0)
    rl.SetMasterVolume(am.master_volume)
}

set_sfx_volume :: proc(volume: f32) {
	am := g.audman
    am.sfx_volume = clamp(volume, 0.0, 1.0)
}

set_music_volume :: proc(volume: f32) {
	am := g.audman
    am.music_volume = clamp(volume, 0.0, 1.0)
    if current_music := am.current_music; current_music != nil {
        sound := get_sound(current_music.?)
        rl.SetSoundVolume(sound, am.music_volume * am.master_volume)
    }
}

toggle_mute :: proc() {
	set_mute(!g.audman.muted)
}

set_mute :: proc(muted: bool) {
	am := g.audman
    am.muted = muted
    if am.muted {
        rl.SetMasterVolume(0.0)
    } else {
        rl.SetMasterVolume(am.master_volume)
    }
}

play_sfx :: proc(id: Sound_ID) {
	am := g.audman
    if am.muted do return
    sound := get_sound(id)
    rl.SetSoundVolume(sound, am.sfx_volume * am.master_volume)
    rl.PlaySound(sound)
}

play_continuous_sfx :: proc(id: Sound_ID) {
	am := g.audman
    if am.muted do return

    sound := get_sound(id)
	if !rl.IsSoundPlaying(sound) {
		rl.SetSoundVolume(sound, am.sfx_volume * am.master_volume)
		rl.PlaySound(sound)
	}
}

play_music :: proc(id: Sound_ID, loop: bool = true) {
	am := g.audman
    if am.muted do return

    stop_music()

    am.current_music = id
    am.music_loop = loop
    am.music_state = .Playing

    sound := get_sound(id)
    rl.SetSoundVolume(sound, am.music_volume * am.master_volume)
    rl.PlaySound(sound)

    log.debugf("Started playing music: %v (loop: %v)", id, loop)
}

stop_music :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil {
        sound := get_sound(current_music.?)
        rl.StopSound(sound)
        log.debugf("Stopped music: %v", current_music)
    }
    am.current_music = nil
    am.music_state = .Stopped
}

pause_music :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil && am.music_state == .Playing {
        sound := get_sound(current_music.?)
        rl.PauseSound(sound)
        am.music_state = .Paused
        log.debugf("Paused music: %v", current_music)
    }
}

resume_music :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil && am.music_state == .Paused {
        sound := get_sound(current_music.?)
        rl.ResumeSound(sound)
        am.music_state = .Playing
        log.debugf("Resumed music: %v", current_music)
    }
}

is_music_playing :: proc() -> bool {
	am := g.audman
    return am.music_state == .Playing
}

is_music_paused :: proc() -> bool {
	am := g.audman
    return am.music_state == .Paused
}

get_current_music :: proc() -> Maybe(Sound_ID) {
	am := g.audman
    return am.current_music
}

update_audio_manager :: proc() {
	am := g.audman
    if current_music := am.current_music; current_music != nil && am.music_state == .Playing {
        sound := get_sound(current_music.?)

        if !rl.IsSoundPlaying(sound)  {
			if am.music_loop {
				rl.PlaySound(sound)
			} else {
				am.current_music = nil
				am.music_state = .Stopped
			}
        }
    }
}

stop_sfx :: proc(id: Sound_ID) {
    sound := get_sound(id)
    rl.StopSound(sound)
}

is_sfx_playing :: proc(id: Sound_ID) -> bool {
    sound := get_sound(id)
    return rl.IsSoundPlaying(sound)
}

restart_sfx :: proc(id: Sound_ID) {
    if is_sfx_playing(id) {
        stop_sfx(id)
    }
    play_sfx(id)
}
