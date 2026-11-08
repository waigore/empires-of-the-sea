class_name AudioMix
extends RefCounted
## Player-facing mix state and its persistence (REQ-P1-06: mute/volume work).
## Node-free so the clamp + save/load contract is unit-testable on its own.

const SETTINGS_PATH := "user://audio.cfg"
const MIN_VOLUME := 0.0
const MAX_VOLUME := 1.0
## Music sits under SFX so feedback never fights the score (REQ-P1-06).
const MUSIC_DEFAULT := 0.5
const SFX_DEFAULT := 0.85
const MUTE_DB := -80.0

var music: float = MUSIC_DEFAULT
var sfx: float = SFX_DEFAULT
var muted: bool = false


static func clamp_volume(value: float) -> float:
	if is_nan(value):
		return 0.0
	return clampf(value, MIN_VOLUME, MAX_VOLUME)


func set_music(value: float) -> float:
	music = clamp_volume(value)
	return music


func set_sfx(value: float) -> float:
	sfx = clamp_volume(value)
	return sfx


func set_muted(value: bool) -> bool:
	muted = value
	return muted


func toggle_muted() -> bool:
	muted = not muted
	return muted


func music_db() -> float:
	return _db(music)


func sfx_db() -> float:
	return _db(sfx)


func _db(volume: float) -> float:
	if muted or volume <= MIN_VOLUME:
		return MUTE_DB
	return linear_to_db(clamp_volume(volume))


func save(path: String = SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value("audio", "music", music)
	config.set_value("audio", "sfx", sfx)
	config.set_value("audio", "muted", muted)
	return config.save(path) == OK


func load_from(path: String = SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	music = clamp_volume(float(config.get_value("audio", "music", MUSIC_DEFAULT)))
	sfx = clamp_volume(float(config.get_value("audio", "sfx", SFX_DEFAULT)))
	muted = bool(config.get_value("audio", "muted", false))
	return true


func reset() -> void:
	music = MUSIC_DEFAULT
	sfx = SFX_DEFAULT
	muted = false


func as_dict() -> Dictionary:
	return {"music": music, "sfx": sfx, "muted": muted}
