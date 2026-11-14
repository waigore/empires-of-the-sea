class_name MapScreen
extends Node2D
## Map screen host: builds the world, hands the camera + HUD to the session and
## turns input into intents. Presentation only — no rule outcomes are decided
## here. Region mounting is MapPlayRegion's, view wiring MapPlayWiring's, and
## play steps live on MapPlay* against PlaySession (REQ-P3-02).
## Presentation moments are broadcast as signals; audio/motion listen.

signal province_selected(province_id: int)
signal selection_cleared
signal coast_charted(province_id: int)
signal battle_resolved(battles: Array[Dictionary])
## Hostile patrols and the crown's own stations worked the sea this turn
## (DR-20261110-13): audio and rings answer, the rules already applied.
signal raid_resolved(raids: Array[Dictionary])
signal turn_ended(turn: int)
## The rules decided the campaign or the human crown fell; audio/motion listen.
signal victory_declared(victory: VictoryState)
signal defeat_declared(defeat: DefeatState)
## In-game menu intents; the app router owns screen replacement.
signal load_slot_requested(slot: int)
signal main_menu_requested

const TILE_SIZE: float = PlaySession.TILE_SIZE
## The chart recipe seed and the opening roster live with the mount owner; kept
## here for callers/tests that still name the screen.
const MAP_SEED: int = MapPlayRegion.MAP_SEED
## Kept for callers/tests that assume the default human slot; the live value is
## play.player_faction.
const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION
const SHIP_COUNT: int = MapPlayRegion.SHIP_COUNT
const STARTING_CIVILIANS: Array[String] = MapPlayRegion.STARTING_CIVILIANS

var play: PlaySession = null
var map_seed: int = MAP_SEED
var map_width: int = 128
var map_height: int = 84
## Human Great Power chosen in game setup (Spain by default).
var player_faction: int = FactionCatalog.PLAYER_FACTION
## LeaderKey chosen for that crown; empty means the crown's configured leader.
var player_leader: String = ""
## Endless campaign chosen in game setup (wiki: turn-time-mapping).
var infinite_mode: bool = false
var advanced_start: String = AdvancedStart.NONE
## Difficulty at setup (wiki: ruleset-config § Layers).
var difficulty: String = Difficulty.DEFAULT
## Full-AI observer: every Great Power is AI (title / tools/ai_vs_ai.gd;
## wiki: game-setup § Human/AI slot assignment).
var observer_mode: bool = false
## When set (load), skip generation and restore this save instead.
var pending_save: Dictionary = {}
## Overridable for tests so saves do not touch the player's slots.
var save_dir: String = SaveStore.DIR
## When set (tests), skip generation and load this world in `_ready`; loads reuse it.
var preset_world: WorldMap = null

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var overlay: MapOverlay = $World/MapOverlay
@onready var ship_layer: ShipLayer = $World/ShipLayer
@onready var civilian_layer: CivilianLayer = $World/CivilianLayer
@onready var army_layer: ArmyLayer = $World/ArmyLayer
@onready var camera: MapCamera = $World/MapCamera
@onready var hud: GameHud = $HUD/HudRoot
@onready var improvements: ImprovementPanel = $HUD/Improvements
@onready var game_menu: GameMenu = $GameMenu
@onready var fade: ColorRect = $FadeLayer/Fade

# Compat accessors for tests / e2e (session is source of truth).
var model: MapModel:
	get:
		return play.model if play != null else null
	set(value):
		if play != null:
			play.model = value

var visibility: VisibilityModel:
	get:
		return play.visibility if play != null else null
	set(value):
		if play != null:
			play.visibility = value

var economy: EconomyController:
	get:
		return play.economy if play != null else null
	set(value):
		if play != null:
			play.economy = value

var turn: int:
	get:
		return play.turn if play != null else 1
	set(value):
		if play != null:
			play.turn = value

var income: int:
	get:
		return play.income if play != null else 0
	set(value):
		if play != null:
			play.income = value

var selected_province: int:
	get:
		return play.selected_province if play != null else -1
	set(value):
		if play != null:
			play.selected_province = value

var capital_province: int:
	get:
		return play.capital_province if play != null else -1
	set(value):
		if play != null:
			play.capital_province = value

var capital_tile: Vector2i:
	get:
		return play.capital_tile if play != null else CapitalChoice.NO_TILE
	set(value):
		if play != null:
			play.capital_tile = value

var land_works: LandWorks:
	get:
		return play.land_works if play != null else null
	set(value):
		if play != null:
			play.land_works = value

var treasury: int:
	get:
		return play.treasury() if play != null else 0

var stockpile: Dictionary:
	get:
		return play.stockpile() if play != null else {}

var world: WorldMap:
	get:
		return play.world if play != null else null

var region_index: int:
	get:
		return play.region_index if play != null else 0


func _ready() -> void:
	InputActions.ensure_actions()
	play = PlaySession.new()
	play.bind_host(self)
	play.pause_menu = game_menu
	play.observer_mode = observer_mode
	play.bind_views(
		ship_layer, civilian_layer, army_layer, canvas, overlay, camera, hud, improvements,
		$World/ResourceLens, $World/DiplomacyLens
	)
	var restored: bool = SaveCodec.restore(play, pending_save, preset_world)
	if not restored:
		play.configure(
			player_faction, map_seed, map_width, map_height, player_leader,
			infinite_mode, advanced_start, difficulty
		)
		if preset_world != null:
			play.world = preset_world
		else:
			play.world = MapGenerator.new().generate_world(map_seed, map_width, map_height)
	else:
		player_faction = play.player_faction
		map_seed = play.map_seed
		map_width = play.map_width
		map_height = play.map_height
	# Economy always founds on the Old World; restore there, then return.
	var target_region: int = play.region_index
	if restored:
		play.region_index = 0
	load_region(play.region_index)
	MapPlaySetup.build_hud(play)
	if restored:
		SaveCodec.restore_economy(play, pending_save)
	play.diplomacy = DiplomacyState.new()
	if restored:
		SaveCodec.restore_diplomacy(play, pending_save)
	else:
		play.diplomacy.initialize(play.turn)
	play.diplomacy.human_faction = play.human_faction_id()
	# Mid-age opening (wiki: advanced-starts); a load already carries it.
	if not restored:
		MapPlayAdvanced.begin(play)
	if restored and target_region != play.region_index:
		load_region(target_region)
	MapPlayDiplomacy.sync_first_contact(play)
	MapPlaySetup.build_diplomacy_lens(play)
	_connect()
	if restored:
		MapPlaySetup.refresh_after_load(play)
	MapPlaySetup.intro(play, fade, not restored)
	if observer_mode:
		_setup_observer()
	pending_save = {}


func _process(_delta: float) -> void:
	MapPlayInput.update_hover(play)


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.is_quick_battle_shown(): return
	if event.is_action_pressed(InputActions.END_TURN):
		MapPlayTurn.end_turn(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.FOCUS_CAPITAL):
		MapPlaySetup.focus_capital(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.LENS):
		MapPlayInput.toggle_lens(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.DIPLOMACY_LENS):
		MapPlayInput.toggle_diplomacy_lens(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CANCEL):
		MapPlayInput.deselect(play)
		get_viewport().set_input_as_handled()


## Back: close the top layer first; quit only from the bare map (RUB-P5-07).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if game_menu != null and game_menu.handle_back():
		return
	if not BackRequest.handle(play, improvements):
		get_tree().quit()


## Swap the view onto one region: canvas, fog, units, works, minimap, camera.
## The host keeps the name (session, tests and the warp step call it); the
## mounting itself belongs to MapPlayRegion.
func load_region(index: int) -> void:
	MapPlayRegion.mount(play, sea_backdrop, index)


## Cycles Old World -> New World and back. Intents never change rules state.
func _cycle_region() -> void:
	MapPlayRegion.cycle(play, sea_backdrop)


## Every view signal names its owner in MapPlayWiring; the screen keeps the
## pause menu's seals and the region seal, which parks the frame around the
## mounted chart.
func _connect() -> void:
	MapPlayWiring.connect_views(play)
	hud.region_toggle_pressed.connect(_cycle_region)
	game_menu.save_chosen.connect(_on_save_chosen)
	game_menu.load_chosen.connect(_on_load_chosen)
	game_menu.main_menu_chosen.connect(func() -> void: main_menu_requested.emit())


func _on_save_chosen(slot: int) -> void:
	var ok: bool = SaveStore.save_slot(slot, SaveCodec.capture(play), save_dir)
	game_menu.show_save_result(ok, slot)


func _on_load_chosen(slot: int) -> void:
	load_slot_requested.emit(slot)


## Full-AI observatory: hide human chrome, seal saving, mount metrics (REQ-P5-02).
func _setup_observer() -> void:
	hud.visible = false
	game_menu.door.seal()  # panel owns the pause door
	game_menu.save_button.disabled = true
	var panel := AiObserverPanel.new()
	panel.name = "AiObserver"
	panel.play = play
	add_child(panel)
	turn_ended.connect(func(_turn: int) -> void: panel.refresh())
	panel.refresh()


## Ownership changed outside the map layers (Join Empire): redraw politics.
func refresh_political_map() -> void:
	MapPlayRegion.refresh_political(play)
