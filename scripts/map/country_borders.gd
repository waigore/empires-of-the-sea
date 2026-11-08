class_name CountryBorders
extends RefCounted
## Country borders are the *internal* land boundaries between two owners: the
## coastline keeps its ink treatment so a nation's colour never bleeds into the
## sea. One segment per boundary edge (right/bottom checks only).

## Dictionary: owner id -> Array[PackedVector2Array] of unit segments.
static func build(model: MapModel, tile_size: float = 1.0) -> Dictionary:
	var result: Dictionary = {}
	if model == null:
		return result
	for y in model.height:
		for x in model.width:
			if not model.is_land(x, y):
				continue
			var owner: int = model.owner_at(x, y)
			if owner == MapModel.NO_ID:
				continue
			var right: int = model.owner_at(x + 1, y)
			if right != MapModel.NO_ID and right != owner:
				_add(result, owner, _edge(x, y, 1, tile_size))
			var below: int = model.owner_at(x, y + 1)
			if below != MapModel.NO_ID and below != owner:
				_add(result, owner, _edge(x, y, 2, tile_size))
	return result


## 0 = top, 1 = right, 2 = bottom, 3 = left, in world coordinates.
static func _edge(x: int, y: int, edge: int, tile_size: float) -> PackedVector2Array:
	match edge:
		1:
			return PackedVector2Array([
				Vector2(float(x) + 1.0, float(y)) * tile_size,
				Vector2(float(x) + 1.0, float(y) + 1.0) * tile_size,
			])
		2:
			return PackedVector2Array([
				Vector2(float(x), float(y) + 1.0) * tile_size,
				Vector2(float(x) + 1.0, float(y) + 1.0) * tile_size,
			])
		3:
			return PackedVector2Array([
				Vector2(float(x), float(y)) * tile_size,
				Vector2(float(x), float(y) + 1.0) * tile_size,
			])
		_:
			return PackedVector2Array([
				Vector2(float(x), float(y)) * tile_size,
				Vector2(float(x) + 1.0, float(y)) * tile_size,
			])


static func _add(result: Dictionary, owner: int, segment: PackedVector2Array) -> void:
	if not result.has(owner):
		result[owner] = [] as Array[PackedVector2Array]
	var segments: Array[PackedVector2Array] = result[owner]
	segments.append(segment)
