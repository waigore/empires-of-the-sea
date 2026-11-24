class_name ChartInk
extends RefCounted
## The baked views' own hand: a chart that holds what it has already inked, so a
## second build of the same political chart keeps its texture and its coast and
## crown strokes instead of redrawing them. The minimap and the map overlay both
## bake ink this way; the holders stay their own domains (REQ-P3-01).

## Chart the cached ink was drawn from; a rebake of the same chart (a re-seat
## from the same save, a region repaint) draws nothing again.
var key: int = 0
var baked: bool = false

## Coastline strokes in world units, smoothed into the chart's hand.
var coast: Array[PackedVector2Array] = []
## Dictionary: owner id -> Array[PackedVector2Array] of world-unit borders.
var country_borders: Dictionary = {}

## The same ink projected into a view's own pixels, so strokes draw at device
## scale with true antialiasing. Kept next to the world ink it came from
## (named without the leading underscore so views may read them in tests).
var projected_coast: Array[PackedVector2Array] = []
var projected_borders: Dictionary = {}


## True when this ink was baked from the stated chart. A view that cannot bake a
## chart stays where it was until it does.
func holds(id: int) -> bool:
	return baked and key == id


## Records the chart about to be inked.
func take(id: int) -> void:
	key = id
	baked = true


func clear() -> void:
	coast.clear()
	country_borders.clear()
	projected_coast.clear()
	projected_borders.clear()


func is_empty() -> bool:
	return coast.is_empty() and country_borders.is_empty()


## Charted land/sea edges, smoothed. Uncharted coast stays un-inked; the seam
## walk itself is `TileEdges`, shared with the play overlay.
func take_coast(
	model: MapModel, charted_land: Callable, tile_world: float
) -> void:
	coast.clear()
	if model == null:
		return
	var seams: Array[PackedVector2Array] = TileEdges.province_seams(
		model, charted_land, tile_world, TileEdges.Look.COAST
	)
	coast = InkPaths.smooth_segments(seams, 2)


## Owners' internal borders, smoothed. `CountryBorders` already hides edges
## touching unknown ground, so an uncharted crown never outlines itself here.
func take_borders(model: MapModel, tile_world: float, visibility: VisibilityModel) -> void:
	country_borders.clear()
	if model == null:
		return
	var raw: Dictionary = CountryBorders.build(model, tile_world, visibility)
	var owners: Array = raw.keys()
	owners.sort()
	for owner: int in owners:
		country_borders[owner] = InkPaths.smooth_segments(raw[owner], 2)


## Projects the world ink into one rect's pixels. Ink is cached in world units;
## a view only ever draws its own pixels, so project once per build/resize
## instead of scaling the canvas (a scaled canvas stretches the antialiasing
## feather and muddies thin strokes).
func project(map_size: Vector2, fit: Rect2) -> void:
	projected_coast.clear()
	projected_borders.clear()
	if map_size.x <= 0.0:
		return
	var unit: float = fit.size.x / map_size.x
	for path: PackedVector2Array in coast:
		projected_coast.append(_project_path(path, fit.position, unit))
	var owners: Array = country_borders.keys()
	owners.sort()
	for owner: int in owners:
		var paths: Array[PackedVector2Array] = []
		for path: PackedVector2Array in country_borders[owner]:
			paths.append(_project_path(path, fit.position, unit))
		projected_borders[owner] = paths


func _project_path(path: PackedVector2Array, origin: Vector2, unit: float) -> PackedVector2Array:
	var projected := PackedVector2Array()
	projected.resize(path.size())
	for index in path.size():
		projected[index] = origin + path[index] * unit
	return projected
