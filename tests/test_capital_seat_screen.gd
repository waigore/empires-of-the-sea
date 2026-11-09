extends GdToolsTest
## The capital-choice page: a Great Power seats its court on the chart before
## turn 1 (wiki: capital-choice-phase § Player choice; game-setup § Capital-
## Choice Phase). The chart is generated once here and the world is put back
## after every case, because seating mutates provinces and terrain.

const SCENE: PackedScene = preload("res://scenes/capital_choice.tscn")
const SEED: int = 1500
const SIZE: Vector2i = Vector2i(56, 38)

var world: WorldMap = null
var page: CapitalChoiceScreen = null

var _snapshot: Dictionary = {}


func before_all() -> void:
	world = MapGenerator.new().generate_world(SEED, SIZE.x, SIZE.y)


func before_each() -> void:
	_snapshot = _capture(world.region(0))
	page = SCENE.instantiate()
	page.config = GameConfig.make(SEED, 0, FactionCatalog.PLAYER_FACTION)
	page.config.map_width = SIZE.x
	page.config.map_height = SIZE.y
	page.world = world
	add_child(page)


func after_each() -> void:
	if is_instance_valid(page):
		page.free()
	page = null
	_restore(world.region(0), _snapshot)


# --- opening ----------------------------------------------------------------


## The auto-chosen seat is preselected, so confirming without touching the map
## is the documented setup default (wiki: capital-choice-phase § Auto-Choice).
func test_the_chart_opens_on_the_crowns_recommended_seat() -> void:
	var model: MapModel = page.model
	assert_not_null(model, "the Old World chart is bound")
	if model == null:
		return
	var seat: int = CapitalChoice.seat_province(model, page.config.player_faction)
	assert_gte(seat, 0, "the generated world seats the crown")
	assert_eq(page.selected_province, seat)
	assert_eq(page.selected_tile, model.get_province(seat).capital_tile)
	assert_false(page.confirm_button.disabled, "the seat can be confirmed at once")
	assert_eq(page.marker.province_id, seat, "the chart marks the chosen province")
	assert_eq(page.canvas.model, model, "the chart is drawn")


## A hand-picked province and tile become the campaign's seat, and the chart
## handed to the map screen is the very world that was changed.
func test_a_chosen_province_and_tile_seat_the_court_there() -> void:
	var model: MapModel = page.model
	var faction: int = page.config.player_faction
	var first: int = page.selected_province
	var target: int = _other_coast(model, first)
	assert_gte(target, 0, "the crown holds a second seaboard province")
	if target < 0:
		return
	var tile: Vector2i = model.province_tiles(target)[0]
	assert_true(page.pick_province(target))
	assert_true(page.pick_tile(tile))

	var handed: Array = []
	page.capital_chosen.connect(
		func(_config: GameConfig, chart: WorldMap) -> void: handed.append(chart)
	)
	assert_true(page.confirm())
	assert_eq(handed.size(), 1, "the map screen receives the chart")
	assert_true(handed[0] == page.world, "the chart is the one already generated")
	assert_eq(CapitalChoice.seat_province(model, faction), target)
	assert_eq(model.get_province(target).town_development, 4)
	assert_false(model.get_province(first).capital, "the old seat stands down")


# --- refusals ---------------------------------------------------------------


func test_a_foreign_province_is_refused_and_the_seat_stays() -> void:
	var model: MapModel = page.model
	var before: int = page.selected_province
	var foreign: int = _foreign_province(model)
	assert_gte(foreign, 0, "another crown owns a province")
	if foreign < 0:
		return
	assert_false(page.pick_province(foreign))
	assert_eq(page.selected_province, before, "the choice is unchanged")
	assert_true(page.hint_text().contains("not yours"), "the refusal is stated")


func test_open_sea_is_not_a_seat() -> void:
	var model: MapModel = page.model
	var before: Vector2i = page.selected_tile
	var sea: Vector2i = _sea_tile(model)
	assert_gte(sea.x, 0, "the chart has open water")
	if sea.x < 0:
		return
	assert_false(page.pick_tile(sea))
	assert_eq(page.selected_tile, before, "the seat is unchanged")
	assert_true(page.hint_text().contains("open sea"), "the refusal is stated")


func test_confirm_without_a_seat_is_refused() -> void:
	page.selected_province = -1
	page.selected_tile = CapitalChoice.NO_TILE
	assert_false(page.confirm())
	assert_true(page.hint_text().contains("coastal provinces"))


# --- chart interaction ------------------------------------------------------


## A tap inside the chosen province moves the seat ring, one tile at a time.
func test_tapping_a_tile_inside_the_province_moves_the_seat() -> void:
	var model: MapModel = page.model
	var province: int = page.selected_province
	var tile: Vector2i = _other_tile(model, province, page.selected_tile)
	assert_gte(tile.x, 0, "the province has more than one tile")
	if tile.x < 0:
		return
	page.on_tapped(MapGeo.tile_center(tile.x, tile.y, PlaySession.TILE_SIZE))
	assert_eq(page.selected_tile, tile)
	assert_eq(page.marker.seat, tile, "the chart follows the tap")


func test_back_leaves_the_phase() -> void:
	var backs: Array = []
	page.back_pressed.connect(func() -> void: backs.append(true))
	page.back_button.emit_signal("pressed")
	assert_eq(backs.size(), 1, "the router hears the back intent")


## Android delivers the back request to every node, so the chart must answer it
## itself instead of letting the OS close the app (RUB-P5-07).
func test_android_back_leaves_the_phase() -> void:
	var backs: Array = []
	page.back_pressed.connect(func() -> void: backs.append(true))
	page.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(backs.size(), 1, "the back gesture returns to setup")


## Phone geometry: the banner and the action bar stay on screen, never overlap,
## and keep a touch-sized confirm (REQ-P1-05, REQ-P1-07, RUB-P1-05).
func test_phone_geometry_keeps_banner_and_actions_on_screen() -> void:
	for size: Vector2i in [Vector2i(914, 411), Vector2i(800, 360)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var phone_page: CapitalChoiceScreen = SCENE.instantiate()
		phone_page.config = GameConfig.make(SEED, 0, FactionCatalog.PLAYER_FACTION)
		phone_page.world = world
		viewport.add_child(phone_page)
		await get_tree().process_frame
		var screen_rect := Rect2(Vector2.ZERO, Vector2(size))
		_fits(phone_page.banner.get_global_rect(), screen_rect, "banner %s" % size)
		_fits(phone_page.back_button.get_global_rect(), screen_rect, "back %s" % size)
		_fits(phone_page.confirm_button.get_global_rect(), screen_rect, "confirm %s" % size)
		assert_true(
			phone_page.confirm_button.get_global_rect().position.y
			>= phone_page.banner.get_global_rect().end.y,
			"banner and action bar do not collide at %s" % size
		)
		assert_gte(phone_page.confirm_button.size.y, 44.0, "touch-sized confirm %s" % size)
		viewport.free()


# --- helpers ----------------------------------------------------------------


## Another sea-bound province of the human crown.
func _other_coast(model: MapModel, first: int) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION or province.id == first:
			continue
		if CapitalChoice.is_sea_bound(model, province.id):
			return province.id
	return -1


func _foreign_province(model: MapModel) -> int:
	for province: ProvinceState in model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			return province.id
	return -1


func _sea_tile(model: MapModel) -> Vector2i:
	for y in model.height:
		for x in model.width:
			if model.is_sea(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _other_tile(model: MapModel, province_id: int, avoid: Vector2i) -> Vector2i:
	for tile: Vector2i in model.province_tiles(province_id):
		if tile != avoid and model.is_land(tile.x, tile.y):
			return tile
	return Vector2i(-1, -1)


func _fits(inner: Rect2, outer: Rect2, what: String) -> void:
	var pad: float = 0.5
	assert_true(
		inner.position.x >= -pad and inner.position.y >= -pad
		and inner.end.x <= outer.end.x + pad and inner.end.y <= outer.end.y + pad,
		"%s must fit: %s inside %s" % [what, inner, outer]
	)


## Province records and tile arrays the seating phase can change.
func _capture(model: MapModel) -> Dictionary:
	var provinces: Array = []
	for province: ProvinceState in model.provinces:
		provinces.append({
			"capital": province.capital,
			"capital_tile": province.capital_tile,
			"ports": province.ports.duplicate(),
			"road_paths": province.road_paths.duplicate(true),
			"town_tile": province.town_tile,
			"town_development": province.town_development,
			"resource": province.resource,
			"resource_tile": province.resource_tile,
		})
	return {
		"provinces": provinces,
		"terrain": model.terrain.duplicate(),
		"resource": model.resource.duplicate(),
	}


func _restore(model: MapModel, snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	model.terrain = (snapshot["terrain"] as PackedByteArray).duplicate()
	model.resource = (snapshot["resource"] as PackedInt32Array).duplicate()
	var rows: Array = snapshot["provinces"]
	for index in mini(rows.size(), model.provinces.size()):
		var province: ProvinceState = model.provinces[index]
		var row: Dictionary = rows[index]
		province.capital = bool(row["capital"])
		province.capital_tile = row["capital_tile"]
		province.ports = (row["ports"] as Dictionary).duplicate()
		province.road_paths = (row["road_paths"] as Array).duplicate(true)
		province.town_tile = row["town_tile"]
		province.town_development = int(row["town_development"])
		province.resource = int(row["resource"])
		province.resource_tile = row["resource_tile"]
