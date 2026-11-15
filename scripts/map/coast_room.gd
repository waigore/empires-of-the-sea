class_name CoastRoom
extends RefCounted
## How much water a shore has beside it, point by point along the inked coast.
##
## Every shore on the chart is printed with a pale surf rim, a wet-sand band, a
## damp edge and a line of breaking foam, and each of those spills most of a tile
## into the sea. In open water that reads as a painted beach; in a gulf a couple
## of tiles across two banks of it meet in the middle and the basin prints as
## barren ground (#456). This measures the water each stretch of coast has beside
## it, so the chart keeps its full shore where there is room and the inked line
## alone where there is not.
##
## Pure data: no nodes, so it measures headless and in tests.

## Water narrower than this many tiles takes the line alone.
const NARROW: int = 3

var _model: MapModel = null
var _tile_size: float = 22.0
## Water width per tile, in tiles; 0 on land.
var _width: PackedInt32Array = PackedInt32Array()


## One flag per point of each path: 1 where the sea beside it has room for the
## shore's paints, 0 where the bank is too narrow for them.
func measure(
	model: MapModel, paths: Array[PackedVector2Array], tile_size: float
) -> Array[PackedByteArray]:
	_model = model
	_tile_size = tile_size
	_width = _water_width(model)
	var out: Array[PackedByteArray] = []
	for path: PackedVector2Array in paths:
		var open := PackedByteArray()
		open.resize(path.size())
		for i in path.size():
			open[i] = 1 if _room(MapGeo.tile_at_world(path[i], _tile_size)) else 0
		out.append(open)
	return out


## The water's own width over the chart, in tiles: the shorter of the sea's run
## east–west through a tile and its run north–south. A channel two tiles across
## answers two however its banks curve, where a cast along one bank's normal runs
## out into the bay the channel opens onto.
func _water_width(model: MapModel) -> PackedInt32Array:
	var width := PackedInt32Array()
	width.resize(model.width * model.height)
	width.fill(0)
	for y in model.height:
		var x: int = 0
		while x < model.width:
			if model.is_land(x, y):
				x += 1
				continue
			var start: int = x
			while x < model.width and not model.is_land(x, y):
				x += 1
			for at in range(start, x):
				width[y * model.width + at] = x - start
	for x in model.width:
		var y: int = 0
		while y < model.height:
			if model.is_land(x, y):
				y += 1
				continue
			var start: int = y
			while y < model.height and not model.is_land(x, y):
				y += 1
			for at in range(start, y):
				var index: int = at * model.width + x
				width[index] = mini(width[index], y - start)
	return width


## Whether the water in reach of one coast point is wide enough for the shore's
## paints. The narrowest water within a tile decides: the paints run along the
## bank, so a stretch beside a creek is printed by the creek's own walls.
func _room(tile: Vector2i) -> bool:
	var room: int = 1 << 30
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if not _model.in_bounds(tile.x + dx, tile.y + dy):
				continue
			var width: int = _width[_model.index_of(tile.x + dx, tile.y + dy)]
			if width > 0:
				room = mini(room, width)
	return room >= NARROW
