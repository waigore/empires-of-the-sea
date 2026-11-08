class_name MapScreen
extends Node2D
## Map screen controller: builds the world, wires camera + HUD, and turns input
## into intents. Presentation only — no rule outcomes are decided here.

const TILE_SIZE: float = 22.0
const MAP_SEED: int = 1500
const PLAYER_FACTION: int = FactionCatalog.PLAYER_FACTION
const SHIP_COUNT: int = 7

var world: WorldMap = null
## Region currently on screen (Old World first).
var region_index: int = 0
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

var _hover_province: int = -1
var _charted_provinces: Dictionary = {}
## One fog model per region, kept across map switches.
var _visibility_by_region: Dictionary = {}

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var overlay: MapOverlay = $World/MapOverlay
@onready var ship_layer: ShipLayer = $World/ShipLayer
@onready var camera: MapCamera = $World/MapCamera
@onready var hud: GameHud = $HUD/HudRoot
@onready var fade: ColorRect = $FadeLayer/Fade


func _ready() -> void:
	InputActions.ensure_actions()
	world = MapGenerator.new().generate_world(map_seed, map_width, map_height)
	_load_region(0)
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


## Swaps the whole view onto one region of the world: canvas, fog, fleets,
## minimap and camera bounds all follow the active tile map.
func _load_region(index: int) -> void:
	region_index = clampi(index, 0, world.region_count() - 1)
	model = world.region(region_index)
	var map_size: Vector2 = model.world_size(TILE_SIZE)
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
	capital_tile = _capital_tile(capital_province)
	ship_layer.spawn(
		model,
		SHIP_COUNT,
		MAP_SEED + 3 + region_index,
		capital_province,
		_player_present()
	)
	camera.configure(map_size)
	_build_visibility()
	overlay.snap_fog()
	_refresh_fleet_visibility()
	if hud != null:
		hud.set_minimap(model, map_size)
		hud.set_region_label(FactionCatalog.region_label(region_index))
		hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
		income = 90 + _owned_provinces() * 6


## Cycles Old World -> New World and back. Intents never change rules state.
func _cycle_region() -> void:
	if world == null or world.region_count() < 2:
		return
	_deselect()
	_load_region((region_index + 1) % world.region_count())
	_intro_region()
	_on_view_changed()


func _intro_region() -> void:
	var seat: Vector2 = _capital_world()
	camera.focus_on(seat, maxf(camera.target_zoom, 0.75))
	hud.toast(
		"%s — %d provinces"
		% [FactionCatalog.region_label(region_index), model.province_count()]
	)
	if region_index == FactionCatalog.NEW_WORLD:
		hud.toast(
			"Lands of the %d tribes — unexplored and uncharted"
			% FactionCatalog.tribe_ids().size()
		)


func _player_present() -> bool:
	return _owned_provinces() > 0


func _build_hud() -> void:
	hud.set_nation(FactionCatalog.name_of(PLAYER_FACTION))
	hud.set_region_label(FactionCatalog.region_label(region_index))
	hud.set_minimap(model, model.world_size(TILE_SIZE))
	hud.set_turn(turn, TurnTime.year_for_turn(turn))
	hud.set_treasury(treasury, false)
	hud.set_prestige(prestige)
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))
	income = 90 + _owned_provinces() * 6


func _connect() -> void:
	camera.tapped.connect(_on_tapped)
	camera.view_changed.connect(_on_view_changed)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.zoom_in_pressed.connect(camera.zoom_in)
	hud.zoom_out_pressed.connect(camera.zoom_out)
	hud.minimap_jump.connect(_on_minimap_jump)
	hud.region_toggle_pressed.connect(_cycle_region)
	hud.panel_action.connect(_on_panel_action)
	hud.panel_closed.connect(_deselect)
	ship_layer.zone_entered.connect(_on_zone_entered)
	ship_layer.ship_selected.connect(_select_fleet)
	ship_layer.fleet_moved.connect(_on_fleet_moved)
	hud.fleet_closed.connect(_deselect)


func _intro() -> void:
	var map_size: Vector2 = model.world_size(TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(_capital_world(), maxf(start_zoom * 1.65, 0.75))
	hud.toast("The Indies await — Turn 1, 1500")
	hud.toast(
		"%d Great Powers, %d minor nations, %d tribes"
		% [
			FactionCatalog.great_power_ids().size(),
			FactionCatalog.minor_ids().size(),
			FactionCatalog.tribe_ids().size(),
		]
	)
	if capital_province >= 0:
		hud.toast(
			"%s holds court at %s"
			% [
				FactionCatalog.name_of(PLAYER_FACTION),
				model.province_name(capital_province),
			]
		)
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: fade.visible = false)


func _build_visibility() -> void:
	if _visibility_by_region.has(region_index):
		visibility = _visibility_by_region[region_index]
		overlay.sync_visibility(visibility)
		return
	visibility = VisibilityModel.new()
	visibility.setup(model, PLAYER_FACTION)
	visibility.apply_initial()
	_visibility_by_region[region_index] = visibility
	overlay.sync_visibility(visibility)


func _find_capital() -> int:
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == PLAYER_FACTION and bool(province["capital"]):
			return int(province["id"])
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == PLAYER_FACTION:
			return int(province["id"])
	return MapModel.NO_ID


func _owned_provinces() -> int:
	var total: int = 0
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == PLAYER_FACTION:
			total += 1
	return total


# --- interaction ------------------------------------------------------------


func _on_tapped(world_position: Vector2) -> void:
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
	overlay.clear_move_options()
	hud.hide_fleet()
	selected_province = province_id
	overlay.select_province(province_id, world_position)
	hud.show_province(model, province_id)


func _deselect() -> void:
	selected_province = -1
	overlay.select_province(-1)
	ship_layer.deselect()
	overlay.clear_move_options()
	hud.hide_province()
	hud.hide_fleet()


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
		hud.toast("Fleet of %s — observe only" % FactionCatalog.name_of(fleet.owner))


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
		_:
			hud.toast("Order noted in %s" % name)


func _on_end_turn() -> void:
	_resolve_naval_combat()
	_resolve_visibility()
	ship_layer.begin_turn()
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


## Fleets that end movement in the same sea zone fight (wiki: ships-and-naval
## § Naval Combat). Rules resolve the battle; this only prunes markers and
## reports the outcome.
func _resolve_naval_combat() -> void:
	var battles: Array[Dictionary] = NavalCombat.resolve_turn(ship_layer.fleets)
	if battles.is_empty():
		return
	ship_layer.prune_destroyed()
	for battle: Dictionary in battles:
		hud.toast(_battle_report(battle))
	hud.set_fleets(ship_layer.hull_count(PLAYER_FACTION))


func _battle_report(battle: Dictionary) -> String:
	var zone: String = model.sea_zone_name(int(battle["zone"]))
	var attacker: String = FactionCatalog.name_of(int(battle["attacker"]))
	var defender: String = FactionCatalog.name_of(int(battle["defender"]))
	var sunk: int = 0
	match int(battle["outcome"]):
		NavalCombat.Outcome.SIDE1_VICTORY:
			sunk = int((battle["defender_lost"] as Array).size())
			return "%s holds the %s — %s loses %d ships" % [attacker, zone, defender, sunk]
		NavalCombat.Outcome.SIDE2_VICTORY:
			sunk = int((battle["attacker_lost"] as Array).size())
			return "%s repels %s in the %s — %d ships lost" % [defender, attacker, zone, sunk]
	return "%s and %s trade broadsides in the %s and withdraw" % [attacker, defender, zone]


## End-of-turn visibility pass (wiki: fog-and-exploration). Zones with a fleet at
## sea stay visible; charted coasts fade until an explorer holds them.
func _resolve_visibility() -> void:
	if visibility == null:
		return
	var at_sea: Array = []
	for ship: Ship in ship_layer.ships:
		if ship.faction == PLAYER_FACTION and ship.zone >= 0:
			at_sea.append(ship.zone)
	var changed: Array = visibility.end_of_turn(at_sea)
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
	return model.world_size(TILE_SIZE) * 0.5


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
			FactionCatalog.name_of(int(data["owner"])),
		]
	)


func _clear_hover() -> void:
	if _hover_province == -1:
		return
	_hover_province = -1
	overlay.hover_province = -1
	hud.hide_tooltip()
