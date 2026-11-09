extends Node
## Application shell: title screen -> game setup / load -> map screen, plus the
## in-game menu's return and load intents. Loading rebuilds the whole screen so
## no state from the previous game survives.

const MAP_SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const MAIN_MENU: PackedScene = preload("res://scenes/main_menu.tscn")
const GAME_SETUP: PackedScene = preload("res://scenes/game_setup.tscn")
const SAVE_BROWSER: PackedScene = preload("res://scenes/save_browser.tscn")

## Overridable for tests / e2e smoke (set before add_child).
var auto_start: bool = false
var map_width: int = 128
var map_height: int = 84
var map_seed: int = GameConfig.DEFAULT_SEED
var player_faction: int = FactionCatalog.PLAYER_FACTION
## Tests may pin the generated size while still driving the real setup screen.
var size_override: Vector2i = Vector2i.ZERO

var current_page: Node = null
var current_screen: MapScreen = null


func _ready() -> void:
	InputActions.ensure_actions()
	# One HUD unit == one point on handhelds; a no-op on desktop.
	PlatformDisplay.apply(get_window())
	if auto_start:
		_start_new_game(_default_config())
	else:
		_show_main_menu()


func _default_config() -> GameConfig:
	var config := GameConfig.make(
		map_seed, GameConfig.DEFAULT_SIZE_INDEX, player_faction
	)
	config.map_width = map_width
	config.map_height = map_height
	return config


# --- pages -------------------------------------------------------------------


func _show_main_menu(notice: String = "") -> void:
	_clear_page()
	var menu: MainMenu = MAIN_MENU.instantiate()
	menu.new_game_pressed.connect(_show_setup)
	menu.load_game_pressed.connect(_show_main_load)
	menu.quit_pressed.connect(func() -> void: get_tree().quit())
	add_child(menu)
	menu.set_notice(notice)
	current_page = menu


func _show_setup() -> void:
	_clear_page()
	var setup: GameSetupScreen = GAME_SETUP.instantiate()
	setup.start_requested.connect(_start_new_game)
	setup.back_pressed.connect(_back_to_menu)
	add_child(setup)
	current_page = setup


func _show_main_load() -> void:
	_clear_page()
	var browser: SaveBrowser = SAVE_BROWSER.instantiate()
	browser.slot_chosen.connect(_load_save)
	browser.back_pressed.connect(_back_to_menu)
	add_child(browser)
	browser.setup(SaveBrowser.Mode.LOAD)
	current_page = browser


## Android delivers the back request to every node in the tree, so a page that
## swaps itself out synchronously hands the same event to the page it just
## installed — the freshly built title screen would then quit the app. Swap on
## the next idle frame instead (REQ-P5-01, REQ-P5-07).
func _back_to_menu() -> void:
	_show_main_menu.call_deferred()


# --- games -------------------------------------------------------------------


func _start_new_game(config: GameConfig) -> void:
	if size_override.x > 0 and size_override.y > 0:
		config.map_width = size_override.x
		config.map_height = size_override.y
	var screen: MapScreen = _new_screen()
	screen.map_seed = config.map_seed
	screen.map_width = config.map_width
	screen.map_height = config.map_height
	screen.player_faction = config.player_faction
	screen.player_leader = config.player_leader
	screen.infinite_mode = config.infinite_mode
	_install_screen(screen)


func _load_save(slot: int) -> void:
	var dir: String = current_screen.save_dir if current_screen != null else SaveStore.DIR
	var data: Dictionary = SaveStore.load_slot(slot, dir)
	if not SaveCodec.is_valid(data):
		_show_main_menu("That save could not be read.")
		return
	var screen: MapScreen = _new_screen()
	screen.save_dir = dir
	screen.pending_save = data
	_install_screen(screen)


func _new_screen() -> MapScreen:
	var screen: MapScreen = MAP_SCREEN.instantiate()
	screen.load_slot_requested.connect(_load_save)
	screen.main_menu_requested.connect(func() -> void: _show_main_menu())
	return screen


func _install_screen(screen: MapScreen) -> void:
	_clear_page()
	add_child(screen)
	current_page = screen
	current_screen = screen


# --- lifecycle ---------------------------------------------------------------


func _clear_page() -> void:
	get_tree().paused = false
	if current_page != null:
		if current_page.get_parent() == self:
			remove_child(current_page)
		current_page.queue_free()
	current_page = null
	current_screen = null
