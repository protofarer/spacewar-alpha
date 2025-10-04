package game

import "core:log"
import rl "vendor:raylib"

// TODO: don't use audman global, procs are getting confusing about whether audman var is a pointer or value

Audio_Manager :: struct {
    master_volume: f32,
	muted: bool,
    sfx_volume: f32,
    music_volume: f32,
    current_music_id: Maybe(Music_ID),
    music_state: Music_State,
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
    }
}

update_audio_manager :: proc() {
	am := &g.audman
	if m, ok := get_current_music().?; ok {
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
	am := &g.audman
    am.music_volume = clamp(volume, 0.0, 1.0)
    if m, ok := get_current_music().?; ok {
        rl.SetMusicVolume(m, am.music_volume * am.master_volume)
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

play_music :: proc(id: Music_ID, loop: bool = true) {
	am := &g.audman
    if am.muted do return

    stop_music()

    am.current_music_id = id
    am.music_state = .Playing

    if music, ok := get_music(id).?; ok {
		vol := am.music_volume * am.master_volume
		music.looping = loop
		rl.SetMusicVolume(music, vol)
		rl.PlayMusicStream(music)
		log.debugf("Started playing music: %v (loop: %v)", id, loop)
	}
}

is_music_looping :: proc(id: Music_ID) -> bool {
	if music, ok := get_music(id).?; ok {
		if music.looping {
			return true
		}
	}
	return false
}

stop_music :: proc() {
	am := &g.audman
	if m, ok := get_current_music().?; ok {
        rl.StopMusicStream(m)
        log.debugf("Stopped music")
    }
    am.current_music_id = nil
    am.music_state = .Stopped
}

pause_music :: proc() {
	am := &g.audman
	if m, ok := get_current_music().?; ok && am.music_state == .Playing {
        rl.PauseMusicStream(m)
        am.music_state = .Paused
        log.debugf("Paused music")
    }
}

resume_music :: proc() {
	am := &g.audman
	if m, ok := get_current_music().?; ok && am.music_state == .Paused {
		rl.ResumeMusicStream(m)
		log.debugf("Resumed music")
		am.music_state = .Playing
	}
}

restart_music :: proc() {
	am := &g.audman
    if m, ok := get_current_music().?; ok {
		rl.StopMusicStream(m)
		rl.PlayMusicStream(m)
        log.debugf("Restarted music")
    }
}

get_current_music :: proc() -> Maybe(rl.Music) {
	if m_id, ok_m_id := get_current_music_id().?; ok_m_id {
		return get_music(m_id)
	}
	return nil
}

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
