extends GdToolsTest
## Integration: the score — the app shell's launch bed, the real map screen's era
## beds, cues on player moments, battle music and the sound seals (REQ-P1-06).

const Fixture = preload("res://tests/map_fixture.gd")
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const TEMP_PATH := "user://test_map_soundtrack.cfg"

var _screen: MapScreen = null
var _audio: AudioDirector = null
var _score: MapSoundtrack = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)
	_audio = _screen.get_node("Audio") as AudioDirector
	# Keep the suite's mix out of the player's own settings file.
	_audio.settings_path = TEMP_PATH
	_score = _screen.get_node("Soundtrack") as MapSoundtrack


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	_audio = null
	_score = null
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_the_campaign_opens_on_the_renaissance_bed() -> void:
	assert_not_null(_audio)
	assert_not_null(_score)
	assert_eq(_audio.current_track_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(_audio.last_track_id, MusicPlaylist.AGE_OF_DISCOVERY)


func test_the_soundtrack_wires_the_director() -> void:
	assert_eq(_score.audio, _audio)
	assert_eq(_score.screen, _screen)


func test_selecting_a_province_plays_a_cue_pair() -> void:
	var before: int = _audio.sfx_played
	var province_id: int = Fixture.inland_province(_screen.model)
	MapPlayInput.on_tapped(
		_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	assert_eq(_audio.last_event, AudioEvents.PANEL_OPEN)
	assert_eq(_audio.sfx_played, before + 2)


func test_clearing_the_selection_closes_the_panel_audibly() -> void:
	var inland: Vector2 = (
		_screen.model.province_center(Fixture.inland_province(_screen.model))
		* MapScreen.TILE_SIZE
	)
	MapPlayInput.on_tapped(_screen.play, inland)
	MapPlayInput.deselect(_screen.play)
	assert_eq(_audio.last_event, AudioEvents.PANEL_CLOSE)


func test_deselecting_a_fleet_does_not_sound_another_selection() -> void:
	_screen.ship_layer.select(_screen.ship_layer.ships[0])
	assert_eq(_audio.last_event, AudioEvents.FLEET_SELECT)
	MapPlayInput.deselect(_screen.play)
	assert_eq(_audio.last_event, AudioEvents.PANEL_CLOSE)


func test_civilian_selection_and_moves_sound() -> void:
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
	var before: int = _audio.sfx_played
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_audio.last_event, AudioEvents.COIN)
	assert_gte(_audio.sfx_played, before + 2)


func test_selecting_a_fleet_sounds_the_ship_bell() -> void:
	var ship: Ship = _screen.ship_layer.ships[0]
	_screen.ship_layer.select(ship)
	assert_eq(_audio.last_event, AudioEvents.FLEET_SELECT)


func test_a_battle_brings_the_battle_bed_and_a_salute() -> void:
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
	_screen.turn = 101
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), MusicPlaylist.GILDED_MINUET)


func test_the_sound_seal_opens_and_drives_the_mix() -> void:
	var controls := _screen.hud.get_node("AudioControls") as AudioControls
	assert_not_null(controls)
	assert_false(controls.is_open())
	controls._trigger.pressed.emit()
	assert_true(controls.is_open())

	controls.music_slider().value = 0.2
	assert_almost_eq(_audio.mix.music, 0.2, 0.01)
	controls.sfx_slider().value = 0.45
	assert_almost_eq(_audio.mix.sfx, 0.45, 0.01)

	controls._mute.button_pressed = true
	controls._mute.pressed.emit()
	assert_true(_audio.is_muted())
	controls.close_panel()
	assert_false(controls.is_open())


func test_the_seal_shows_the_authoritative_mix() -> void:
	var controls := _screen.hud.get_node("AudioControls") as AudioControls
	_audio.set_muted(true)
	assert_true(controls._mute.button_pressed)
	assert_eq(controls._mute.text, "UNMUTE")
	_audio.set_muted(false)
	assert_false(controls._mute.button_pressed)


func test_the_mute_key_is_bound() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.MUTE))
	var keys: Array = InputMap.action_get_events(InputActions.MUTE)
	assert_gt(keys.size(), 0)


# --- app shell ---------------------------------------------------------------


func _boot_shell() -> Node:
	var app: Node = MAIN.instantiate()
	app.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	add_child(app)
	# Keep the shell's mix out of the player's own settings file.
	app.audio.settings_path = TEMP_PATH
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
	var app: Node = _boot_shell()
	assert_true(app.current_page is MainMenu, "the title screen is the entry point")
	assert_eq(MusicPlaylist.menu_bed_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(app.audio.current_track_id(), MusicPlaylist.menu_bed_id())
	assert_true(app.audio._ambience.playing, "the swell joins the launch bed")
	app.free()


func test_the_title_page_carries_the_sound_seal() -> void:
	var app: Node = _boot_shell()
	var seal: AudioControls = (app.current_page as MainMenu).audio_controls
	assert_not_null(seal, "the launch page offers the mix desk")
	seal.music_slider().value = 0.25
	assert_almost_eq(app.audio.mix.music, 0.25, 0.01)
	seal._trigger.pressed.emit()
	assert_true(seal.is_open(), "the desk opens over the title")
	seal._mute.button_pressed = true
	seal._mute.pressed.emit()
	assert_true(app.audio.is_muted(), "the title desk silences the score")
	assert_true(seal.mute_button().button_pressed, "the seal mirrors the mix")
	seal._mute.button_pressed = false
	seal._mute.pressed.emit()
	assert_false(app.audio.is_muted())
	app.free()


func test_a_campaign_takes_the_launch_director_over() -> void:
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
	assert_eq(
		MusicPlaylist.menu_bed_id(),
		MusicPlaylist.bed_id_for_year(TurnTime.START_YEAR)
	)


func test_returning_to_the_title_brings_the_sea_bed_back() -> void:
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
	var app: Node = _boot_shell()
	var before: bool = app.audio.is_muted()
	_press_mute_key()
	assert_eq(app.audio.is_muted(), not before, "M silences the launch bed")
	_press_mute_key()
	assert_eq(app.audio.is_muted(), before, "M restores the mix")
	app.free()
