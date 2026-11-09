class_name MapScreen
extends Node2D
## Map screen controller: builds the world, wires camera + HUD, and turns input
## into intents. Presentation only — no rule outcomes are decided here.
## Play steps live on MapPlay* against PlaySession (REQ-P3-02).
## Presentation moments are broadcast as signals; audio/motion listen.

signal province_selected(province_id: int)
signal selection_cleared
signal coast_charted(province_id: int)
signal battle_resolved(battles: Array[Dictionary])
signal turn_ended(turn: int)
## The rules decided the campaign or the human crown fell; audio/motion listen.
signal victory_declared(victory: VictoryState)
signal defeat_declared(defeat: DefeatState)
## In-game menu intents; the app router owns screen replacement.
signal load_slot_requested(slot: int)
signal main_menu_requested

const TILE_SIZE: float = PlaySession.TILE_SIZE
const MAP_SEED: int = 1500
## Kept for callers/tests that assume the default human slot; the live value is
## play.player_faction.
const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION
const SHIP_COUNT: int = 7
const STARTING_CIVILIANS: Array[String] = ["explorer", "builder", "engineer"]

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

# --- compat accessors for tests / e2e (session is source of truth) -----------

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

var prestige: int:
	get:
		return play.prestige if play != null else 0
	set(value):
		if play != null:
			play.prestige = value

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
	play.bind_views(
		ship_layer, civilian_layer, army_layer, canvas, overlay, camera, hud, improvements,
		$World/ResourceLens
	)
	var restored: bool = SaveCodec.restore(play, pending_save, preset_world)
	if not restored:
		play.configure(player_faction, map_seed, map_width, map_height, player_leader, infinite_mode)
		if preset_world != null:
			play.world = preset_world
		else:
			play.world = MapGenerator.new().generate_world(map_seed, map_width, map_height)
	else:
		player_faction = play.player_faction
		map_seed = play.map_seed
		map_width = play.map_width
		map_height = play.map_height
	# The economy is always founded on the Old World, exactly as when the run
	# started; restore there first, then return to the saved map.
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
	play.diplomacy.human_faction = play.player_faction
	if restored and target_region != play.region_index:
		load_region(target_region)
	MapPlayDiplomacy.sync_first_contact(play)
	_connect()
	if restored:
		MapPlaySetup.refresh_after_load(play)
	MapPlaySetup.intro(play, fade, not restored)
	pending_save = {}


func _process(_delta: float) -> void:
	MapPlayInput.update_hover(play)

func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.is_quick_battle_shown(): return
	if event.is_action_pressed(InputActions.END_TURN):
		MapPlayTurn.end_turn(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.FOCUS_CAPITAL):
		MapPlayTurn.focus_capital(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.LENS):
		MapPlayInput.toggle_lens(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CANCEL):
		MapPlayInput.deselect(play)
		get_viewport().set_input_as_handled()


## Android back / iOS back gesture: close the top layer first, quit only from the
## bare map. Without this the OS kills the session mid-order (RUB-P5-07).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if game_menu != null and game_menu.handle_back():
		return
	if not BackRequest.handle(play, improvements):
		get_tree().quit()


# --- setup ------------------------------------------------------------------


## Swaps the whole view onto one region: canvas, fog, fleets, civilians, works,
## minimap and camera bounds all follow the active tile map.
func load_region(index: int) -> void:
	play.region_index = clampi(index, 0, play.world.region_count() - 1)
	play.model = play.world.region(play.region_index)
	ship_layer.world = play.world
	var map_size: Vector2 = MapGeo.world_size(play.model, TILE_SIZE)
	var margin: float = 1400.0
	sea_backdrop.position = Vector2(-margin, -margin)
	sea_backdrop.size = map_size + Vector2(margin, margin) * 2.0
	if sea_backdrop.material is ShaderMaterial:
		(sea_backdrop.material as ShaderMaterial).set_shader_parameter(
			"world_size", sea_backdrop.size
		)
	play.capital_province = MapPlaySetup.find_capital(play)
	play.capital_tile = MapPlayTurn.capital_tile(play, play.capital_province)
	# Prepare works first so the post-pass can wire them before units muster.
	if not play.bootstrapped_regions.has(play.region_index):
		civilian_layer.spawn(
			play.model, play.capital_province, play.player_faction, STARTING_CIVILIANS, false
		)
		_bootstrap_region(play)
	canvas.build(play.model, play.world)
	overlay.build(play.model)
	ship_layer.spawn(
		play.model, SHIP_COUNT, MAP_SEED + 3 + play.region_index, play.capital_province,
		play.player_present(), play.player_faction
	)
	army_layer.spawn(play.model)
	civilian_layer.spawn(
		play.model, play.capital_province, play.player_faction, STARTING_CIVILIANS
	)
	play.land_works = civilian_layer.works
	camera.configure(map_size)
	_build_visibility()
	overlay.snap_fog()
	MapPlayFleets.refresh_visibility(play)
	MapPlayArmies.refresh_visibility(play)
	MapPlaySetup.build_lens(play)
	MapPlaySetup.refresh_region_hud(play, map_size)


## Cycles Old World -> New World and back. Intents never change rules state.
func _cycle_region() -> void:
	if play.world == null or play.world.region_count() < 2:
		return
	MapPlayInput.deselect(play)
	load_region((play.region_index + 1) % play.world.region_count())
	MapPlayDiplomacy.sync_first_contact(play)
	MapPlayDiplomacy.refresh(play)
	camera.focus_on(MapPlayTurn.capital_world(play), maxf(camera.target_zoom, 0.75))
	RegionBriefing.arrival(hud, play.model, play.region_index)
	MapPlayInput.on_view_changed(play)


func _connect() -> void:
	camera.tapped.connect(func(p: Vector2) -> void: MapPlayInput.on_tapped(play, p))
	camera.view_changed.connect(func() -> void: MapPlayInput.on_view_changed(play))
	hud.end_turn_pressed.connect(func() -> void: MapPlayTurn.end_turn(play))
	hud.zoom_in_pressed.connect(camera.zoom_in)
	hud.zoom_out_pressed.connect(camera.zoom_out)
	hud.minimap_jump.connect(
		func(p: Vector2) -> void: MapPlayInput.on_minimap_jump(play, p)
	)
	hud.region_toggle_pressed.connect(_cycle_region)
	hud.lens_pressed.connect(func(active: bool) -> void: MapPlayInput.set_lens(play, active))
	hud.focus_capital_pressed.connect(func() -> void:
		MapPlayTurn.focus_capital(play)
	)
	hud.diplomacy_pressed.connect(func() -> void:
		MapPlayDiplomacy.open(play)
	)
	hud.diplomacy_order.connect(func(kind: String, target: int, arg: String) -> void:
		MapCourtOrders.apply(play, kind, target, arg)
	)
	hud.panel_action.connect(func(action: String) -> void:
		MapPlayInput.on_panel_action(play, action)
	)
	hud.panel_closed.connect(func() -> void: MapPlayInput.deselect(play))
	ship_layer.zone_entered.connect(func(zone_id: int, ship: Ship) -> void:
		MapPlayFleets.on_zone_entered(play, zone_id, ship)
	)
	ship_layer.ship_selected.connect(func(ship: Ship) -> void:
		MapPlayFleets.select(play, ship)
	)
	ship_layer.fleet_moved.connect(func(fleet: FleetState, result: Dictionary) -> void:
		MapPlayFleets.on_moved(play, fleet, result)
	)
	ship_layer.warp_crossed.connect(func(fleet: FleetState, result: Dictionary) -> void:
		MapPlayWarp.on_crossed(play, fleet, result)
	)
	army_layer.army_selected.connect(func(army: ArmyState) -> void:
		if army != null:
			MapPlayArmies.select(play, army)
		else:
			play.hud.panels.hide_army()
	)
	army_layer.army_moved.connect(func(army: ArmyState, result: Dictionary) -> void:
		MapPlayArmies.on_moved(play, army, result)
	)
	hud.army_action.connect(func(action: String) -> void:
		MapPlayArmies.on_action(play, action)
	)
	hud.army_closed.connect(func() -> void:
		MapPlayInput.deselect(play)
	)
	hud.fleet_closed.connect(func() -> void: MapPlayInput.deselect(play))
	hud.fleet_action.connect(func(action: String) -> void: MapPlayFleets.on_action(play, action))
	civilian_layer.unit_selected.connect(func(unit: CivilianState) -> void:
		MapPlayCivilians.select(play, unit)
	)
	civilian_layer.unit_moved.connect(func(unit: CivilianState, result: Dictionary) -> void:
		MapPlayCivilians.on_moved(play, unit, result)
	)
	hud.civilian_action.connect(func(action: String) -> void:
		MapPlayCivilians.on_action(play, action)
	)
	hud.civilian_cancel.connect(func() -> void:
		MapPlayCivilians.on_cancel(play)
	)
	hud.civilian_closed.connect(func() -> void:
		MapPlayInput.deselect(play)
	)
	improvements.action_pressed.connect(func(action: String, tile: Vector2i) -> void:
		MapPlayImprovements.on_action(play, action, tile)
	)
	improvements.focus_pressed.connect(func(tile: Vector2i) -> void:
		MapPlayImprovements.on_action(play, "focus", tile)
	)
	game_menu.save_chosen.connect(_on_save_chosen)
	game_menu.load_chosen.connect(_on_load_chosen)
	game_menu.main_menu_chosen.connect(func() -> void: main_menu_requested.emit())


func _on_save_chosen(slot: int) -> void:
	var ok: bool = SaveStore.save_slot(slot, SaveCodec.capture(play), save_dir)
	game_menu.show_save_result(ok, slot)


func _on_load_chosen(slot: int) -> void:
	load_slot_requested.emit(slot)


func _build_visibility() -> void:
	if play.visibility_by_region.has(play.region_index):
		play.visibility = play.visibility_by_region[play.region_index]
		overlay.sync_visibility(play.visibility)
		return
	play.visibility = VisibilityModel.new()
	play.visibility.setup(play.model, play.player_faction)
	play.visibility.apply_initial()
	play.visibility_by_region[play.region_index] = play.visibility
	overlay.sync_visibility(play.visibility)


## Setup post-pass per region: capital ports and harbour roads become real
## LandWorks entries, and Great Powers receive their guaranteed grain farms.
## Runs once per region, before civilians muster and before the economy reads it.
func _bootstrap_region(session: PlaySession) -> void:
	if session.bootstrapped_regions.has(session.region_index):
		return
	WorldBootstrap.apply(session.model, session.civilian_layer.works)
	session.bootstrapped_regions[session.region_index] = true


## Ownership changed outside the map layers (Join Empire): redraw borders,
## terrain tint, fog and the region chips without respawning units.
func refresh_political_map() -> void:
	if play == null or play.model == null:
		return
	canvas.build(play.model, play.world)
	overlay.build(play.model)
	if play.lens != null:
		play.lens.refresh()
	if play.visibility != null:
		overlay.sync_visibility(play.visibility)
	MapPlaySetup.refresh_region_hud(play, MapGeo.world_size(play.model, TILE_SIZE))
