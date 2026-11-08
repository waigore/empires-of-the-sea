class_name MapScreen
extends Node2D
## Map screen controller: builds the world, wires camera + HUD, and turns input
## into intents. Presentation only — no rule outcomes are decided here.
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
const STOCKPILE_START: Dictionary = {
	"lumber": 40,
	"castIron": 40,
	"bronze": 12,
	"steel": 8,
	"paper": 8,
}

var model: MapModel = null
var visibility: VisibilityModel = null
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
var stockpile: Dictionary = STOCKPILE_START.duplicate()

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
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputActions.END_TURN):
		_on_end_turn()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.FOCUS_CAPITAL):
		_focus_capital()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.CANCEL):
		_deselect()
		get_viewport().set_input_as_handled()


# --- setup ------------------------------------------------------------------


func _build_world() -> void:
	var map_size: Vector2 = model.world_size(TILE_SIZE)
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
	capital_tile = _capital_tile(capital_province)
	ship_layer.spawn(model, SHIP_COUNT, MAP_SEED + 3, capital_province)
	land_works = LandWorks.new()
	civilian_layer.spawn(model, land_works, capital_province, PLAYER_FACTION, STARTING_CIVILIANS)
	camera.configure(map_size)
	_build_visibility()
	overlay.snap_fog()
	_refresh_fleet_visibility()


func _build_hud() -> void:
	hud.set_minimap(model, model.world_size(TILE_SIZE))
	hud.set_turn(turn, TurnTime.year_for_turn(turn))
	hud.set_treasury(treasury, false)
	hud.set_prestige(prestige)
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	hud.set_civilians(civilian_layer.unit_count(PLAYER_FACTION))
	income = 90 + _owned_provinces() * 6


func _connect() -> void:
	camera.tapped.connect(_on_tapped)
	camera.view_changed.connect(_on_view_changed)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.zoom_in_pressed.connect(camera.zoom_in)
	hud.zoom_out_pressed.connect(camera.zoom_out)
	hud.minimap_jump.connect(_on_minimap_jump)
	hud.panel_action.connect(_on_panel_action)
	hud.panel_closed.connect(_deselect)
	ship_layer.zone_entered.connect(_on_zone_entered)
	ship_layer.ship_selected.connect(_select_fleet)
	ship_layer.fleet_moved.connect(_on_fleet_moved)
	hud.fleet_closed.connect(_deselect)
	civilian_layer.unit_selected.connect(_select_civilian)
	civilian_layer.unit_moved.connect(_on_civilian_moved)
	hud.civilian_action.connect(_on_civilian_action)
	hud.civilian_cancel.connect(_on_civilian_cancel)
	hud.civilian_closed.connect(_deselect)


func _intro() -> void:
	var map_size: Vector2 = model.world_size(TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(_capital_world(), maxf(start_zoom * 1.65, 0.75))
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


func _owned_provinces() -> int:
	var total: int = 0
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == PLAYER_FACTION:
			total += 1
	return total


# --- interaction ------------------------------------------------------------


func _on_tapped(world_position: Vector2) -> void:
	var civilian: CivilianState = civilian_layer.unit_at(world_position)
	if civilian != null:
		civilian_layer.select(civilian)
		return
	if _try_civilian_move(world_position):
		return
	var ship: Ship = ship_layer.ship_at(world_position, 30.0 / maxf(camera.zoom.x, 0.001))
	if ship != null:
		ship_layer.select(ship)
		return
	var tile: Vector2i = model.tile_at_world(world_position, TILE_SIZE)
	if not model.in_bounds(tile.x, tile.y):
		return
	if ship_layer.selected_ship != null and _try_fleet_order(tile):
		return
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		_deselect()
		return
	_select_province(province_id, world_position)


func _select_province(province_id: int, world_position: Vector2) -> void:
	ship_layer.deselect()
	civilian_layer.deselect()
	overlay.clear_move_options()
	overlay.clear_tile_options()
	hud.hide_fleet()
	hud.hide_civilian()
	selected_province = province_id
	overlay.select_province(province_id, world_position)
	hud.show_province(model, province_id)
	hud.set_civilian_training(province_id == capital_province)
	province_selected.emit(province_id)


func _deselect() -> void:
	selected_province = -1
	overlay.select_province(-1)
	selection_cleared.emit()
	ship_layer.deselect()
	civilian_layer.deselect()
	overlay.clear_move_options()
	overlay.clear_tile_options()
	hud.hide_province()
	hud.hide_fleet()
	hud.hide_civilian()


# --- civilians --------------------------------------------------------------


func _select_civilian(unit: CivilianState) -> void:
	selected_province = -1
	overlay.select_province(-1)
	overlay.clear_tile_options()
	hud.hide_province()
	hud.hide_fleet()
	if unit == null:
		hud.hide_civilian()
		return
	hud.show_civilian(model, unit, land_works, civilian_layer.units, stockpile, visibility)
	if unit.owner == PLAYER_FACTION:
		overlay.show_tile_options(CivilianMovement.valid_tiles(model, unit))
	else:
		hud.toast("Civilian of %s — observe only" % MapGenerator.FACTION_NAMES[unit.owner])


## Tapping a neighbouring land tile marches the selected civilian there.
func _try_civilian_move(world_position: Vector2) -> bool:
	var unit: CivilianState = civilian_layer.selected_unit
	if unit == null or unit.owner != PLAYER_FACTION:
		return false
	var tile: Vector2i = model.tile_at_world(world_position, TILE_SIZE)
	if not model.in_bounds(tile.x, tile.y):
		return false
	var distance: int = absi(unit.tile.x - tile.x) + absi(unit.tile.y - tile.y)
	if distance != 1:
		return false
	var result: Dictionary = civilian_layer.apply_move(unit, tile)
	if not bool(result.get("ok", false)):
		hud.toast(String(result.get("reason", "")))
	return true


func _on_civilian_moved(unit: CivilianState, _result: Dictionary) -> void:
	if unit.owner != PLAYER_FACTION:
		return
	var province: int = model.province_at(unit.tile.x, unit.tile.y)
	var place: String = model.province_name(province) if province >= 0 else "the wilds"
	hud.toast("The %s marches into %s" % [unit.display_name(), place])
	_refresh_civilian_panel()


func _on_civilian_action(action: String) -> void:
	var unit: CivilianState = civilian_layer.selected_unit
	if unit == null or unit.owner != PLAYER_FACTION:
		return
	var result: Dictionary = CivilianWork.assign(
		model, unit, action, land_works, civilian_layer.units, stockpile, visibility
	)
	if not bool(result.get("ok", false)):
		hud.toast(String(result.get("reason", "")))
		return
	hud.toast("%s begins: %s" % [unit.display_name(), CivilianWork.label(action)])
	_refresh_civilian_panel()


func _on_civilian_cancel() -> void:
	var unit: CivilianState = civilian_layer.selected_unit
	if unit == null or not unit.is_working():
		return
	unit.cancel_work()
	hud.toast("The %s abandons its work." % unit.display_name())
	_refresh_civilian_panel()


func _refresh_civilian_panel() -> void:
	civilian_layer.sync()
	civilian_layer.refresh_works()
	var unit: CivilianState = civilian_layer.selected_unit
	if unit == null:
		return
	hud.show_civilian(model, unit, land_works, civilian_layer.units, stockpile, visibility)
	overlay.clear_tile_options()
	overlay.show_tile_options(CivilianMovement.valid_tiles(model, unit))


## Build/Work pass: advance work orders, apply completions and report them.
func _resolve_civilian_work() -> void:
	if land_works == null:
		return
	var reports: Array[Dictionary] = CivilianWork.resolve_turn(
		model, civilian_layer.units, land_works, visibility
	)
	var changed: Array = []
	for report: Dictionary in reports:
		if not bool(report.get("completed", false)):
			continue
		changed.append_array(report.get("changed", []))
		var type_name: String = CivilianCatalog.display_name(String(report["type_id"]))
		var province: int = int(report["province"])
		var place: String = model.province_name(province) if province >= 0 else "the wilds"
		var work_name: String = CivilianWork.label(String(report["action"])).to_lower()
		hud.toast("%s in %s: %s" % [type_name, place, work_name])
	if not changed.is_empty():
		overlay.sync_visibility(visibility, changed)
	civilian_layer.sync()
	civilian_layer.refresh_works()


func _train_civilian(type_id: String) -> void:
	if not CivilianCatalog.is_implemented(type_id):
		hud.toast(CivilianCatalog.deferred_reason(type_id))
		return
	if selected_province != capital_province:
		hud.toast("Civilians are trained at the capital.")
		return
	var paper: int = int(stockpile.get("paper", 0))
	if not CivilianCatalog.can_afford(type_id, treasury, paper):
		hud.toast("The crown cannot afford a %s." % CivilianCatalog.display_name(type_id))
		return
	var tile: Vector2i = civilian_layer.mustering_tile(capital_province)
	if tile.x < 0:
		hud.toast("There is no room to muster another civilian.")
		return
	treasury -= CivilianCatalog.treasury_cost(type_id)
	stockpile["paper"] = paper - CivilianCatalog.paper_cost(type_id)
	var unit: CivilianState = civilian_layer.add_unit(PLAYER_FACTION, type_id, tile)
	hud.set_treasury(treasury)
	hud.set_civilians(civilian_layer.unit_count(PLAYER_FACTION))
	hud.toast("%s musters at %s" % [unit.display_name(), model.province_name(capital_province)])


# --- fleets -----------------------------------------------------------------


func _select_fleet(ship: Ship) -> void:
	if ship == null:
		return
	var fleet: FleetState = ship_layer.fleet_of(ship)
	if fleet == null:
		return
	selected_province = -1
	overlay.select_province(-1)
	hud.hide_province()
	hud.show_fleet(model, fleet, fleet.owner == PLAYER_FACTION)
	_refresh_fleet_options(fleet)
	if fleet.owner != PLAYER_FACTION:
		hud.toast("Fleet of %s — observe only" % MapGenerator.FACTION_NAMES[fleet.owner])


func _refresh_fleet_options(fleet: FleetState) -> void:
	overlay.clear_move_options()
	if fleet == null or fleet.owner != PLAYER_FACTION or fleet.moved:
		return
	var options: Dictionary = NavalMovement.valid_destinations(model, fleet)
	var zones: Array[int] = []
	for zone: int in options.get("sea_zones", []):
		zones.append(zone)
	var provinces: Array[int] = []
	for province: int in options.get("provinces", []):
		provinces.append(province)
	overlay.show_move_options(zones, provinces)


func _try_fleet_order(tile: Vector2i) -> bool:
	var fleet: FleetState = ship_layer.fleet_of(ship_layer.selected_ship)
	if fleet == null or fleet.owner != PLAYER_FACTION:
		return false
	var zone_id: int = model.sea_zone_at(tile.x, tile.y)
	if zone_id != MapModel.NO_ID:
		return _try_sea_order(fleet, zone_id)
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		return false
	if not NavalMovement.dockable_provinces(model, fleet).has(province_id):
		return false
	var port_result: Dictionary = ship_layer.order(
		fleet, FleetState.Location.IN_PORT, province_id
	)
	if bool(port_result.get("ok", false)):
		return true
	hud.toast(String(port_result.get("reason", "")))
	return true


func _try_sea_order(fleet: FleetState, zone_id: int) -> bool:
	if fleet.moved:
		hud.toast("This fleet has already moved this turn.")
		return true
	if zone_id == fleet.sea_zone:
		hud.toast("The fleet is already in the %s" % model.sea_zone_name(zone_id))
		return true
	var result: Dictionary = ship_layer.order(fleet, FleetState.Location.AT_SEA, zone_id)
	if bool(result.get("ok", false)):
		return true
	hud.toast(String(result.get("reason", "")))
	return true


func _on_fleet_moved(fleet: FleetState, result: Dictionary) -> void:
	if fleet.owner != PLAYER_FACTION:
		return
	hud.show_fleet(model, fleet, true)
	_refresh_fleet_options(fleet)
	var zone: int = int(result.get("entered_zone", -1))
	if zone >= 0:
		hud.toast("The fleet enters the %s" % model.sea_zone_name(zone))
	else:
		hud.toast("The fleet docks at %s" % model.province_name(fleet.province))
	_refresh_fleet_visibility()


func _on_minimap_jump(world_position: Vector2) -> void:
	camera.focus_on(world_position)


func _on_view_changed() -> void:
	var viewport: Vector2 = camera.viewport_size()
	var half: Vector2 = viewport / (2.0 * maxf(camera.zoom.x, 0.001))
	hud.update_view_rect(Rect2(camera.position - half, half * 2.0))
	ship_layer.set_zoom(camera.zoom.x)
	civilian_layer.set_zoom(camera.zoom.x)


func _on_zone_entered(zone_id: int, ship: Ship) -> void:
	if ship == null or ship.faction != PLAYER_FACTION or visibility == null:
		return
	var changed: Array = visibility.reveal_sea_zone(zone_id)
	if not changed.is_empty():
		overlay.sync_visibility(visibility, changed)
	_announce_charted_coast(changed)
	_refresh_fleet_visibility()


## First sighting of a province's coast earns a quiet note, once per province.
func _announce_charted_coast(changed: Array) -> void:
	for raw: Variant in changed:
		var index: int = int(raw)
		var y: int = int(floor(float(index) / float(model.width)))
		var x: int = index - y * model.width
		if not model.is_land(x, y):
			continue
		var province_id: int = model.province_at(x, y)
		if province_id == MapModel.NO_ID or _charted_provinces.has(province_id):
			continue
		_charted_provinces[province_id] = true
		hud.toast("The coast of %s is charted" % model.province_name(province_id))
		coast_charted.emit(province_id)
		return


func _on_panel_action(action: String) -> void:
	if selected_province < 0:
		return
	var name: String = model.province_name(selected_province)
	match action:
		"recruit":
			hud.toast("A regiment is raised in %s" % name)
		"build":
			hud.toast("Works begin in %s" % name)
		"train_explorer", "train_builder", "train_engineer":
			_train_civilian(action.trim_prefix("train_"))
		_:
			hud.toast("Order noted in %s" % name)


func _on_end_turn() -> void:
	_resolve_civilian_work()
	_resolve_naval_combat()
	_resolve_visibility()
	ship_layer.begin_turn()
	civilian_layer.begin_turn()
	_refresh_fleet_visibility()
	turn += 1
	var year: int = TurnTime.year_for_turn(turn)
	treasury += income
	prestige += 1
	hud.set_turn(turn, year)
	hud.set_treasury(treasury)
	hud.set_prestige(prestige)
	hud.flash_income(income)
	hud.toast("Turn %d — %d" % [turn, year])
	var selected: Ship = ship_layer.selected_ship
	if selected != null:
		var fleet: FleetState = ship_layer.fleet_of(selected)
		if fleet != null:
			hud.show_fleet(model, fleet, fleet.owner == PLAYER_FACTION)
			_refresh_fleet_options(fleet)
	if civilian_layer.selected_unit != null:
		_refresh_civilian_panel()
	turn_ended.emit(turn)


## Fleets that end movement in the same sea zone fight (wiki: ships-and-naval
## § Naval Combat). Rules resolve the battle; this only prunes markers and
## reports the outcome.
func _resolve_naval_combat() -> void:
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(ship_layer.fleets)
	if battles.is_empty():
		return
	ship_layer.prune_destroyed()
	for battle: Dictionary in battles:
		var zone: String = model.sea_zone_name(int(battle["zone"]))
		hud.toast(BattleReport.describe(battle, zone, MapGenerator.FACTION_NAMES))
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	battle_resolved.emit(battles)


## End-of-turn visibility pass (wiki: fog-and-exploration). Zones with a fleet at
## sea stay visible; charted coasts fade until an explorer holds them.
func _resolve_visibility() -> void:
	if visibility == null:
		return
	var at_sea: Array = []
	for ship: Ship in ship_layer.ships:
		if ship.faction == PLAYER_FACTION and ship.zone >= 0:
			at_sea.append(ship.zone)
	var held: Array = CivilianMovement.held_provinces(
		model, civilian_layer.units, PLAYER_FACTION
	)
	var changed: Array = visibility.end_of_turn(at_sea, held)
	if not changed.is_empty():
		overlay.sync_visibility(visibility, changed)


func _focus_capital() -> void:
	camera.focus_on(_capital_world(), 0.7)


## World position of the ruler's seat: the capital tile from the capital-choice
## phase, falling back to the province centre when the map has no capital.
func _capital_world() -> Vector2:
	if capital_tile.x >= 0:
		return model.tile_center(capital_tile.x, capital_tile.y, TILE_SIZE)
	if capital_province >= 0:
		return model.province_center(capital_province) * TILE_SIZE
	return Vector2.ZERO


func _capital_tile(province_id: int) -> Vector2i:
	var data: Dictionary = model.province_data(province_id)
	if data.is_empty():
		return CapitalChoice.NO_TILE
	return Vector2i(data.get("capital_tile", CapitalChoice.NO_TILE))


## Enemy markers follow fog intel: a fleet is only drawn while its tile is
## fully visible for the player (wiki: fog-and-exploration).
func _refresh_fleet_visibility() -> void:
	for ship: Ship in ship_layer.ships:
		var fleet: FleetState = ship_layer.fleet_of(ship)
		if fleet == null:
			continue
		ship.visible = _fleet_known(fleet)


func _fleet_known(fleet: FleetState) -> bool:
	if fleet.owner == PLAYER_FACTION or visibility == null:
		return true
	var tile: Vector2i = _fleet_tile(fleet)
	if tile.x < 0:
		return true
	return visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FULLY_VISIBLE


func _fleet_tile(fleet: FleetState) -> Vector2i:
	if fleet.is_at_sea():
		var zone: Dictionary = model.sea_zone_data(fleet.sea_zone)
		var tiles: Array = zone.get("tiles", [])
		if tiles.is_empty():
			return Vector2i(-1, -1)
		return tiles[0]
	var data: Dictionary = model.province_data(fleet.province)
	var port: Vector2i = data.get("port_tile", Vector2i(-1, -1))
	return port


func _update_hover(screen_position: Vector2 = Vector2.INF) -> void:
	if camera.is_dragging():
		_clear_hover()
		return
	if get_viewport().gui_get_hovered_control() != null:
		_clear_hover()
		return
	var mouse: Vector2 = screen_position
	if mouse == Vector2.INF:
		mouse = get_viewport().get_mouse_position()
	var world: Vector2 = CameraMath.screen_to_world(
		camera.position, camera.zoom.x, mouse, camera.viewport_size()
	)
	var tile: Vector2i = model.tile_at_world(world, TILE_SIZE)
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == _hover_province:
		return
	_hover_province = province_id
	overlay.hover_province = province_id
	if province_id < 0:
		hud.hide_tooltip()
		return
	if visibility != null and visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.UNKNOWN:
		hud.show_tooltip("Uncharted land")
		return
	var data: Dictionary = model.province_data(province_id)
	var terrain: int = model.terrain_at(tile.x, tile.y)
	hud.show_tooltip(
		"%s  ·  %s  ·  %s"
		% [
			String(data["name"]),
			String(MapModel.TERRAIN_LABELS.get(terrain, "Unknown")),
			MapGenerator.FACTION_NAMES[int(data["owner"])],
		]
	)


func _clear_hover() -> void:
	if _hover_province == -1:
		return
	_hover_province = -1
	overlay.hover_province = -1
	hud.hide_tooltip()
