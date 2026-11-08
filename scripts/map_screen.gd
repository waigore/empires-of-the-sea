class_name MapScreen
extends Node2D
## Map screen controller: builds the world, wires camera + HUD, and turns input
## into intents. Presentation only — no rule outcomes are decided here.

const TILE_SIZE: float = 22.0
const MAP_SEED: int = 1500
const PLAYER_FACTION: int = 0
const SHIP_COUNT: int = 7

var model: MapModel = null
var turn: int = 1
var treasury: int = 1240
var prestige: int = 38
var income: int = 120
var selected_province: int = -1
var capital_province: int = -1

var _hover_province: int = -1

@onready var sea_backdrop: ColorRect = $World/SeaBackdrop
@onready var canvas: MapCanvas = $World/MapCanvas
@onready var overlay: MapOverlay = $World/MapOverlay
@onready var ship_layer: ShipLayer = $World/ShipLayer
@onready var camera: MapCamera = $World/MapCamera
@onready var hud: GameHud = $HUD/HudRoot
@onready var fade: ColorRect = $FadeLayer/Fade


func _ready() -> void:
	InputActions.ensure_actions()
	model = MapGenerator.new().generate(MAP_SEED)
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
	ship_layer.spawn(model, SHIP_COUNT, MAP_SEED + 3)
	camera.configure(map_size)
	capital_province = _find_capital()
	_build_fog()
	overlay.snap_fog()


func _build_hud() -> void:
	hud.set_minimap(model, model.world_size(TILE_SIZE))
	hud.set_turn(turn, TurnTime.year_for_turn(turn))
	hud.set_treasury(treasury, false)
	hud.set_prestige(prestige)
	hud.set_fleets(SHIP_COUNT)
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
	ship_layer.ship_selected.connect(_on_ship_selected)


func _intro() -> void:
	var map_size: Vector2 = model.world_size(TILE_SIZE)
	var start_zoom: float = camera.min_zoom()
	camera.zoom = Vector2.ONE * start_zoom
	camera.position = map_size * 0.5
	camera.focus_on(
		model.province_center(capital_province) * TILE_SIZE,
		maxf(start_zoom * 1.65, 0.75)
	)
	hud.toast("The Indies await — Turn 1, 1500")
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: fade.visible = false)


func _build_fog() -> void:
	var capital_tile: Vector2 = model.province_center(capital_province)
	for y in model.height:
		for x in model.width:
			var distance: float = Vector2(float(x), float(y)).distance_to(capital_tile)
			var state: int = MapOverlay.FOG_UNKNOWN
			if distance < 34.0:
				state = MapOverlay.FOG_VISIBLE
			elif distance < 41.0:
				state = MapOverlay.FOG_FOGGED
			overlay.set_fog_state(model.index_of(x, y), state)
	for province: Dictionary in model.provinces:
		if int(province["owner"]) != PLAYER_FACTION:
			continue
		for tile: Vector2i in province["tiles"]:
			overlay.set_fog_state(model.index_of(tile.x, tile.y), MapOverlay.FOG_VISIBLE)
		for neighbor: int in model.province_neighbors(int(province["id"])):
			for tile: Vector2i in model.province_tiles(neighbor):
				overlay.set_fog_state(model.index_of(tile.x, tile.y), MapOverlay.FOG_FOGGED)


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
	var ship: Ship = ship_layer.ship_at(world_position, 30.0 / maxf(camera.zoom.x, 0.001))
	if ship != null:
		ship_layer.select(ship)
		return
	var tile: Vector2i = model.tile_at_world(world_position, TILE_SIZE)
	if not model.in_bounds(tile.x, tile.y):
		return
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		_deselect()
		return
	_select_province(province_id, world_position)


func _select_province(province_id: int, world_position: Vector2) -> void:
	selected_province = province_id
	overlay.select_province(province_id, world_position)
	hud.show_province(model, province_id)


func _deselect() -> void:
	selected_province = -1
	overlay.select_province(-1)
	hud.hide_province()


func _on_ship_selected(ship: Ship) -> void:
	if ship == null:
		return
	_deselect()
	hud.toast(
		"Fleet of %s — patrolling the %s"
		% [MapGenerator.FACTION_NAMES[ship.faction], model.sea_zone_name(ship.zone)]
	)


func _on_minimap_jump(world_position: Vector2) -> void:
	camera.focus_on(world_position)


func _on_view_changed() -> void:
	var viewport: Vector2 = camera.viewport_size()
	var half: Vector2 = viewport / (2.0 * maxf(camera.zoom.x, 0.001))
	hud.update_view_rect(Rect2(camera.position - half, half * 2.0))
	ship_layer.set_zoom(camera.zoom.x)


func _on_zone_entered(zone_id: int, ship: Ship) -> void:
	if ship == null or ship.faction != PLAYER_FACTION:
		return
	overlay.reveal_sea_zone(zone_id)


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
	turn += 1
	var year: int = TurnTime.year_for_turn(turn)
	treasury += income
	prestige += 1
	hud.set_turn(turn, year)
	hud.set_treasury(treasury)
	hud.set_prestige(prestige)
	hud.flash_income(income)
	hud.toast("Turn %d — %d" % [turn, year])
	_reveal_frontier()


func _reveal_frontier() -> void:
	for zone: Dictionary in model.sea_zones:
		var tiles: Array = zone.get("tiles", [])
		if tiles.is_empty():
			continue
		var tile: Vector2i = tiles[0]
		if overlay.fog_state_at(tile.x, tile.y) == MapOverlay.FOG_FOGGED:
			overlay.reveal_sea_zone(int(zone["id"]))
			return


func _focus_capital() -> void:
	camera.focus_on(model.province_center(capital_province) * TILE_SIZE, 0.7)


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
