extends GdToolsTest
## Mix state and persistence: sliders clamp, mute silences both buses, settings
## survive a reload (REQ-P1-06).

const TEMP_PATH := "user://test_audio_mix.cfg"

var _mix: AudioMix = null


func before_each() -> void:
	_mix = AudioMix.new()
	_remove_temp()


func after_each() -> void:
	_remove_temp()
	_mix = null


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_defaults_leave_music_under_the_effects() -> void:
	assert_true(_mix.music < _mix.sfx)
	assert_between(_mix.music, 0.4, 0.8)
	assert_false(_mix.muted)


func test_volumes_clamp_to_the_unit_range() -> void:
	assert_eq(_mix.set_music(2.5), 1.0)
	assert_eq(_mix.set_sfx(-3.0), 0.0)
	assert_eq(_mix.set_music(0.35), 0.35)


func test_mute_drops_both_buses_to_silence() -> void:
	_mix.set_music(0.6)
	_mix.set_sfx(0.7)
	_mix.set_muted(true)
	assert_eq(_mix.music_db(), AudioMix.MUTE_DB)
	assert_eq(_mix.sfx_db(), AudioMix.MUTE_DB)
	assert_true(_mix.toggle_muted() == false)
	assert_almost_eq(_mix.music_db(), linear_to_db(0.6), 0.01)


func test_zero_volume_is_silent_even_when_unmuted() -> void:
	_mix.set_muted(false)
	_mix.set_sfx(0.0)
	assert_eq(_mix.sfx_db(), AudioMix.MUTE_DB)


func test_save_and_load_round_trip() -> void:
	_mix.set_music(0.24)
	_mix.set_sfx(0.91)
	_mix.set_muted(true)
	assert_true(_mix.save(TEMP_PATH))

	var reloaded := AudioMix.new()
	assert_true(reloaded.load_from(TEMP_PATH))
	assert_almost_eq(reloaded.music, 0.24, 0.001)
	assert_almost_eq(reloaded.sfx, 0.91, 0.001)
	assert_true(reloaded.muted)


func test_missing_settings_file_keeps_defaults() -> void:
	var fresh := AudioMix.new()
	assert_false(fresh.load_from("user://definitely_not_saved.cfg"))
	assert_almost_eq(fresh.music, AudioMix.MUSIC_DEFAULT, 0.001)
	assert_false(fresh.muted)


func test_reset_restores_shipping_defaults() -> void:
	_mix.set_music(0.1)
	_mix.set_sfx(0.1)
	_mix.set_muted(true)
	_mix.reset()
	assert_almost_eq(_mix.music, AudioMix.MUSIC_DEFAULT, 0.001)
	assert_almost_eq(_mix.sfx, AudioMix.SFX_DEFAULT, 0.001)
	assert_false(_mix.muted)
