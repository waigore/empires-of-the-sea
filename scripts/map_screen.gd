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

const TILE_SIZE: float = PlaySession.TILE_SIZE
const MAP_SEED: int = 1500
const PLAYER_FACTION: int = PlaySession.PLAYER_FACTION
const SHIP_COUNT: int = 7
const STARTING_CIVILIANS: Array[String] = ["explorer", "builder", "engineer"]

var play: PlaySession = null
var map_seed: int = MAP_SEED
var map_width: int = 128
var map_height: int = 84

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var overlay: MapOverlay = $World/MapOverlay
@onready var ship_layer: ShipLayer = $World/ShipLayer
@onready var civilian_layer: CivilianLayer = $World/CivilianLayer
@onready var camera: MapCamera = $World/MapCamera
@onready var hud: GameHud = $HUD/HudRoot
@onready var improvements: ImprovementPanel = $HUD/Improvements
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


func _ready() -> void:
	InputActions.ensure_actions()
	play = PlaySession.new()
	play.bind_host(self)
	play.bind_views(ship_layer, civilian_layer, overlay, camera, hud, improvements)
	play.model = MapGenerator.new().generate(map_seed, map_width, map_height)
	_build_world()
	_build_hud()
	_connect()
	_intro()


func _process(_delta: float) -> void:
	MapPlayInput.update_hover(play)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.END_TURN):
		MapPlayTurn.end_turn(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.FOCUS_CAPITAL):
		MapPlayTurn.focus_capital(play)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CANCEL):
		MapPlayInput.deselect(play)
		get_viewport().set_input_as_handled()


# --- setup ------------------------------------------------------------------


func _build_world() -> void:
	var map_size: Vector2 = MapGeo.world_size(play.model, TILE_SIZE)
	var margin: float = 1400.0
	sea_backdrop.position = Vector2(-margin, -margin)
	sea_backdrop.size = map_size + Vector2(margin, margin) * 2.0
	if sea_backdrop.material is ShaderMaterial:
		(sea_backdrop.material as ShaderMaterial).set_shader_parameter(
			"world_size", sea_backdrop.size
		)
	canvas.build(play.model)
	overlay.build(play.model)
	play.capital_province = _find_capital()
	play.capital_tile = MapPlayTurn.capital_tile(play, play.capital_province)
	ship_layer.spawn(play.model, SHIP_COUNT, MAP_SEED + 3, play.capital_province)
	play.land_works = LandWorks.new()
	civilian_layer.spawn(
		play.model, play.land_works, play.capital_province, PLAYER_FACTION, STARTING_CIVILIANS
	)
	camera.configure(map_size)
	_build_visibility()
	overlay.snap_fog()
	MapPlayFleets.refresh_visibility(play)


func _build_hud() -> void:
	hud.set_minimap(play.model, MapGeo.world_size(play.model, TILE_SIZE))
	hud.set_turn(play.turn, TurnTime.year_for_turn(play.turn))
	hud.set_prestige(play.prestige)
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	hud.set_civilians(civilian_layer.unit_count(PLAYER_FACTION))
	play.economy = EconomyController.new()
	add_child(play.economy)
	play.economy.setup(
		play.model, PLAYER_FACTION, play.capital_province, ship_layer, hud,
		play.land_works, play.capital_tile
	)
	hud.set_treasury(play.treasury(), false)
	play.income = play.economy.projected_income()
	improvements.set_data(
		play.model, play.land_works, civilian_layer.units, play.stockpile(),
		play.capital_tile, PLAYER_FACTION, play.economy.economy.tech_unlocked
	)


func _connect() -> void:
	camera.tapped.connect(func(world_position: Vector2) -> void:
		MapPlayInput.on_tapped(play, world_position)
	)
	camera.view_changed.connect(func() -> void:
		MapPlayInput.on_view_changed(play)
	)
	hud.end_turn_pressed.connect(func() -> void:
		MapPlayTurn.end_turn(play)
	)
	hud.zoom_in_pressed.connect(camera.zoom_in)
	hud.zoom_out_pressed.connect(camera.zoom_out)
	hud.minimap_jump.connect(func(world_position: Vector2) -> void:
		MapPlayInput.on_minimap_jump(play, world_position)
	)
	hud.panel_action.connect(func(action: String) -> void:
		MapPlayInput.on_panel_action(play, action)
	)
	hud.panel_closed.connect(func() -> void:
		MapPlayInput.deselect(play)
	)
	ship_layer.zone_entered.connect(func(zone_id: int, ship: Ship) -> void:
		MapPlayFleets.on_zone_entered(play, zone_id, ship)
	)
	ship_layer.ship_selected.connect(func(ship: Ship) -> void:
		MapPlayFleets.select(play, ship)
	)
	ship_layer.fleet_moved.connect(func(fleet: FleetState, result: Dictionary) -> void:
		MapPlayFleets.on_moved(play, fleet, result)
	)
	hud.fleet_closed.connect(func() -> void:
		MapPlayInput.deselect(play)
	)
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


func _intro() -> void:
	var map_size: Vector2 = MapGeo.world_size(play.model, TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(MapPlayTurn.capital_world(play), maxf(start_zoom * 1.65, 0.75))
	hud.toast("The Indies await — Turn 1, 1500")
	if play.capital_province >= 0:
		var crown: String = MapGenerator.FACTION_NAMES[PLAYER_FACTION]
		hud.toast(
			"%s holds court at %s"
			% [crown, play.model.province_name(play.capital_province)]
		)
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: fade.visible = false)


func _build_visibility() -> void:
	play.visibility = VisibilityModel.new()
	play.visibility.setup(play.model, PLAYER_FACTION)
	play.visibility.apply_initial()
	overlay.sync_visibility(play.visibility)


func _find_capital() -> int:
	var owned: Array = play.model.provinces.filter(
		func(p): return int(p["owner"]) == PLAYER_FACTION
	)
	for province: Dictionary in owned:
		if bool(province["capital"]):
			return int(province["id"])
	return int(owned[0]["id"]) if not owned.is_empty() else 0
