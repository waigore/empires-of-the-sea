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
const PLAYER_FACTION: int = 0
const SHIP_COUNT: int = 7
const STARTING_CIVILIANS: Array[String] = ["explorer", "builder", "engineer"]

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

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var overlay: MapOverlay = $World/MapOverlay
@onready var ship_layer: ShipLayer = $World/ShipLayer
@onready var civilian_layer: CivilianLayer = $World/CivilianLayer
@onready var camera: MapCamera = $World/MapCamera
@onready var hud: GameHud = $HUD/HudRoot
@onready var fade: ColorRect = $FadeLayer/Fade


func _ready() -> void:
	InputActions.ensure_actions()
	model = MapGenerator.new().generate(map_seed, map_width, map_height)
	_build_world()
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


func _build_world() -> void:
	var map_size: Vector2 = MapGeo.world_size(model, TILE_SIZE)
	var margin: float = 1400.0
	sea_backdrop.position = Vector2(-margin, -margin)
	sea_backdrop.size = map_size + Vector2(margin, margin) * 2.0
	if sea_backdrop.material is ShaderMaterial:
		(sea_backdrop.material as ShaderMaterial).set_shader_parameter(
			"world_size", sea_backdrop.size
		)
	canvas.build(model)
	overlay.build(model)
	capital_province = _find_capital()
	capital_tile = MapPlayTurn.capital_tile(self, capital_province)
	ship_layer.spawn(model, SHIP_COUNT, MAP_SEED + 3, capital_province)
	land_works = LandWorks.new()
	civilian_layer.spawn(model, land_works, capital_province, PLAYER_FACTION, STARTING_CIVILIANS)
	camera.configure(map_size)
	_build_visibility()
	overlay.snap_fog()
	MapPlayFleets.refresh_visibility(self)


func _build_hud() -> void:
	hud.set_minimap(model, MapGeo.world_size(model, TILE_SIZE))
	hud.set_turn(turn, TurnTime.year_for_turn(turn))
	hud.set_prestige(prestige)
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	hud.set_civilians(civilian_layer.unit_count(PLAYER_FACTION))
	economy = EconomyController.new()
	add_child(economy)
	economy.setup(model, PLAYER_FACTION, capital_province, ship_layer, hud)
	economy.treasury_changed.connect(func(value: int) -> void: treasury = value)
	treasury = economy.economy.treasury
	stockpile = economy.economy.stockpile
	hud.set_treasury(treasury, false)
	income = economy.projected_income()


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


func _intro() -> void:
	var map_size: Vector2 = MapGeo.world_size(model, TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(MapPlayTurn.capital_world(self), maxf(start_zoom * 1.65, 0.75))
	hud.toast("The Indies await — Turn 1, 1500")
	if capital_province >= 0:
		hud.toast(
			"%s holds court at %s"
			% [
				MapGenerator.FACTION_NAMES[PLAYER_FACTION],
				model.province_name(capital_province),
			]
		)
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: fade.visible = false)


func _build_visibility() -> void:
	visibility = VisibilityModel.new()
	visibility.setup(model, PLAYER_FACTION)
	visibility.apply_initial()
	overlay.sync_visibility(visibility)


func _find_capital() -> int:
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == PLAYER_FACTION and bool(province["capital"]):
			return int(province["id"])
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == PLAYER_FACTION:
			return int(province["id"])
	return 0


