# gdlint: disable=max-public-methods
extends GdToolsTest
## One boot for the mix and the director (wiki: sounds).
## Also includes map soundtrack (one Godot boot).

## Merged from test_audio_mix, test_audio_director.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const TEMP_PATH := "user://test_audio_mix.cfg"
const audio_director_TEMP_PATH := "user://test_audio_director.cfg"

var _mix: AudioMix = null
var _director: AudioDirector = null

var _suite_setup: String = ""

func after_each() -> void:
	match _suite_setup:
		"audio_mix":
			_teardown_audio_mix()
		"audio_director":
			_teardown_audio_director()
		"map_soundtrack":
			_teardown_map_soundtrack()
	_suite_setup = ""

func _setup_audio_mix() -> void:
	_suite_setup = "audio_mix"
	_mix = AudioMix.new()
	_remove_temp()

func _setup_audio_director() -> void:
	_suite_setup = "audio_director"
	_audio_director_remove_temp()
	_director = AudioDirector.new()
	_director.settings_path = audio_director_TEMP_PATH
	add_child(_director)

func _teardown_audio_mix() -> void:
	_remove_temp()
	_mix = null

func _teardown_audio_director() -> void:
	if is_instance_valid(_director):
		_director.queue_free()
	_director = null
	_audio_director_remove_temp()

# --- test_audio_mix ---

func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

func test_defaults_leave_music_under_the_effects() -> void:
	_setup_audio_mix()
	assert_true(_mix.music < _mix.sfx)
	assert_between(_mix.music, 0.4, 0.8)
	assert_false(_mix.muted)

func test_volumes_clamp_to_the_unit_range() -> void:
	_setup_audio_mix()
	assert_eq(_mix.set_music(2.5), 1.0)
	assert_eq(_mix.set_sfx(-3.0), 0.0)
	assert_eq(_mix.set_music(0.35), 0.35)

func test_mute_drops_both_buses_to_silence() -> void:
	_setup_audio_mix()
	_mix.set_music(0.6)
	_mix.set_sfx(0.7)
	_mix.set_muted(true)
	assert_eq(_mix.music_db(), AudioMix.MUTE_DB)
	assert_eq(_mix.sfx_db(), AudioMix.MUTE_DB)
	assert_true(_mix.toggle_muted() == false)
	assert_almost_eq(_mix.music_db(), linear_to_db(0.6), 0.01)

func test_zero_volume_is_silent_even_when_unmuted() -> void:
	_setup_audio_mix()
	_mix.set_muted(false)
	_mix.set_sfx(0.0)
	assert_eq(_mix.sfx_db(), AudioMix.MUTE_DB)

func test_save_and_load_round_trip() -> void:
	_setup_audio_mix()
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
	_setup_audio_mix()
	var fresh := AudioMix.new()
	assert_false(fresh.load_from("user://definitely_not_saved.cfg"))
	assert_almost_eq(fresh.music, AudioMix.MUSIC_DEFAULT, 0.001)
	assert_false(fresh.muted)

func test_reset_restores_shipping_defaults() -> void:
	_setup_audio_mix()
	_mix.set_music(0.1)
	_mix.set_sfx(0.1)
	_mix.set_muted(true)
	_mix.reset()
	assert_almost_eq(_mix.music, AudioMix.MUSIC_DEFAULT, 0.001)
	assert_almost_eq(_mix.sfx, AudioMix.SFX_DEFAULT, 0.001)
	assert_false(_mix.muted)

# --- test_audio_director ---

func _audio_director_remove_temp() -> void:
	if FileAccess.file_exists(audio_director_TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_director_TEMP_PATH))

func test_unknown_events_are_refused() -> void:
	_setup_audio_director()
	assert_false(_director.play_event("kraken_scream"))
	assert_eq(_director.sfx_played, 0)
	assert_eq(_director.last_event, "")

func test_a_known_cue_plays_on_a_pooled_voice() -> void:
	_setup_audio_director()
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
	_setup_audio_director()
	for _step in AudioDirector.SFX_VOICES * 3:
		_director.play_event(AudioEvents.UI_CLICK)
	assert_eq(_director._sfx.size(), AudioDirector.SFX_VOICES)
	assert_eq(_director.sfx_played, AudioDirector.SFX_VOICES * 3)

func test_music_beds_load_and_loop() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_eq(_director.current_track_id(), MusicPlaylist.SPANISH_MAIN)
	var stream := _director._active_player().stream as AudioStreamOggVorbis
	assert_not_null(stream)
	assert_true(stream.loop)
	assert_true(_director._ambience.playing)

func test_unknown_beds_are_refused() -> void:
	_setup_audio_director()
	assert_false(_director.play_music("sea_shanty_404"))
	assert_eq(_director.current_track_id(), "")

func test_restarting_the_same_bed_does_not_restart_playback() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	var player: AudioStreamPlayer = _director._active_player()
	var playback: float = player.get_playback_position()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_eq(_director._active_player(), player)
	assert_almost_eq(_director._active_player().get_playback_position(), playback, 0.5)

func test_switching_beds_crossfades_to_the_other_player() -> void:
	_setup_audio_director()
	_director.play_music(MusicPlaylist.AGE_OF_DISCOVERY)
	var first: AudioStreamPlayer = _director._active_player()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	assert_ne(_director._active_player(), first)
	assert_eq(_director.current_track_id(), MusicPlaylist.SPANISH_MAIN)

func test_mute_silences_the_bed_and_the_ambience() -> void:
	_setup_audio_director()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	_director.set_muted(true)
	assert_eq(_director._active_player().volume_db, AudioDirector.SILENT_DB)
	assert_eq(_director._ambience.volume_db, AudioDirector.SILENT_DB)
	_director.set_muted(false)
	assert_almost_eq(_director._active_player().volume_db,
		linear_to_db(_director.mix.music), 0.01)

func test_volume_changes_are_clamped_and_broadcast() -> void:
	_setup_audio_director()
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
	_setup_audio_director()
	assert_false(_director.is_muted())
	_director.toggle_mute()
	assert_true(_director.is_muted())
	_director.toggle_mute()
	assert_false(_director.is_muted())

func test_stingers_play_without_stopping_the_bed() -> void:
	_setup_audio_director()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	var bed: AudioStreamPlayer = _director._active_player()
	assert_true(_director.play_stinger(MusicPlaylist.VICTORY))
	assert_eq(_director._active_player(), bed)
	assert_true(bed.playing)
	assert_false((_director._sfx[0].stream as AudioStreamOggVorbis).loop)

func test_mix_settings_persist_to_disk() -> void:
	_setup_audio_director()
	_director.set_music_volume(0.33)
	_director.set_muted(true)
	_director._save_timer.timeout.emit()
	var reloaded := AudioMix.new()
	assert_true(reloaded.load_from(audio_director_TEMP_PATH))
	assert_almost_eq(reloaded.music, 0.33, 0.01)
	assert_true(reloaded.muted)

# --- map_soundtrack ---
## Integration: the score — the app shell's launch bed, the real map screen's era
## beds, cues on player moments, battle music and the sound seals (REQ-P1-06).

const Fixture = preload("res://tests/map_fixture.gd")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const map_soundtrack_TEMP_PATH := "user://test_map_soundtrack.cfg"

var _screen: MapScreen = null
var _audio: AudioDirector = null
var _score: MapSoundtrack = null
## Lazily filled on the first soundtrack mount so shell cases can restore the chart.
var world_snapshot: Array = []


func _setup_map_soundtrack() -> void:
	_teardown_map_soundtrack()
	_suite_setup = "map_soundtrack"
	if world_snapshot.is_empty():
		world_snapshot = Fixture.snapshot(Fixture.world())
	Fixture.restore(Fixture.world(), world_snapshot)
	_screen = Fixture.attach_screen(self)
	_audio = _screen.get_node("Audio") as AudioDirector
	# Keep the suite's mix out of the player's own settings file.
	_audio.settings_path = map_soundtrack_TEMP_PATH
	_score = _screen.get_node("Soundtrack") as MapSoundtrack


func _teardown_map_soundtrack() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	_audio = null
	_score = null
	Fixture.restore(Fixture.world(), world_snapshot)
	if FileAccess.file_exists(map_soundtrack_TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(map_soundtrack_TEMP_PATH))


func test_the_campaign_opens_on_the_renaissance_bed() -> void:
	_setup_map_soundtrack()
	assert_not_null(_audio)
	assert_not_null(_score)
	assert_eq(_audio.current_track_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(_audio.last_track_id, MusicPlaylist.AGE_OF_DISCOVERY)


func test_the_soundtrack_wires_the_director() -> void:
	_setup_map_soundtrack()
	assert_eq(_score.audio, _audio)
	assert_eq(_score.screen, _screen)


func test_selecting_a_province_plays_a_cue_pair() -> void:
	_setup_map_soundtrack()
	var before: int = _audio.sfx_played
	var province_id: int = Fixture.inland_province(_screen.model)
	MapPlayInput.on_tapped(
		_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	assert_eq(_audio.last_event, AudioEvents.PANEL_OPEN)
	assert_eq(_audio.sfx_played, before + 2)


func test_clearing_the_selection_closes_the_panel_audibly() -> void:
	_setup_map_soundtrack()
	var inland: Vector2 = (
		_screen.model.province_center(Fixture.inland_province(_screen.model))
		* MapScreen.TILE_SIZE
	)
	MapPlayInput.on_tapped(_screen.play, inland)
	MapPlayInput.deselect(_screen.play)
	assert_eq(_audio.last_event, AudioEvents.PANEL_CLOSE)


func test_deselecting_a_fleet_does_not_sound_another_selection() -> void:
	_setup_map_soundtrack()
	_screen.ship_layer.select(_screen.ship_layer.ships[0])
	assert_eq(_audio.last_event, AudioEvents.FLEET_SELECT)
	MapPlayInput.deselect(_screen.play)
	assert_eq(_audio.last_event, AudioEvents.PANEL_CLOSE)


func test_civilian_selection_and_moves_sound() -> void:
	_setup_map_soundtrack()
	var unit: CivilianState = _screen.civilian_layer.units[0]
	_screen.civilian_layer.select(unit)
	assert_eq(_audio.last_event, AudioEvents.CIVILIAN_SELECT)
	var before: int = _audio.sfx_played
	_screen.civilian_layer.unit_moved.emit(unit, {"ok": true})
	assert_eq(_audio.last_event, AudioEvents.CIVILIAN_MOVE)
	_screen.civilian_layer.unit_moved.emit(unit, {"ok": false, "reason": "blocked"})
	assert_eq(_audio.last_event, AudioEvents.ORDER_DENIED)
	assert_eq(_audio.sfx_played, before + 2)


func test_ending_a_turn_rings_the_bell_and_coins() -> void:
	_setup_map_soundtrack()
	var before: int = _audio.sfx_played
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_audio.last_event, AudioEvents.COIN)
	assert_gte(_audio.sfx_played, before + 2)


func test_selecting_a_fleet_sounds_the_ship_bell() -> void:
	_setup_map_soundtrack()
	var ship: Ship = _screen.ship_layer.ships[0]
	_screen.ship_layer.select(ship)
	assert_eq(_audio.last_event, AudioEvents.FLEET_SELECT)


func test_a_battle_brings_the_battle_bed_and_a_salute() -> void:
	_setup_map_soundtrack()
	_screen.turn = 30
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), MusicPlaylist.SPANISH_MAIN)

	var battle: Dictionary = {
		"zone": 0,
		"attacker": MapScreen.PLAYER_FACTION,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["hull_a"],
	}
	var before: int = _audio.sfx_played
	_score._on_battle_resolved([battle] as Array[Dictionary])
	assert_eq(_audio.current_track_id(), MusicPlaylist.BROADSIDES)
	assert_gte(_audio.sfx_played, before + 2)


func test_a_battle_bed_survives_the_turn_end() -> void:
	_setup_map_soundtrack()
	var battle: Dictionary = {
		"zone": 0,
		"attacker": MapScreen.PLAYER_FACTION,
		"defender": 1,
		"outcome": NavalCombat.Outcome.STALEMATE,
		"attacker_lost": [],
		"defender_lost": [],
	}
	_score._on_battle_resolved([battle] as Array[Dictionary])
	assert_eq(_audio.current_track_id(), MusicPlaylist.BROADSIDES)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_audio.current_track_id(), MusicPlaylist.BROADSIDES)


## A siege answers with its battery, and a silenced battery lets the stone fall:
## the breach cue lands last so the player hears the wall come down.
func test_a_siege_plays_its_battery_and_the_breach() -> void:
	_setup_map_soundtrack()
	var battle: Dictionary = {
		"attacker": MapScreen.PLAYER_FACTION,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"battle_mode": "siege",
		"fort_level": 1,
		"quick": {"fort_downgraded": true, "fort_after": 0},
		"attacker_lost": [],
		"defender_lost": [],
	}
	var before: int = _audio.sfx_played

	_score._on_battle_resolved([battle] as Array[Dictionary])

	assert_eq(_audio.last_event, AudioEvents.WALL_BREACH, "the breach lands last")
	assert_gte(_audio.sfx_played, before + 2, "battery and breach both sound")


func test_a_lost_battle_plays_the_knell() -> void:
	_setup_map_soundtrack()
	var battle: Dictionary = {
		"zone": 0,
		"attacker": 1,
		"defender": MapScreen.PLAYER_FACTION,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["hull_a"],
	}
	assert_eq(_score._player_outcome([battle] as Array[Dictionary]), -1)
	assert_eq(_score._player_outcome([]), 0)


func test_the_era_bed_follows_the_calendar() -> void:
	_setup_map_soundtrack()
	_screen.turn = 101
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), MusicPlaylist.GILDED_MINUET)


## The map carries no sound seal: the mix desk lives in its pause menu, wired
## to the same director the score uses (REQ-P1-06).
func test_the_pause_menu_desk_drives_the_mix() -> void:
	_setup_map_soundtrack()
	var desk: SoundDesk = _screen.game_menu.sound_desk
	assert_not_null(desk, "the map folds the mix desk into its pause menu")
	_screen.game_menu.open()
	assert_not_null(desk.music, "the desk arrives with the menu")

	desk.music.value = 0.2
	assert_almost_eq(_audio.mix.music, 0.2, 0.01)
	desk.sfx.value = 0.45
	assert_almost_eq(_audio.mix.sfx, 0.45, 0.01)

	desk.mute.button_pressed = true
	desk.mute.pressed.emit()
	assert_true(_audio.is_muted())
	_screen.game_menu.close()


func test_the_desk_shows_the_authoritative_mix() -> void:
	_setup_map_soundtrack()
	var desk: SoundDesk = _screen.game_menu.sound_desk
	assert_not_null(desk)
	_audio.set_muted(true)
	assert_true(desk.mute.button_pressed)
	assert_eq(desk.mute.text, "UNMUTE")
	_audio.set_muted(false)
	assert_false(desk.mute.button_pressed)


func test_the_mute_key_is_bound() -> void:
	_setup_map_soundtrack()
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.MUTE))
	var keys: Array = InputMap.action_get_events(InputActions.MUTE)
	assert_gt(keys.size(), 0)


# --- app shell ---------------------------------------------------------------


func _boot_shell() -> Node:
	# Drop the map-screen mount from `_setup_map_soundtrack` so the shell and the screen
	# never share one WorldMap instance under the same suite.
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	_audio = null
	_score = null
	Fixture.restore(Fixture.world(), world_snapshot)
	var app: Node = MAIN.instantiate()
	app.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	# Observer / campaign doors reuse the shared chart so shell cases do not
	# roll a world under coverage just to assert the score.
	app.preset_world = Fixture.world()
	add_child(app)
	# Keep the shell's mix out of the player's own settings file.
	app.audio.settings_path = map_soundtrack_TEMP_PATH
	app.audio.set_music_volume(AudioMix.MUSIC_DEFAULT)
	app.audio.set_sfx_volume(AudioMix.SFX_DEFAULT)
	app.audio.set_muted(false)
	return app


## M is the shell's shortcut now, so it answers before any page claims the key.
func _press_mute_key() -> void:
	InputActions.ensure_actions()
	var down := InputEventKey.new()
	down.physical_keycode = KEY_M
	down.pressed = true
	get_viewport().push_input(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_M
	up.pressed = false
	get_viewport().push_input(up)


func test_the_title_screen_opens_on_the_sea_bed() -> void:
	_setup_map_soundtrack()
	var app: Node = _boot_shell()
	assert_true(app.current_page is MainMenu, "the title screen is the entry point")
	assert_eq(MusicPlaylist.menu_bed_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(app.audio.current_track_id(), MusicPlaylist.menu_bed_id())
	assert_true(app.audio._ambience.playing, "the swell joins the launch bed")
	app.free()


func test_the_title_page_carries_the_sound_seal() -> void:
	_setup_map_soundtrack()
	var app: Node = _boot_shell()
	var seal: AudioControls = (app.current_page as MainMenu).audio_controls
	assert_not_null(seal, "the launch page offers the mix desk")
	seal.music_slider().value = 0.25
	assert_almost_eq(app.audio.mix.music, 0.25, 0.01)
	seal._trigger.pressed.emit()
	assert_true(seal.is_open(), "the desk opens over the title")
	seal.mute_button().button_pressed = true
	seal.mute_button().pressed.emit()
	assert_true(app.audio.is_muted(), "the title desk silences the score")
	assert_true(seal.mute_button().button_pressed, "the seal mirrors the mix")
	seal.mute_button().button_pressed = false
	seal.mute_button().pressed.emit()
	assert_false(app.audio.is_muted())
	app.free()


func test_a_campaign_takes_the_launch_director_over() -> void:
	_setup_map_soundtrack()
	var app: Node = _boot_shell()
	(app.current_page as MainMenu).observer_pressed.emit()
	var screen: MapScreen = app.current_screen
	assert_not_null(screen, "the debug door installs a campaign")
	if screen == null:
		app.free()
		return
	var score: MapSoundtrack = screen.get_node("Soundtrack") as MapSoundtrack
	assert_eq(score.audio, app.audio, "the campaign shares the shell director")
	assert_eq(
		app.audio.current_track_id(), MusicPlaylist.menu_bed_id(),
		"the launch bed keeps playing into the first turn"
	)
	assert_true(app.audio._active_player().playing, "the bed never stopped")
	await get_tree().process_frame
	assert_null(screen.get_node_or_null("Audio"), "the scene's own director retires")
	app.free()


func test_the_title_bed_is_the_bed_the_campaign_opens_on() -> void:
	_setup_map_soundtrack()
	assert_eq(
		MusicPlaylist.menu_bed_id(),
		MusicPlaylist.bed_id_for_year(TurnTime.START_YEAR)
	)


func test_returning_to_the_title_brings_the_sea_bed_back() -> void:
	_setup_map_soundtrack()
	var app: Node = _boot_shell()
	(app.current_page as MainMenu).observer_pressed.emit()
	assert_not_null(app.current_screen)
	if app.current_screen == null:
		app.free()
		return
	app.audio.play_music(MusicPlaylist.BROADSIDES)
	assert_eq(app.audio.current_track_id(), MusicPlaylist.BROADSIDES)
	app.current_screen.main_menu_requested.emit()
	assert_true(app.current_page is MainMenu, "the title comes back")
	assert_eq(app.audio.current_track_id(), MusicPlaylist.menu_bed_id())
	app.free()


func test_the_mute_shortcut_answers_on_the_title_screen() -> void:
	_setup_map_soundtrack()
	var app: Node = _boot_shell()
	var before: bool = app.audio.is_muted()
	_press_mute_key()
	assert_eq(app.audio.is_muted(), not before, "M silences the launch bed")
	_press_mute_key()
	assert_eq(app.audio.is_muted(), before, "M restores the mix")
	app.free()
