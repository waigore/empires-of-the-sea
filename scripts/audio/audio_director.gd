class_name AudioDirector
extends Node
## Presentation-layer audio: one music bed with a crossfade pair, a small SFX
## voice pool and the sea ambience. Nothing here decides gameplay; screens call
## `play_event` / `play_music` and the mix stays in `AudioMix` (REQ-P1-06, P3).
##
## Lives as a scene node (no autoload) so `arch-lint` keeps autoloads empty and
## tests can instantiate it in isolation.

signal mix_changed(music_volume: float, sfx_volume: float, muted: bool)

const MUSIC_FADE := 1.6
const SFX_VOICES := 6
const SILENT_DB := -80.0
const AMBIENCE_GAIN := 0.55

var mix: AudioMix = AudioMix.new()
var settings_path: String = AudioMix.SETTINGS_PATH
## Last cue / bed requested — intent, even when the stream is missing on disk.
var last_event: String = ""
var last_track_id: String = ""
var sfx_played: int = 0

var _music: Array[AudioStreamPlayer] = []
var _active: int = 0
var _sfx: Array[AudioStreamPlayer] = []
var _cursor: int = 0
var _ambience: AudioStreamPlayer = null
var _cache: Dictionary = {}
var _fades: Array[Tween] = []
var _save_timer: Timer = null
var _current_track: String = ""


func _ready() -> void:
	_build_players()
	mix.load_from(settings_path)
	_apply_mix()


# --- cues --------------------------------------------------------------------


func play_event(event_name: String, volume_scale: float = 1.0) -> bool:
	if not AudioEvents.has(event_name):
		return false
	last_event = event_name
	var stream: AudioStream = _stream(AudioEvents.path_for(event_name))
	if stream == null:
		return false
	sfx_played += 1
	if mix.muted:
		return true
	var cue: Dictionary = AudioEvents.cue(event_name)
	var pitch: float = float(cue.get("pitch", 0.0))
	var player: AudioStreamPlayer = _take_sfx_player()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch, pitch)
	player.volume_db = SILENT_DB
	if not mix.muted:
		var trim: float = float(cue.get("volume_db", -12.0))
		var scale_db: float = linear_to_db(clampf(volume_scale, 0.05, 1.0))
		player.volume_db = trim + scale_db + mix.sfx_db()
	player.play()
	return true


# --- music -------------------------------------------------------------------


func play_music(track_id: String, fade: float = MUSIC_FADE) -> bool:
	if MusicPlaylist.track(track_id).is_empty():
		return false
	last_track_id = track_id
	if track_id == _current_track and _active_player().playing:
		return true
	var stream: AudioStream = _stream(MusicPlaylist.path_for(track_id))
	if stream == null:
		return false
	_set_loop(stream, MusicPlaylist.loops(track_id))
	_crossfade(stream, fade)
	_current_track = track_id
	_start_ambience()
	return true


func stop_music(fade: float = MUSIC_FADE) -> void:
	_current_track = ""
	var player: AudioStreamPlayer = _active_player()
	_fade_to(player, SILENT_DB, fade, true)


## One-shot musical hit (victory fanfare, defeat knell) over the running bed.
func play_stinger(track_id: String, volume_db: float = -4.0) -> bool:
	var stream: AudioStream = _stream(MusicPlaylist.path_for(track_id))
	if stream == null:
		return false
	_set_loop(stream, false)
	sfx_played += 1
	if mix.muted:
		return true
	var player: AudioStreamPlayer = _take_sfx_player()
	player.stream = stream
	player.pitch_scale = 1.0
	player.volume_db = volume_db + mix.sfx_db()
	player.play()
	return true


func current_track_id() -> String:
	return _current_track


# --- mix ---------------------------------------------------------------------


func set_music_volume(value: float) -> void:
	mix.set_music(value)
	_apply_mix()
	_save_soon()
	mix_changed.emit(mix.music, mix.sfx, mix.muted)


func set_sfx_volume(value: float) -> void:
	mix.set_sfx(value)
	_apply_mix()
	_save_soon()
	mix_changed.emit(mix.music, mix.sfx, mix.muted)


func set_muted(value: bool) -> void:
	mix.set_muted(value)
	_apply_mix()
	_save_soon()
	mix_changed.emit(mix.music, mix.sfx, mix.muted)


func toggle_mute() -> void:
	set_muted(not mix.muted)


func is_muted() -> bool:
	return mix.muted


func mix_state() -> Dictionary:
	return mix.as_dict()


# --- internals ---------------------------------------------------------------


func _build_players() -> void:
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % index
		player.volume_db = SILENT_DB
		add_child(player)
		_music.append(player)
	for index in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % index
		player.volume_db = SILENT_DB
		add_child(player)
		_sfx.append(player)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.volume_db = SILENT_DB
	add_child(_ambience)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(func() -> void: mix.save(settings_path))
	add_child(_save_timer)


func _save_soon() -> void:
	if _save_timer != null:
		_save_timer.start()


func _apply_mix() -> void:
	for tween: Tween in _fades:
		if tween.is_valid():
			tween.kill()
	_fades.clear()
	for index in _music.size():
		var player: AudioStreamPlayer = _music[index]
		player.volume_db = mix.music_db() if index == _active else SILENT_DB
	_ambience.volume_db = _ambience_db()
	for player: AudioStreamPlayer in _sfx:
		if not player.playing:
			player.volume_db = SILENT_DB


func _ambience_db() -> float:
	if mix.muted:
		return SILENT_DB
	return mix.music_db() + linear_to_db(AMBIENCE_GAIN)


func _start_ambience() -> void:
	if _ambience.playing:
		return
	var stream: AudioStream = _stream(MusicPlaylist.AMBIENCE)
	if stream == null:
		return
	_set_loop(stream, true)
	_ambience.stream = stream
	_ambience.volume_db = _ambience_db()
	_ambience.play()


func _crossfade(stream: AudioStream, fade: float) -> void:
	var previous: AudioStreamPlayer = _active_player()
	var next_index: int = 1 - _active
	var incoming: AudioStreamPlayer = _music[next_index]
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_active = next_index
	_fade_to(previous, SILENT_DB, fade, true)
	_fade_to(incoming, mix.music_db(), fade, false)


func _fade_to(player: AudioStreamPlayer, target_db: float, fade: float,
		stop_when_done: bool) -> void:
	if fade <= 0.0:
		player.volume_db = target_db
		if stop_when_done:
			player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, fade)
	if stop_when_done:
		tween.tween_callback(player.stop)
	_fades.append(tween)
	if _fades.size() > 8:
		_fades = _fades.slice(_fades.size() - 8)


func _active_player() -> AudioStreamPlayer:
	return _music[_active]


func _take_sfx_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx:
		if not player.playing:
			return player
	var chosen: AudioStreamPlayer = _sfx[_cursor % _sfx.size()]
	_cursor += 1
	chosen.stop()
	return chosen


func _stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as AudioStream
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is AudioStream:
		_cache[path] = loaded
		return loaded
	return null


func _set_loop(stream: AudioStream, loop: bool) -> void:
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = loop
		return
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
