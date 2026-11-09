class_name CivilianMovement
extends RefCounted
## Land movement for civilian units (wiki: civilian-units § Relations).
## One orthogonal land tile per turn, mirroring the fleet move budget. Explores
## may enter any province; builders and engineers stay in their crown's land.

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Tiles the unit could enter this turn (empty while working or after a move).
## `visibility` gates the destination province: a crown cannot order a march into
## land it has never charted (wiki: fog-and-exploration § Order Visibility
## Requirements). Without a model the gate is inert, so rules fixtures stay small.
static func valid_tiles(
	model: MapModel, unit: CivilianState, visibility: VisibilityModel = null
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if unit == null or unit.is_working() or unit.moved:
		return result
	for offset: Vector2i in NEIGHBORS:
		var tile: Vector2i = unit.tile + offset
		if may_enter(model, unit.type_id, unit.owner, tile) and _charted(visibility, model, tile):
			result.append(tile)
	return result


## Move orders need a destination province the crown has glimpsed at least once.
static func _charted(
	visibility: VisibilityModel, model: MapModel, tile: Vector2i
) -> bool:
	if visibility == null:
		return true
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		return true
	return visibility.is_province_known(province_id)


static func may_enter(
	model: MapModel, type_id: String, owner: int, tile: Vector2i
) -> bool:
	if model == null or not model.in_bounds(tile.x, tile.y):
		return false
	if not model.is_land(tile.x, tile.y):
		return false
	if type_id == "explorer" or type_id == "merchant":
		return true
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id == MapModel.NO_ID:
		return true
	return model.owner_at(tile.x, tile.y) == owner


## Applies a move through the rules; returns {ok, reason, from, to}.
static func apply_move(
	model: MapModel, unit: CivilianState, tile: Vector2i, visibility: VisibilityModel = null
) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "No civilian selected"}
	if unit.is_working():
		return {"ok": false, "reason": "The %s is busy working." % unit.display_name()}
	if unit.moved:
		return {"ok": false, "reason": "This civilian has already moved this turn."}
	if tile == unit.tile:
		return {"ok": false, "reason": "The civilian is already there."}
	if not _adjacent(unit.tile, tile):
		return {"ok": false, "reason": "Civilians travel one tile per turn."}
	if not may_enter(model, unit.type_id, unit.owner, tile):
		return {"ok": false, "reason": _refusal(model, unit, tile)}
	if not _charted(visibility, model, tile):
		return {"ok": false, "reason": "That province has never been charted."}
	var from: Vector2i = unit.tile
	unit.tile = tile
	unit.moved = true
	return {"ok": true, "from": from, "to": tile}


## Restores one move per civilian at the start of a turn.
static func begin_turn(units: Array[CivilianState]) -> void:
	for unit: CivilianState in units:
		if unit != null:
			unit.moved = false


## Explorer presence keeps their province fully visible for the owner. A Spy
## only reads within explored terrain and never surveys `unknown` coast, so it
## does not hold a province (wiki: fog-and-exploration § Explorer vs Spy;
## DR-20261109-04).
static func held_provinces(
	model: MapModel, units: Array[CivilianState], owner: int
) -> Array:
	var result: Array = []
	for unit: CivilianState in units:
		if unit == null or unit.owner != owner:
			continue
		if unit.type_id == "spy":
			continue
		var province: int = model.province_at(unit.tile.x, unit.tile.y)
		if province != MapModel.NO_ID and not result.has(province):
			result.append(province)
	return result


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


static func _refusal(model: MapModel, unit: CivilianState, tile: Vector2i) -> String:
	if not model.in_bounds(tile.x, tile.y) or not model.is_land(tile.x, tile.y):
		return "Civilians cannot cross open water."
	var province_id: int = model.province_at(tile.x, tile.y)
	if province_id != MapModel.NO_ID:
		var name: String = model.province_name(province_id)
		return "The %s may not enter %s without a war." % [unit.display_name(), name]
	return "The civilian cannot enter that land."
