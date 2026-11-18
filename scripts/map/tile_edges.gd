class_name TileEdges
extends RefCounted
## One province seam, as ink: the shared tile-edge walk behind every charted
## layer (REQ-P3-01, REQ-P3-03).
##
## The play overlay inked province and sea outlines with one hand-copied grid
## walk; the inset copied the same walk twice more for its coast and its hairlines,
## each with its own four corner pairs. The walk lives here once: a caller names
## the tiles it wants (`in_region`), the region each tile belongs to (`region_of`,
## e.g. `model.province_at`), and how a step across the seam is judged (`Look`),
## and gets the world-unit ink back. Nothing here reads a node or a view, so a
## headless suite can ink without drawing (REQ-P3-03).

## Edge slots, clockwise from the top of the tile.
enum Edge {
	TOP = 0,
	RIGHT = 1,
	BOTTOM = 2,
	LEFT = 3,
}

## Every slot, as a typed default. An optional `Array[int]` default of a bare
## `[]` is rebuilt untyped on every call, and a typed `for` over it then hands
## the interpreter a float slot: the walk silently inks dotted diagonals
## instead of edges. A typed const keeps the warm path and the cold one equal.
const ALL_EDGES: Array[int] = [Edge.TOP, Edge.RIGHT, Edge.BOTTOM, Edge.LEFT]

## How far the walk looks across the seam.
enum Look {
	## A closed outline of the region itself: any neighbour outside it inks.
	OUTSIDE = 0,
	## A division between two regions: only a different region inks, and coast,
	## fog and the map's edge never do (the subdivisions of land).
	DIVIDE = 1,
	## A coast: a land tile's edge whose neighbour is sea, or off the chart where
	## the reading says nothing (an absent region). `region_of` is a land test in
	## this reading, so only land inks and the step that would leave the chart
	## inks too.
	COAST = 2,
}


## The province edges `in_region` reads, each drawn once for the tile that owns
## it. `edge_slots` narrows the slots walked (the inset reads only the right and
## bottom steps, so the coast and the subdivisions each trace a seam once);
## `neighbour_ok` lets a caller leave a step to someone else (uncharted ground).
static func province_seams(
	model: MapModel,
	in_region: Callable,
	unit: float,
	look: int = Look.OUTSIDE,
	edge_slots: Array[int] = ALL_EDGES,
	neighbour_ok: Callable = Callable()
) -> Array[PackedVector2Array]:
	if model == null:
		return []
	return seams(model, in_region, model.province_at, look, unit, edge_slots, neighbour_ok)


## The sea zones' edges: every sea tile's border, region by region, without the
## double edge a closed outline would need — a neighbouring zone shares none.
static func sea_seams(model: MapModel, in_region: Callable, unit: float) -> Array[PackedVector2Array]:
	if model == null:
		return []
	return seams(model, in_region, model.sea_zone_at, Look.OUTSIDE, unit)


## The shared walk: one pass over the grid, one corner pair per seam. A caller
## that names no region reading inks nothing: there is no seam to judge across.
static func seams(
	model: MapModel,
	in_region: Callable,
	region_of: Callable,
	look: int,
	unit: float,
	edge_slots: Array[int] = ALL_EDGES,
	neighbour_ok: Callable = Callable()
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if model == null or model.width <= 0 or model.height <= 0:
		return result
	# A caller that has not measured its chart yet (an inset before its build)
	# would fold every tile onto one point of the grid: ink nothing instead.
	if unit <= 0.0:
		return result
	if not in_region.is_valid() or not region_of.is_valid():
		return result
	var slots: Array[int] = edge_slots
	for y in model.height:
		for x in model.width:
			if not in_region.call(x, y):
				continue
			for slot: int in slots:
				var across: Vector2i = Vector2i(x, y) + step(slot)
				if neighbour_ok.is_valid() and not neighbour_ok.call(across.x, across.y):
					continue
				if _inks(region_of, look, x, y, across):
					result.append(pair(x, y, slot, unit))
	return result


## The two corners of tile (`x`, `y`)'s `slot`, in world units of `unit`. The
## owning tile draws its own, so neighbours never trace the line twice.
static func pair(x: int, y: int, slot: int, unit: float) -> PackedVector2Array:
	var top_left := Vector2(float(x), float(y)) * unit
	return PackedVector2Array([
		top_left + _corner(slot, unit),
		top_left + _corner(slot + 1, unit),
	])


## Offset to the tile across `slot`.
static func step(slot: int) -> Vector2i:
	match posmod(slot, 4):
		Edge.RIGHT:
			return Vector2i(1, 0)
		Edge.BOTTOM:
			return Vector2i(0, 1)
		Edge.LEFT:
			return Vector2i(-1, 0)
		_:
			return Vector2i(0, -1)


## Whether the step from (`x`, `y`) to `across` is this region's seam.
static func _inks(region_of: Callable, look: int, x: int, y: int, across: Vector2i) -> bool:
	var here: Variant = region_of.call(x, y)
	var there: Variant = region_of.call(across.x, across.y)
	match look:
		Look.DIVIDE:
			return not _same(there, here) and not _outside(here) and not _outside(there)
		Look.COAST:
			# Sea alone is not a seam: the tile on either side of it reads as no
			# land, and only the land side inks.
			return bool(here) and not bool(there)
		_:
			return not _same(there, here)


## A reading that is absent or the model's no-id sentinel is off the chart.
static func _outside(value: Variant) -> bool:
	return value == null or int(value) == MapModel.NO_ID


static func _same(a: Variant, b: Variant) -> bool:
	if _outside(a) or _outside(b):
		return _outside(a) and _outside(b)
	return int(a) == int(b)


## Corner `slot` (0 = top-left, 1 = top-right, 2 = bottom-right, 3 = bottom-left)
## in units from the tile's top-left corner.
static func _corner(slot: int, unit: float) -> Vector2:
	match posmod(slot, 4):
		1:
			return Vector2(unit, 0.0)
		2:
			return Vector2(unit, unit)
		3:
			return Vector2(0.0, unit)
		_:
			return Vector2.ZERO

