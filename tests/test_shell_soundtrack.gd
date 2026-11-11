extends GdToolsTest
## App-shell score: the sea bed starts with the title screen at launch, one
## director carries it into the campaign, and the mute shortcut answers on every
## page (REQ-P1-06).

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const Fixture = preload("res://tests/map_fixture.gd")
const TEMP_PATH := "user://test_shell_soundtrack.cfg"

var _app: Node = null


func before_each() -> void:
	_clean()
	_app = _boot()


func after_each() -> void:
	if is_instance_valid(_app):
		_app.free()
	_app = null
	_clean()


func _clean() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _boot() -> Node:
	var app: Node = load("res://scenes/main.tscn").instantiate()
	app.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	app.map_width = Fixture.WORLD_WIDTH
	app.map_height = Fixture.WORLD_HEIGHT
	add_child(app)
	# Keep the mix away from the player's own settings file.
	app.audio.settings_path = TEMP_PATH
	app.audio.set_music_volume(AudioMix.MUSIC_DEFAULT)
	app.audio.set_sfx_volume(AudioMix.SFX_DEFAULT)
	app.audio.set_muted(false)
	return app


## The M action belongs to the shell now, so it must answer before any page
## claims the key.
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


# --- launch ------------------------------------------------------------------


func test_the_title_screen_opens_on_the_sea_bed() -> void:
	assert_true(_app.current_page is MainMenu, "the title screen is the entry point")
	assert_eq(MusicPlaylist.menu_bed_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(_app.audio.current_track_id(), MusicPlaylist.menu_bed_id())
	assert_true(_app.audio._ambience.playing, "the swell joins the launch bed")


func test_the_title_page_carries_the_sound_seal() -> void:
	var menu: MainMenu = _app.current_page as MainMenu
	assert_not_null(menu.audio_controls, "the launch page offers the mix desk")
	var seal: AudioControls = menu.audio_controls
	seal.music_slider().value = 0.25
	assert_almost_eq(_app.audio.mix.music, 0.25, 0.01)
	seal.sfx_slider().value = 0.4
	assert_almost_eq(_app.audio.mix.sfx, 0.4, 0.01)
	seal._trigger.pressed.emit()
	assert_true(seal.is_open(), "the desk opens over the title")
	seal._mute.button_pressed = true
	seal._mute.pressed.emit()
	assert_true(_app.audio.is_muted(), "the title desk silences the score")
	assert_true(seal.mute_button().button_pressed, "the seal mirrors the mix")
	seal._mute.button_pressed = false
	seal._mute.pressed.emit()
	assert_false(_app.audio.is_muted())


# --- hand-off ----------------------------------------------------------------


func test_a_campaign_takes_the_launch_director_over() -> void:
	var menu: MainMenu = _app.current_page as MainMenu
	menu.observer_pressed.emit()
	var screen: MapScreen = _app.current_screen
	assert_not_null(screen, "the debug door installs a campaign")
	if screen == null:
		return
	var score: MapSoundtrack = screen.get_node("Soundtrack") as MapSoundtrack
	assert_eq(score.audio, _app.audio, "the campaign shares the shell director")
	assert_eq(
		_app.audio.current_track_id(), MusicPlaylist.menu_bed_id(),
		"the launch bed keeps playing into the first turn"
	)
	assert_true(_app.audio._active_player().playing, "the bed never stopped")


func test_the_title_bed_is_the_bed_the_campaign_opens_on() -> void:
	assert_eq(
		MusicPlaylist.menu_bed_id(),
		MusicPlaylist.bed_id_for_year(TurnTime.START_YEAR)
	)


func test_returning_to_the_title_brings_the_sea_bed_back() -> void:
	var menu: MainMenu = _app.current_page as MainMenu
	menu.observer_pressed.emit()
	assert_not_null(_app.current_screen)
	if _app.current_screen == null:
		return
	_app.audio.play_music(MusicPlaylist.BROADSIDES)
	assert_eq(_app.audio.current_track_id(), MusicPlaylist.BROADSIDES)
	_app.current_screen.main_menu_requested.emit()
	assert_true(_app.current_page is MainMenu, "the title comes back")
	assert_eq(_app.audio.current_track_id(), MusicPlaylist.menu_bed_id())


# --- mute --------------------------------------------------------------------


func test_the_mute_shortcut_answers_on_the_title_screen() -> void:
	var before: bool = _app.audio.is_muted()
	_press_mute_key()
	assert_eq(_app.audio.is_muted(), not before, "M silences the launch bed")
	_press_mute_key()
	assert_eq(_app.audio.is_muted(), before, "M restores the mix")