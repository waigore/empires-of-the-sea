extends Node
## Application shell: title screen -> game setup / load -> map screen, plus the
## in-game menu's return and load intents. Loading rebuilds the whole screen so
## no state from the previous game survives.

const MAP_SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const MAIN_MENU: PackedScene = preload("res://scenes/main_menu.tscn")
const GAME_SETUP: PackedScene = preload("res://scenes/game_setup.tscn")
const CAPITAL_CHOICE: PackedScene = preload("res://scenes/capital_choice.tscn")
const INTRO: PackedScene = preload("res://scenes/intro.tscn")
const SAVE_BROWSER: PackedScene = preload("res://scenes/save_browser.tscn")

## Overridable for tests / e2e smoke (set before add_child).
var auto_start: bool = false
var map_width: int = 128
var map_height: int = 84
var map_seed: int = GameConfig.DEFAULT_SEED
var player_faction: int = FactionCatalog.PLAYER_FACTION
## Tests may pin the generated size while still driving the real setup screen.
var size_override: Vector2i = Vector2i.ZERO
## Tests may hand a pre-rolled chart so capital-choice / observer / load paths
## skip `generate_world` under coverage (same object the campaign then plays).
var preset_world: WorldMap = null

## One director for the whole app: the title bed keeps playing into a campaign.
@onready var audio: AudioDirector = $Audio
@onready var soundtrack: ShellSoundtrack = $Soundtrack

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
	menu.observer_pressed.connect(_start_observer)
	menu.quit_pressed.connect(func() -> void: get_tree().quit())
	add_child(menu)
	menu.set_notice(notice)
	if menu.audio_controls != null:
		menu.audio_controls.bind(audio)
	soundtrack.play_menu_bed()
	current_page = menu


func _show_setup() -> void:
	_clear_page()
	var setup: GameSetupScreen = GAME_SETUP.instantiate()
	setup.start_requested.connect(_show_capital_choice)
	setup.back_pressed.connect(_back_to_menu)
	add_child(setup)
	current_page = setup


## The capital-choice phase sits between setup and the first turn (wiki:
## capital-choice-phase § Player choice). It generates the world once and hands
## that same world to the map screen, so the seat the player picks is the seat
## the campaign starts on.
func _show_capital_choice(config: GameConfig) -> void:
	_clear_page()
	if size_override.x > 0 and size_override.y > 0:
		config.map_width = size_override.x
		config.map_height = size_override.y
	var page: CapitalChoiceScreen = CAPITAL_CHOICE.instantiate()
	page.config = config
	if preset_world != null:
		page.world = preset_world
	page.capital_chosen.connect(_show_intro)
	page.back_pressed.connect(_back_to_setup)
	add_child(page)
	current_page = page


## The crown's charge sits between the chart and the first turn: one dismissal,
## no orders and no calendar until it is read (wiki: dialogue-management § Kinds,
## `game_start_intro`). A campaign already under way never repeats it, because a
## load installs the map screen directly.
func _show_intro(config: GameConfig, world: WorldMap) -> void:
	_clear_page()
	var page: IntroScreen = INTRO.instantiate()
	page.show_address(CampaignIntro.address(
		FactionCatalog.name_of(config.player_faction),
		LeaderCatalog.label(config.player_leader),
		_intro_seat(world, config.player_faction),
		AdvancedStart.turn(config.advanced_start),
		config.infinite_mode,
		CampaignIntro.salt(config.map_seed, config.player_faction),
		config.difficulty
	))
	page.begin_pressed.connect(_begin_game.bind(config, world))
	add_child(page)
	current_page = page


## The seat the chart just confirmed, by its display name: the charge is printed
## with a masked name, never a province id (wiki: naming § Naming Model).
func _intro_seat(world: WorldMap, faction: int) -> String:
	if world == null or world.region_count() < 1:
		return ""
	var model: MapModel = world.region(0)
	var province: int = CapitalChoice.seat_province(model, faction)
	return model.province_name(province)


## Back from the capital chart returns to the setup screen on the next idle
## frame, for the same Android-back reason as the title screen.
func _back_to_setup() -> void:
	_show_setup.call_deferred()


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
	_begin_game(config)


## Installs the map screen. `world` is the chart the capital-choice phase
## generated (null on the auto-start path, where the screen rolls its own).
func _begin_game(config: GameConfig, world: WorldMap = null) -> void:
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
	screen.advanced_start = config.advanced_start
	screen.difficulty = config.difficulty
	screen.preset_world = world if world != null else preset_world
	_install_screen(screen)


## Debug entry: an all-AI campaign on the new-game defaults (wiki: game-setup
## § Human/AI slot assignment — an empty human slot set is the full-AI observer).
func _start_observer() -> void:
	var config: GameConfig = _default_config()
	if size_override.x > 0 and size_override.y > 0:
		config.map_width = size_override.x
		config.map_height = size_override.y
	config.player_leader = LeaderCatalog.default_key(config.player_faction)
	# Only a whole-game observer may outlast the calendar cap (DR-20261108-05).
	config.infinite_mode = true
	var screen: MapScreen = _new_screen()
	screen.map_seed = config.map_seed
	screen.map_width = config.map_width
	screen.map_height = config.map_height
	screen.player_faction = config.player_faction
	screen.player_leader = config.player_leader
	screen.infinite_mode = true
	screen.observer_mode = true
	screen.preset_world = preset_world
	_install_screen(screen)


func _load_save(slot: int) -> void:
	var dir: String = current_screen.save_dir if current_screen != null else SaveStore.DIR
	var data: Dictionary = SaveStore.load_slot(slot, dir)
	if not SaveCodec.is_valid(data):
		# A refused load leaves the running campaign alone: the pause menu comes
		# back with the notice instead of the campaign being replaced by the
		# title screen (wiki: campaign-persistence § Load and resume).
		if current_screen != null:
			current_screen.game_menu.show_load_refused(SaveBrowser.UNREADABLE)
		else:
			_show_main_menu("That save could not be read.")
		return
	var screen: MapScreen = _new_screen()
	screen.save_dir = dir
	screen.pending_save = data
	# Same chart the campaign saved from: skip a second generate_world on load.
	screen.preset_world = preset_world
	_install_screen(screen)


## The map screen's score borrows the shell's director, so the bed already
## playing on the title screen carries into the first turn untouched.
func _new_screen() -> MapScreen:
	var screen: MapScreen = MAP_SCREEN.instantiate()
	var score: MapSoundtrack = screen.get_node("Soundtrack") as MapSoundtrack
	if score != null:
		score.audio = audio
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
