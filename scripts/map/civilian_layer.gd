class_name CivilianLayer
extends Node2D
## Owns civilian markers and applies land orders. Rules outcomes come from
## CivilianMovement; estate glyphs paint through LandWorksPaint; the multi-region
## Build/Work pass lives on CivilianTurnPass (REQ-P3-01; wiki: civilian-units).

signal unit_selected(unit: CivilianState)
signal unit_moved(unit: CivilianState, result: Dictionary)
## Development on the map changed (a work completed, was assigned or cancelled);
## flat views such as the survey lens refresh from this.
signal works_changed

const TILE_SIZE: float = 22.0
const MARKER_RADIUS: float = 26.0

var model: MapModel = null
var works: LandWorks = null
var units: Array[CivilianState] = []
var markers: Array[CivilianMarker] = []
var selected_unit: CivilianState = null
## Crown whose eyes are on this map. Rival spies are never drawn or selectable:
## spy locations are invisible to every other player (wiki: civilian-units § Spy).
var viewer_faction: int = -1

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
	var anchor: Vector2i = CivilianPlacement.capital_tile(model, province_id)
	# Keep the capital tile clear so the seat's own marker stays readable, and
	# leave improved tiles free so the estate glyphs are not hidden by units.
	var taken: Dictionary = {anchor: true}
	for tile: Vector2i in model.province_tiles(province_id):
		if works.improvement_at(model, tile) > 0:
			taken[tile] = true
	for type_id: String in types:
		var tile: Vector2i = CivilianPlacement.free_tile(model, province_id, anchor, taken)
		if tile.x < 0:
			taken.erase(anchor)
			tile = CivilianPlacement.free_tile(model, province_id, anchor, taken)
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
	# A civilian aboard a squadron has no map tile (DR-20261109-17).
	marker.visible = not unit.is_embarked() and not SpyRules.hidden_from(unit, viewer_faction)
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
		if SpyRules.hidden_from(unit, viewer_faction):
			continue
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
func apply_move(
	unit: CivilianState, tile: Vector2i, visibility: VisibilityModel = null
) -> Dictionary:
	var result: Dictionary = CivilianMovement.apply_move(model, unit, tile, visibility)
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


## Mirrors rules state onto the medallions (selection, work ring, progress and
## assignment relocation).
func sync() -> void:
	for unit: CivilianState in units:
		if unit.is_embarked() or SpyRules.hidden_from(unit, viewer_faction):
			continue
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
	works_changed.emit()


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
	return CivilianPlacement.mustering_tile(model, units, province_id)


func _draw() -> void:
	LandWorksPaint.paint(self, model, works, TILE_SIZE)


func _tile_position(tile: Vector2i) -> Vector2:
	return MapGeo.tile_center(tile.x, tile.y, TILE_SIZE)
