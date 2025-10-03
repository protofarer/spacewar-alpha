package game

import "core:log"
import rl "vendor:raylib"

// TODO: remove extra music state, since depending on raylib. Maybe music_loop and music_state?
// TODO: don't use audman global, procs are getting confusing about whether audman var is a pointer or value

Audio_Manager :: struct {
    master_volume: f32,
	muted: bool,
    sfx_volume: f32,
    music_volume: f32,
    current_music_id: Maybe(Music_ID),
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
        current_music_id = nil,
        music_state = .Stopped,
        music_loop = true,
    }
}

update_audio_manager :: proc() {
	am := &g.audman
	if m_id, ok := get_current_music_id().?; ok {
		m := get_music(m_id)
		rl.UpdateMusicStream(m)
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
    if current_music_id := am.current_music_id; current_music_id != nil {
        music := get_music(current_music_id.?)
        rl.SetMusicVolume(music, am.music_volume * am.master_volume)
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

// TODO: rm any duplicate state that raylib already handles?
// TODO: set rl.Music loop accordingly
play_music :: proc(id: Music_ID, loop: bool = true) {
	am := &g.audman
    if am.muted do return

    stop_music()

    am.current_music_id = id
    am.music_loop = loop
    am.music_state = .Playing

    music := get_music(id)
	vol := am.music_volume * am.master_volume
    rl.SetMusicVolume(music, vol)
    rl.PlayMusicStream(music)
    log.debugf("Started playing music: %v (loop: %v)", id, loop)
}

// TODO: use get_current_music_id and Maybe access
stop_music :: proc() {
	am := &g.audman
    if current_music_id := am.current_music_id; current_music_id != nil {
        music := get_music(current_music_id.?)
        rl.StopMusicStream(music)
        log.debugf("Stopped music: %v", current_music_id)
    }
    am.current_music_id = nil
    am.music_state = .Stopped
}

// TODO: use get_current_music_id and Maybe access
pause_music :: proc() {
	am := &g.audman
    if current_music_id := am.current_music_id; current_music_id != nil && am.music_state == .Playing {
        music := get_music(current_music_id.?)
        rl.PauseMusicStream(music)
        am.music_state = .Paused
        log.debugf("Paused music: %v", current_music_id)
    }
}

// TODO: use get_current_music_id and Maybe access
resume_music :: proc() {
	am := &g.audman
    if current_music_id := am.current_music_id; current_music_id != nil && am.music_state == .Paused {
        music := get_music(current_music_id.?)
        rl.ResumeMusicStream(music)
        am.music_state = .Playing
        log.debugf("Resumed music: %v", current_music_id)
    }
}

restart_music :: proc() {
	am := &g.audman
    if m_id, ok := get_current_music_id().?; ok {
		m := get_music(m_id)
		rl.StopMusicStream(m)
		rl.PlayMusicStream(m)
        log.debugf("Restarted music: %v", current_music_id)
    }
}

// TODO: get_current_music :: proc() -> Maybe(rl.Music) {}

// TODO: use raylib
is_music_playing :: proc() -> bool {
	am := g.audman
    return am.music_state == .Playing
}

// TODO: use raylib
is_music_paused :: proc() -> bool {
	am := g.audman
    return am.music_state == .Paused
}

get_current_music_id :: proc() -> Maybe(Music_ID) {
	am := g.audman
    return am.current_music_id
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
