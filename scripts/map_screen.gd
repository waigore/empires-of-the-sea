class_name MapScreen
extends Node2D
## Map screen controller: builds the world, wires camera + HUD, and turns input
## into intents. Presentation only — no rule outcomes are decided here.
## Play steps live on MapPlayInput, MapPlayCivilians, MapPlayFleets, MapPlayTurn.
## Presentation moments are broadcast as signals; audio/motion listen (REQ-P3-02).

signal province_selected(province_id: int)
signal selection_cleared
signal coast_charted(province_id: int)
signal battle_resolved(battles: Array[Dictionary])
signal turn_ended(turn: int)

const TILE_SIZE: float = 22.0
const MAP_SEED: int = 1500
const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION
const SHIP_COUNT: int = 7
const STARTING_CIVILIANS: Array[String] = ["explorer", "builder", "engineer"]

var world: WorldMap = null
## Region currently on screen (Old World first).
var region_index: int = 0
var model: MapModel = null
var visibility: VisibilityModel = null
var economy: EconomyController = null
var map_seed: int = MAP_SEED
var map_width: int = 128
var map_height: int = 84
var turn: int = 1
var treasury: int = 1240
var prestige: int = 38
var income: int = 120
var selected_province: int = -1
var capital_province: int = -1
var capital_tile: Vector2i = CapitalChoice.NO_TILE
var land_works: LandWorks = null
var stockpile: Dictionary = {}

var _hover_province: int = -1
var _charted_provinces: Dictionary = {}
## One fog model per region, kept across map switches.
var visibility_by_region: Dictionary = {}

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var overlay: MapOverlay = $World/MapOverlay
@onready var ship_layer: ShipLayer = $World/ShipLayer
@onready var civilian_layer: CivilianLayer = $World/CivilianLayer
@onready var camera: MapCamera = $World/MapCamera
@onready var hud: GameHud = $HUD/HudRoot
@onready var improvements: ImprovementPanel = $HUD/Improvements
@onready var fade: ColorRect = $FadeLayer/Fade


func _ready() -> void:
	InputActions.ensure_actions()
	world = MapGenerator.new().generate_world(map_seed, map_width, map_height)
	_load_region(0)
	_build_hud()
	_connect()
	_intro()


func _process(_delta: float) -> void:
	MapPlayInput.update_hover(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.END_TURN):
		MapPlayTurn.end_turn(self)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.FOCUS_CAPITAL):
		MapPlayTurn.focus_capital(self)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CANCEL):
		MapPlayInput.deselect(self)
		get_viewport().set_input_as_handled()


# --- setup ------------------------------------------------------------------


## Swaps the whole view onto one region: canvas, fog, fleets, civilians, works,
## minimap and camera bounds all follow the active tile map.
func _load_region(index: int) -> void:
	region_index = clampi(index, 0, world.region_count() - 1)
	model = world.region(region_index)
	var map_size: Vector2 = MapGeo.world_size(model, TILE_SIZE)
	var margin: float = 1400.0
	sea_backdrop.position = Vector2(-margin, -margin)
	sea_backdrop.size = map_size + Vector2(margin, margin) * 2.0
	if sea_backdrop.material is ShaderMaterial:
		(sea_backdrop.material as ShaderMaterial).set_shader_parameter(
			"world_size", sea_backdrop.size
		)
	canvas.build(model, world)
	overlay.build(model)
	capital_province = _find_capital()
	capital_tile = MapPlayTurn.capital_tile(self, capital_province)
	ship_layer.spawn(
		model, SHIP_COUNT, MAP_SEED + 3 + region_index, capital_province, _player_present()
	)
	civilian_layer.spawn(model, capital_province, PLAYER_FACTION, STARTING_CIVILIANS)
	land_works = civilian_layer.works
	camera.configure(map_size)
	_build_visibility()
	overlay.snap_fog()
	MapPlayFleets.refresh_visibility(self)
	if hud == null:
		return
	hud.set_minimap(model, map_size)
	HudChrome.set_region_label(hud, FactionCatalog.region_label(region_index))
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	hud.set_civilians(civilian_layer.unit_count(PLAYER_FACTION))
	if economy != null:
		income = economy.projected_income()


## Cycles Old World -> New World and back. Intents never change rules state.
func _cycle_region() -> void:
	if world == null or world.region_count() < 2:
		return
	MapPlayInput.deselect(self)
	_load_region((region_index + 1) % world.region_count())
	camera.focus_on(
		MapPlayTurn.capital_world(self), maxf(camera.target_zoom, 0.75)
	)
	RegionBriefing.arrival(hud, model, region_index)
	MapPlayInput.on_view_changed(self)


func _player_present() -> bool:
	return _owned_provinces() > 0


func _owned_provinces() -> int:
	return world.owned_provinces(region_index, PLAYER_FACTION)


func _build_hud() -> void:
	HudChrome.set_nation(hud, FactionCatalog.name_of(PLAYER_FACTION))
	HudChrome.set_region_label(hud, FactionCatalog.region_label(region_index))
	hud.set_minimap(model, MapGeo.world_size(model, TILE_SIZE))
	hud.set_turn(turn, TurnTime.year_for_turn(turn))
	hud.set_prestige(prestige)
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	hud.set_civilians(civilian_layer.unit_count(PLAYER_FACTION))
	economy = EconomyController.new()
	add_child(economy)
	economy.setup(model, PLAYER_FACTION, capital_province, ship_layer, hud, land_works, capital_tile)
	economy.treasury_changed.connect(func(value: int) -> void: treasury = value)
	treasury = economy.economy.treasury
	stockpile = economy.economy.stockpile
	hud.set_treasury(treasury, false)
	income = economy.projected_income()
	improvements.set_data(
		model, land_works, civilian_layer.units, stockpile, capital_tile,
		PLAYER_FACTION, economy.economy.tech_unlocked
	)


func _connect() -> void:
	camera.tapped.connect(func(world_position: Vector2) -> void:
		MapPlayInput.on_tapped(self, world_position)
	)
	camera.view_changed.connect(func() -> void:
		MapPlayInput.on_view_changed(self)
	)
	hud.end_turn_pressed.connect(func() -> void:
		MapPlayTurn.end_turn(self)
	)
	hud.zoom_in_pressed.connect(camera.zoom_in)
	hud.zoom_out_pressed.connect(camera.zoom_out)
	hud.minimap_jump.connect(func(world_position: Vector2) -> void:
		MapPlayInput.on_minimap_jump(self, world_position)
	)
	hud.region_toggle_pressed.connect(_cycle_region)
	hud.panel_action.connect(func(action: String) -> void:
		MapPlayInput.on_panel_action(self, action)
	)
	hud.panel_closed.connect(func() -> void:
		MapPlayInput.deselect(self)
	)
	ship_layer.zone_entered.connect(func(zone_id: int, ship: Ship) -> void:
		MapPlayFleets.on_zone_entered(self, zone_id, ship)
	)
	ship_layer.ship_selected.connect(func(ship: Ship) -> void:
		MapPlayFleets.select(self, ship)
	)
	ship_layer.fleet_moved.connect(func(fleet: FleetState, result: Dictionary) -> void:
		MapPlayFleets.on_moved(self, fleet, result)
	)
	hud.fleet_closed.connect(func() -> void:
		MapPlayInput.deselect(self)
	)
	civilian_layer.unit_selected.connect(func(unit: CivilianState) -> void:
		MapPlayCivilians.select(self, unit)
	)
	civilian_layer.unit_moved.connect(func(unit: CivilianState, result: Dictionary) -> void:
		MapPlayCivilians.on_moved(self, unit, result)
	)
	hud.civilian_action.connect(func(action: String) -> void:
		MapPlayCivilians.on_action(self, action)
	)
	hud.civilian_cancel.connect(func() -> void:
		MapPlayCivilians.on_cancel(self)
	)
	hud.civilian_closed.connect(func() -> void:
		MapPlayInput.deselect(self)
	)
	improvements.action_pressed.connect(func(action: String, tile: Vector2i) -> void:
		MapPlayImprovements.on_action(self, action, tile)
	)
	improvements.focus_pressed.connect(func(tile: Vector2i) -> void:
		MapPlayImprovements.on_action(self, "focus", tile)
	)

func _intro() -> void:
	var map_size: Vector2 = MapGeo.world_size(model, TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(MapPlayTurn.capital_world(self), maxf(start_zoom * 1.65, 0.75))
	RegionBriefing.opening(hud, model, capital_province, PLAYER_FACTION)
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: fade.visible = false)


func _build_visibility() -> void:
	if visibility_by_region.has(region_index):
		visibility = visibility_by_region[region_index]
		overlay.sync_visibility(visibility)
		return
	visibility = VisibilityModel.new()
	visibility.setup(model, PLAYER_FACTION)
	visibility.apply_initial()
	visibility_by_region[region_index] = visibility
	overlay.sync_visibility(visibility)


func _find_capital() -> int:
	return world.seat_province(region_index, PLAYER_FACTION)


