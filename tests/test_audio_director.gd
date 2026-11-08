extends GdToolsTest
## The director's runtime contract: cues fire on pooled voices, music beds loop,
## mute silences everything and the mix reports changes (REQ-P1-06).

const TEMP_PATH := "user://test_audio_director.cfg"

var _director: AudioDirector = null


func before_each() -> void:
	_remove_temp()
	_director = AudioDirector.new()
	_director.settings_path = TEMP_PATH
	add_child(_director)


func after_each() -> void:
	if is_instance_valid(_director):
		_director.queue_free()
	_director = null
	_remove_temp()


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_unknown_events_are_refused() -> void:
	assert_false(_director.play_event("kraken_scream"))
	assert_eq(_director.sfx_played, 0)
	assert_eq(_director.last_event, "")


func test_a_known_cue_plays_on_a_pooled_voice() -> void:
	assert_true(_director.play_event(AudioEvents.UI_CLICK))
	assert_eq(_director.last_event, AudioEvents.UI_CLICK)
	assert_eq(_director.sfx_played, 1)
	var voices: Array = _director._sfx
	assert_eq(voices.size(), AudioDirector.SFX_VOICES)
	var busy: int = 0
	for player: AudioStreamPlayer in voices:
		if player.playing:
			busy += 1
	assert_eq(busy, 1)


func test_the_pool_never_overruns_its_voices() -> void:
	for _step in AudioDirector.SFX_VOICES * 3:
		_director.play_event(AudioEvents.UI_CLICK)
	assert_eq(_director._sfx.size(), AudioDirector.SFX_VOICES)
	assert_eq(_director.sfx_played, AudioDirector.SFX_VOICES * 3)


func test_music_beds_load_and_loop() -> void:
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_eq(_director.current_track_id(), MusicPlaylist.SPANISH_MAIN)
	var stream := _director._active_player().stream as AudioStreamOggVorbis
	assert_not_null(stream)
	assert_true(stream.loop)
	assert_true(_director._ambience.playing)


func test_unknown_beds_are_refused() -> void:
	assert_false(_director.play_music("sea_shanty_404"))
	assert_eq(_director.current_track_id(), "")


func test_restarting_the_same_bed_does_not_restart_playback() -> void:
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	var player: AudioStreamPlayer = _director._active_player()
	var playback: float = player.get_playback_position()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_eq(_director._active_player(), player)
	assert_almost_eq(_director._active_player().get_playback_position(), playback, 0.5)


func test_switching_beds_crossfades_to_the_other_player() -> void:
	_director.play_music(MusicPlaylist.AGE_OF_DISCOVERY)
	var first: AudioStreamPlayer = _director._active_player()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	assert_ne(_director._active_player(), first)
	assert_eq(_director.current_track_id(), MusicPlaylist.SPANISH_MAIN)


func test_mute_silences_the_bed_and_the_ambience() -> void:
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	_director.set_muted(true)
	assert_eq(_director._active_player().volume_db, AudioDirector.SILENT_DB)
	assert_eq(_director._ambience.volume_db, AudioDirector.SILENT_DB)
	_director.set_muted(false)
	assert_almost_eq(_director._active_player().volume_db,
		linear_to_db(_director.mix.music), 0.01)


func test_volume_changes_are_clamped_and_broadcast() -> void:
	var seen: Array = []
	_director.mix_changed.connect(func(music: float, sfx: float, muted: bool) -> void:
		seen.append({"music": music, "sfx": sfx, "muted": muted})
	)
	_director.set_music_volume(4.0)
	_director.set_sfx_volume(-1.0)
	_director.set_muted(true)
	assert_eq(seen.size(), 3)
	assert_almost_eq(float(seen[0]["music"]), 1.0, 0.001)
	assert_almost_eq(float(seen[1]["sfx"]), 0.0, 0.001)
	assert_true(bool(seen[2]["muted"]))


func test_toggle_mute_flips_the_flag() -> void:
	assert_false(_director.is_muted())
	_director.toggle_mute()
	assert_true(_director.is_muted())
	_director.toggle_mute()
	assert_false(_director.is_muted())


func test_stingers_play_without_stopping_the_bed() -> void:
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	var bed: AudioStreamPlayer = _director._active_player()
	assert_true(_director.play_stinger(MusicPlaylist.VICTORY))
	assert_eq(_director._active_player(), bed)
	assert_true(bed.playing)
	assert_false((_director._sfx[0].stream as AudioStreamOggVorbis).loop)


func test_mix_settings_persist_to_disk() -> void:
	_director.set_music_volume(0.33)
	_director.set_muted(true)
	_director._save_timer.timeout.emit()
	var reloaded := AudioMix.new()
	assert_true(reloaded.load_from(TEMP_PATH))
	assert_almost_eq(reloaded.music, 0.33, 0.01)
	assert_true(reloaded.muted)
