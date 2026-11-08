class_name CivilianLayer
extends Node2D
## Owns civilian markers and applies land orders. Rules outcomes come from
## CivilianMovement; this layer only animates them and draws the development
## civilians leave behind (wiki: civilian-units, extraction-and-improvements).

signal unit_selected(unit: CivilianState)
signal unit_moved(unit: CivilianState, result: Dictionary)

const TILE_SIZE: float = 22.0
const MARKER_RADIUS: float = 26.0

var model: MapModel = null
var works: LandWorks = null
var units: Array[CivilianState] = []
var markers: Array[CivilianMarker] = []
var selected_unit: CivilianState = null

var _zoom: float = 1.0
## Units and works per region: switching maps must not reset orders, work
## progress or the development already raised (wiki: map-topology). The public
## table and cursor also give save/load a narrow API (REQ-P3-02).
var next_id: int = 1
var regions := MapRegionTable.new()
var works_regions := MapRegionTable.new()


## Loads the region's roster (creating it on first visit) and its works record.
## `place_units = false` prepares the works only, so the setup post-pass can
## wire ports and roads before civilians muster.
func spawn(
	p_model: MapModel, province_id: int, owner: int, types: Array[String],
	place_units: bool = true
) -> void:
	model = p_model
	_clear_markers()
	units = []
	selected_unit = null
	if model == null:
		return
	works = works_regions.value(model.region_id, null)
	if works == null:
		works = LandWorks.new()
		works_regions.set_region(model.region_id, works)
	if regions.has_region(model.region_id):
		units.assign(regions.value(model.region_id, []))
		regions.set_region(model.region_id, units)
		_rebuild_markers()
		queue_redraw()
		return
	if not place_units or types.is_empty():
		queue_redraw()
		return
	var anchor: Vector2i = _capital_tile(province_id)
	# Keep the capital tile clear so the seat's own marker stays readable, and
	# leave improved tiles free so the estate glyphs are not hidden by units.
	var taken: Dictionary = {anchor: true}
	for tile: Vector2i in model.province_tiles(province_id):
		if works.improvement_at(model, tile) > 0:
			taken[tile] = true
	for type_id: String in types:
		var tile: Vector2i = _free_tile(province_id, anchor, taken)
		if tile.x < 0:
			taken.erase(anchor)
			tile = _free_tile(province_id, anchor, taken)
		if tile.x < 0:
			continue
		taken[tile] = true
		add_unit(owner, type_id, tile)
	regions.set_region(model.region_id, units)
	queue_redraw()


func _clear_markers() -> void:
	for marker: CivilianMarker in markers:
		marker.queue_free()
	markers.clear()


func _rebuild_markers() -> void:
	_clear_markers()
	for unit: CivilianState in units:
		_add_marker(unit)


func _add_marker(unit: CivilianState) -> void:
	var marker := CivilianMarker.new()
	marker.unit_id = unit.id
	marker.type_id = unit.type_id
	marker.faction = unit.owner
	marker.position = _tile_position(unit.tile)
	marker.scale = Vector2.ONE * clampf(1.0 / _zoom, 0.62, 1.0)
	add_child(marker)
	markers.append(marker)


func add_unit(owner: int, type_id: String, tile: Vector2i) -> CivilianState:
	var unit := CivilianState.create(next_id, owner, type_id, tile)
	next_id += 1
	units.append(unit)
	_add_marker(unit)
	return unit


func unit_at(world_position: Vector2) -> CivilianState:
	var best: CivilianState = null
	var best_distance: float = minf(MARKER_RADIUS / maxf(_zoom, 0.001), TILE_SIZE * 0.9)
	for unit: CivilianState in units:
		var distance: float = _tile_position(unit.tile).distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best


func marker_for(unit: CivilianState) -> CivilianMarker:
	if unit == null:
		return null
	for marker: CivilianMarker in markers:
		if marker.unit_id == unit.id:
			return marker
	return null


func select(unit: CivilianState) -> void:
	selected_unit = unit
	sync()
	unit_selected.emit(unit)


func deselect() -> void:
	if selected_unit == null:
		return
	selected_unit = null
	sync()
	unit_selected.emit(null)


## Applies a land order through the rules, then animates the medallion.
func apply_move(unit: CivilianState, tile: Vector2i) -> Dictionary:
	var result: Dictionary = CivilianMovement.apply_move(model, unit, tile)
	if not bool(result.get("ok", false)):
		return result
	var marker: CivilianMarker = marker_for(unit)
	if marker != null:
		var tween: Tween = create_tween()
		tween.tween_property(marker, "position", _tile_position(tile), 0.32).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_IN_OUT)
	unit_moved.emit(unit, result)
	return result


## Ticks every region, not just the one on screen: reading another map must not
## pause work or burn a unit's move. Returns the work reports for the caller.
func begin_turn(world: WorldMap, visibilities: Dictionary) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for index in world.region_count():
		var region_units: Array[CivilianState] = []
		if model != null and index == model.region_id:
			region_units = units
		else:
			region_units.assign(regions.value(index, []))
		CivilianMovement.begin_turn(region_units)
		var region_works: LandWorks = works_regions.value(index, null)
		if region_works == null:
			continue
		var region_visibility: VisibilityModel = visibilities.get(index, null)
		for report: Dictionary in CivilianWork.resolve_turn(
			world.region(index), region_units, region_works, region_visibility
		):
			report["region"] = index
			reports.append(report)
	return reports


## Mirrors rules state onto the medallions (selection, work ring, progress and
## assignment relocation).
func sync() -> void:
	for unit: CivilianState in units:
		var marker: CivilianMarker = marker_for(unit)
		if marker == null:
			continue
		var target: Vector2 = _tile_position(unit.tile)
		if marker.position.distance_to(target) > 0.5:
			var tween: Tween = create_tween()
			tween.tween_property(marker, "position", target, 0.32).set_trans(
				Tween.TRANS_CUBIC
			).set_ease(Tween.EASE_IN_OUT)
		var progress: float = 0.0
		if unit.is_working() and unit.total_turns() > 0:
			progress = 1.0 - float(unit.remaining_turns()) / float(unit.total_turns())
		marker.set_state(unit == selected_unit, unit.is_working(), progress)


func refresh_works() -> void:
	queue_redraw()


func set_zoom(value: float) -> void:
	_zoom = maxf(value, 0.001)
	for marker: CivilianMarker in markers:
		marker.scale = Vector2.ONE * clampf(1.0 / _zoom, 0.62, 1.0)


## Civilians owned across every region: the HUD chip is an empire total.
func unit_count_all(owner: int) -> int:
	var total: int = 0
	for raw: Variant in regions.values():
		var stored: Array[CivilianState] = []
		stored.assign(raw)
		for unit: CivilianState in stored:
			if unit.owner == owner:
				total += 1
	return total


func civilian_tiles(owner: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for unit: CivilianState in units:
		if unit.owner == owner:
			tiles.append(unit.tile)
	return tiles


## Free land tile near the capital for a freshly trained civilian (-1 when full).
func mustering_tile(province_id: int) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var seat: Vector2i = _capital_tile(province_id)
	var taken: Dictionary = {seat: true}
	for unit: CivilianState in units:
		taken[unit.tile] = true
	var tile: Vector2i = _free_tile(province_id, seat, taken)
	if tile.x >= 0:
		return tile
	taken.erase(seat)
	return _free_tile(province_id, seat, taken)


func _draw() -> void:
	if model == null or works == null:
		return
	for tile: Vector2i in works.developed_tiles(model):
		var point: Vector2 = _tile_position(tile)
		var transport: int = works.transport_at(model, tile)
		if transport >= LandWorks.TRANSPORT_ROAD:
			_draw_road(point, transport >= LandWorks.TRANSPORT_RAIL)
		var level: int = works.improvement_at(model, tile)
		if level > 0:
			var resource: int = model.resource_at(tile.x, tile.y)
			_draw_improvement(point, resource, level)
		if works.has_port(model, tile):
			_draw_port(point)


## A road is a dashed ink line; a railroad adds sleepers so level 4 reads at a
## glance (wiki: extraction-and-improvements § Transport Level).
func _draw_road(point: Vector2, rail: bool = false) -> void:
	var ink := Color(0.36, 0.26, 0.16, 0.65)
	if rail:
		draw_line(point + Vector2(-9, 0), point + Vector2(9, 0), ink, 1.6, true)
		for i in 3:
			var x: float = -6.0 + float(i) * 6.0
			draw_line(point + Vector2(x, -3.0), point + Vector2(x, 3.0), ink, 1.4, true)
		return
	draw_line(point + Vector2(-9, 0), point + Vector2(-3, 0), ink, 2.4, true)
	draw_line(point + Vector2(3, 0), point + Vector2(9, 0), ink, 2.4, true)


func _draw_improvement(point: Vector2, resource: int, level: int) -> void:
	var ink := Palette.INK
	var tint: Color = _improvement_color(resource)
	var mark: Vector2 = point + Vector2(0, -3.0)
	match ImprovementCatalog.category(resource):
		"wood":
			draw_colored_polygon(
				PackedVector2Array([
					mark + Vector2(0, -5.0),
					mark + Vector2(4.2, 2.2),
					mark + Vector2(-4.2, 2.2),
				]),
				tint
			)
			draw_line(mark + Vector2(0, 2.0), mark + Vector2(0, 5.0), ink, 1.2, true)
		"mine":
			draw_colored_polygon(
				PackedVector2Array([
					mark + Vector2(0, -4.6),
					mark + Vector2(4.2, 0),
					mark + Vector2(0, 4.6),
					mark + Vector2(-4.2, 0),
				]),
				tint
			)
		"riches":
			draw_circle(mark, 3.8, tint)
			draw_circle(mark, 3.8, ink, false, 1.0, true)
		_:
			draw_line(mark + Vector2(0, 4.6), mark + Vector2(0, -3.0), ink, 1.3, true)
			for i in 3:
				var y: float = -3.0 + float(i) * 2.4
				draw_line(
					mark + Vector2(0, y), mark + Vector2(-3.4, y - 1.4), tint, 1.5, true
				)
				draw_line(
					mark + Vector2(0, y), mark + Vector2(3.4, y - 1.4), tint, 1.5, true
				)
	for i in level:
		var origin: Vector2 = point + Vector2(-7.5 + float(i) * 5.0, 8.0)
		draw_rect(Rect2(origin, Vector2(3.4, 3.4)), Palette.GOLD)
		draw_rect(Rect2(origin, Vector2(3.4, 3.4)), ink, false, 0.8)


func _improvement_color(resource: int) -> Color:
	match ImprovementCatalog.category(resource):
		"wood":
			return Color(0.34, 0.45, 0.27)
		"mine":
			return Color(0.47, 0.43, 0.38)
		"riches":
			return Palette.GOLD
		_:
			return Palette.GOLD_DIM


func _draw_port(point: Vector2) -> void:
	var ink := Color(0.18, 0.24, 0.32, 0.85)
	draw_arc(point + Vector2(0, 5.0), 4.6, PI, TAU, 12, ink, 1.6, true)
	draw_line(point + Vector2(0, 0.6), point + Vector2(0, 5.0), ink, 1.4, true)


func _tile_position(tile: Vector2i) -> Vector2:
	return MapGeo.tile_center(tile.x, tile.y, TILE_SIZE)


func _capital_tile(province_id: int) -> Vector2i:
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return Vector2i(-1, -1)
	var seat: Vector2i = data.capital_tile
	if seat.x >= 0 and model.is_land(seat.x, seat.y):
		return seat
	var tiles: Array = model.province_tiles(province_id)
	if tiles.is_empty():
		return Vector2i(-1, -1)
	return tiles[0]


## First free land tile of the province, nearest the capital seat.
func _free_tile(province_id: int, anchor: Vector2i, taken: Dictionary) -> Vector2i:
	var center: Vector2 = Vector2(anchor)
	var candidates: Array[Vector2i] = []
	for tile: Vector2i in model.province_tiles(province_id):
		if taken.has(tile):
			continue
		candidates.append(tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(center) < Vector2(b).distance_squared_to(center)
	)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[0]
