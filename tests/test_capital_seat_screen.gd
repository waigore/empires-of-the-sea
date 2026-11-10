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


## The chart's sea margin lies outside the map's tiles; a tap there is water
## too, and says so instead of swallowing the tap.
func test_a_tap_beyond_the_chart_is_refused_out_loud() -> void:
	var before: Vector2i = page.selected_tile
	assert_false(page.pick_tile(Vector2i(-4, -4)))
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


# --- real input -------------------------------------------------------------


## A tap must be answered through the GUI, not only through the camera's
## `_unhandled_input`: the page's rectangle lives in the camera canvas, so a tap
## whose map point falls inside it was swallowed silently before the chart
## caught taps itself (the phone report: tapping a tile did nothing).
func test_a_tap_is_answered_where_the_page_covers_the_chart() -> void:
	var chart: CapitalChoiceScreen = await _open(914, 411)
	# Show the map's north-west corner: the page's own rectangle then sits under
	# the tap, which is where the pointer event used to stop.
	chart.camera.focus_on(Vector2(300.0, 300.0), 0.6, true)
	await get_tree().process_frame
	var screen: Vector2 = chart.get_viewport().get_canvas_transform() * Vector2(300.0, 300.0)
	var hint: String = chart.hint_text()
	await _tap(chart.get_viewport(), screen)
	assert_ne(chart.hint_text(), hint, "the tap is answered, never silent")
	assert_eq(chart.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the page is not a tap target")
	_free_page(chart)


## The catcher only answers taps: a drag belongs to the camera, so panning the
## chart never moves the seat.
func test_a_drag_pans_the_chart_and_leaves_the_seat() -> void:
	var chart: CapitalChoiceScreen = await _open(914, 411)
	var viewport: Viewport = chart.get_viewport()
	var seat: Vector2i = chart.selected_tile
	var start := viewport.get_visible_rect().size * 0.5
	# The seat frames the chart against an edge, where the camera is clamped;
	# zoom in so the drag has room on both axes.
	chart.camera.zoom_by(1.6, start)
	await get_tree().process_frame
	var before: Vector2 = chart.camera.position
	_push(viewport, _touch(true, start))
	_push(viewport, _drag(start + Vector2(60.0, 40.0)))
	_push(viewport, _touch(false, start + Vector2(60.0, 40.0)))
	await get_tree().process_frame
	assert_ne(chart.camera.position, before, "the drag pans the chart")
	assert_eq(chart.selected_tile, seat, "a drag is not a tap")
	_free_page(chart)


## Taps the water: the banner names the refusal, so a touch player never taps
## into silence (wiki: capital-choice-phase § Player choice).
func test_a_tap_on_open_sea_is_refused_out_loud() -> void:
	var chart: CapitalChoiceScreen = await _open(914, 411)
	var viewport: Viewport = chart.get_viewport()
	var xform: Transform2D = viewport.get_canvas_transform()
	var screen_size: Vector2 = viewport.get_visible_rect().size
	var tapped: bool = false
	for y in chart.model.height:
		for x in chart.model.width:
			if not chart.model.is_sea(x, y):
				continue
			var screen: Vector2 = xform * MapGeo.tile_center(x, y, PlaySession.TILE_SIZE)
			if not _on_screen(screen, screen_size):
				continue
			await _tap(viewport, screen)
			tapped = true
			break
		if tapped:
			break
	assert_true(tapped, "the phone chart shows open water")
	assert_true(chart.hint_text().contains("open sea"), "the sea tap is stated")
	_free_page(chart)


## A pointer on the chart is answered once, though both input paths see it (the
## camera's release and the HUD catcher).
func test_a_pointer_click_seats_the_court_once() -> void:
	var chart: CapitalChoiceScreen = await _open(914, 411)
	var viewport: Viewport = chart.get_viewport()
	var xform: Transform2D = viewport.get_canvas_transform()
	var screen_size: Vector2 = viewport.get_visible_rect().size
	var tile: Vector2i = _other_tile(chart.model, chart.selected_province, chart.selected_tile)
	var screen: Vector2 = xform * MapGeo.tile_center(tile.x, tile.y, PlaySession.TILE_SIZE)
	assert_true(_on_screen(screen, screen_size), "the crown tile is on screen")
	_click(viewport, screen)
	await get_tree().process_frame
	assert_eq(chart.selected_tile, tile, "the click places the seat")
	assert_true(chart.hint_text().contains("SEAT THE COURT"), "one answer, not two")
	_free_page(chart)


## The chart's own buttons still win the tap: the catcher sits under them, and a
## pointer on the button seats the court instead of moving it.
func test_the_confirm_button_seats_the_court_on_a_touch() -> void:
	var chart: CapitalChoiceScreen = await _open(914, 411)
	var chosen: Array = []
	chart.capital_chosen.connect(
		func(_config: GameConfig, _world: WorldMap) -> void: chosen.append(true)
	)
	var seat: Vector2i = chart.selected_tile
	var centre: Vector2 = chart.confirm_button.get_global_rect().get_center()
	_click(chart.get_viewport(), centre)
	await get_tree().process_frame
	assert_eq(chosen.size(), 1, "the button, not the chart, answers the tap")
	assert_eq(chart.selected_tile, seat, "the tap did not move the seat")
	_free_page(chart)



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


## A chart on a phone-sized viewport, laid out and ready for real input.
func _open(width: int, height: int) -> CapitalChoiceScreen:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var chart: CapitalChoiceScreen = SCENE.instantiate()
	chart.config = GameConfig.make(SEED, 0, FactionCatalog.PLAYER_FACTION)
	chart.world = world
	viewport.add_child(chart)
	await get_tree().process_frame
	await get_tree().process_frame
	return chart


func _free_page(chart: CapitalChoiceScreen) -> void:
	var host: Node = chart.get_parent()
	if host is SubViewport:
		host.free()
	else:
		chart.free()


## One finger tap through the viewport: press, release, one idle frame.
func _tap(viewport: Viewport, screen: Vector2) -> void:
	viewport.push_input(_touch(true, screen))
	viewport.push_input(_touch(false, screen + Vector2(1.0, 1.0)))
	await get_tree().process_frame


func _push(viewport: Viewport, event: InputEvent) -> void:
	viewport.push_input(event)


## A pointer click (what Android emulates beside every tap).
func _click(viewport: Viewport, screen: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = screen
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = screen
	viewport.push_input(press)
	viewport.push_input(release)


func _touch(pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	event.position = position
	return event


func _drag(position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = position
	event.relative = Vector2(-60.0, -40.0)
	return event


func _on_screen(point: Vector2, screen: Vector2) -> bool:
	return Rect2(Vector2.ZERO, screen).has_point(point)


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
