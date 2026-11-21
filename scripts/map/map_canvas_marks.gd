class_name MapCanvasMarks
extends RefCounted
## Where the chart's static marks sit: terrain stamps (groves, ridges, dunes),
## ports, capitals and towns. Pure placement — `MapCanvasPlan` owns the label
## clearing and the glyph list; this module only appends marks that stay clear
## of a province name (REQ-P3-01, REQ-P3-03).
##
## Split from `MapCanvasPlan` so the recent stamp and grove work (#1009, #1010)
## has headroom under the soft size bar without mixing mark layout into the
## plan's name, passage and compass pipeline.


## Scatter every land tile's terrain stamps, then every province's port,
## capital and town marks, appending into `plan.glyphs`.
static func scatter(plan: MapCanvasPlan, p_model: MapModel, tile_size: float) -> void:
	for y in p_model.height:
		for x in p_model.width:
			_scatter_terrain(plan, p_model, x, y, tile_size)
	for province: ProvinceState in p_model.provinces:
		_place_ports(plan, province, p_model, tile_size)
		_place_capital(plan, province, tile_size)
		_place_town(plan, province, p_model, tile_size)


static func _scatter_terrain(
	plan: MapCanvasPlan, p_model: MapModel, x: int, y: int, tile_size: float
) -> void:
	var terrain: int = p_model.terrain_at(x, y)
	if terrain == MapModel.Terrain.OCEAN or terrain == MapModel.Terrain.SHALLOW:
		return
	var kind: String = "grass"
	var chance: float = 0.12
	var second: String = ""
	var second_chance: float = 0.0
	match terrain:
		MapModel.Terrain.MOUNTAINS:
			# Peaks of one tile stand as a small ridge, not one peak per tile.
			if MapGlyphs.hash01(x * 3 + 11, y * 7 + 5) <= 0.70:
				_scatter_marks(
					plan, x, y, tile_size, MapGrove.cluster("mountain", x, y, 2, 3, 0.62, 0.88)
				)
			_place_symbol(plan, p_model, x, y, tile_size, "hill", 0.26, 47, 0.58)
			return
		MapModel.Terrain.HILLS:
			if MapGlyphs.hash01(x * 3 + 11, y * 7 + 5) <= 0.62:
				_scatter_marks(
					plan, x, y, tile_size, MapGrove.cluster("hill", x, y, 2, 3, 0.50, 0.78)
				)
			_place_symbol(plan, p_model, x, y, tile_size, "grass", 0.30, 47, 0.58)
			return
		MapModel.Terrain.HARDWOOD_FOREST:
			# A wood is a stand, not a speck: one grove per tile, its crown tree
			# ringed by smaller companions (MapGrove).
			_scatter_marks(
				plan, x, y, tile_size, MapGrove.stamps("tree", x, y, MapGrove.walled(p_model, x, y))
			)
			return
		MapModel.Terrain.SCRUB_FOREST:
			_scatter_marks(
				plan, x, y, tile_size, MapGrove.stamps("scrub", x, y, MapGrove.walled(p_model, x, y))
			)
			return
		MapModel.Terrain.DESERT:
			kind = "dune"
			chance = 0.30
			second = "grass"
			second_chance = 0.18
		MapModel.Terrain.SWAMP:
			_scatter_marks(
				plan, x, y, tile_size, MapGrove.stamps("reed", x, y, MapGrove.walled(p_model, x, y))
			)
			return
		_:
			kind = "field" if MapGlyphs.hash01(x + 3, y + 8) > 0.62 else "grass"
			chance = 0.22
			second = "grass"
			second_chance = 0.12
	_place_symbol(plan, p_model, x, y, tile_size, kind, chance, 0, 1.0)
	if second.is_empty():
		return
	_place_symbol(plan, p_model, x, y, tile_size, second, second_chance, 47, 0.62)


## One tile's marks: the spots `MapGrove` lays (a wood's stand, a ridge's peaks),
## each offset from the tile's centre and clear of a province name.
static func _scatter_marks(
	plan: MapCanvasPlan, x: int, y: int, tile_size: float, spots: Array[Dictionary]
) -> void:
	var centre: Vector2 = MapGeo.tile_center(x, y, tile_size)
	for spot: Dictionary in spots:
		var at: Vector2 = centre + Vector2(spot["dx"], spot["dy"]) * tile_size
		if plan.under_label(at):
			continue
		plan.glyphs.append({
			"kind": String(spot["kind"]),
			"position": at,
			"size": tile_size * float(spot["scale"]),
			"flip": bool(spot["flip"]),
		})


## One scattered mark for this tile, if its hash clears the chance and the spot
## is not inside a province name. `push` moves the hash stream so the primary
## and the secondary stamp never fall on the same spot.
static func _place_symbol(
	plan: MapCanvasPlan,
	p_model: MapModel,
	x: int,
	y: int,
	tile_size: float,
	kind: String,
	chance: float,
	push: int,
	heft: float
) -> void:
	if MapGlyphs.hash01(x * 3 + 11 + push, y * 7 + 5 + push) > chance:
		return
	var jitter := Vector2(
		(MapGlyphs.hash01(x + 31 + push, y + 17) - 0.5) * tile_size * 0.55,
		(MapGlyphs.hash01(x + 71 + push, y + 43) - 0.5) * tile_size * 0.55
	)
	var at: Vector2 = MapGeo.tile_center(x, y, tile_size) + jitter
	if plan.under_label(at):
		return
	var scale: float = (0.55 + MapGlyphs.hash01(x + 5 + push, y + 9) * 0.45) * heft
	plan.glyphs.append({
		"kind": kind,
		"position": at,
		"size": tile_size * scale,
		"flip": MapGlyphs.hash01(x + 13 + push, y + 3) > 0.5,
	})


static func _place_ports(
	plan: MapCanvasPlan, province: ProvinceState, p_model: MapModel, tile_size: float
) -> void:
	for port: Vector2i in MapMarks.port_tiles(province):
		var anchor: Vector2 = MapGeo.tile_center(port.x, port.y, tile_size)
		anchor += _sea_offset(p_model, port) * tile_size * 0.62
		if plan.under_label(anchor):
			continue
		plan.glyphs.append({
			"kind": "port",
			"position": anchor,
			"size": tile_size * 0.66,
			"flip": false,
		})


static func _place_capital(
	plan: MapCanvasPlan, province: ProvinceState, tile_size: float
) -> void:
	if not province.capital:
		return
	var anchor: Vector2 = Vector2(province.center) * tile_size
	var capital: Vector2i = province.capital_tile
	if capital.x >= 0:
		anchor = MapGeo.tile_center(capital.x, capital.y, tile_size)
	plan.glyphs.append({
		"kind": "capital",
		"position": anchor,
		"size": tile_size * 1.1,
		"flip": false,
		"owner": province.owner,
	})


## Town per province (wiki: capital-and-connectivity § Town per province): every
## non-capital province shows a hamlet mark on its town tile, so the extraction
## anchor a crown's estates tie to is visible on the chart. A capital province
## already carries the star, which is its town. The mark always stands on its
## tile; its own province's name steps aside for it (`MapCanvasPlan` name
## placement), never the town under the name.
static func _place_town(
	plan: MapCanvasPlan, province: ProvinceState, p_model: MapModel, tile_size: float
) -> void:
	if province.capital or province.town_tile.x < 0:
		return
	var town: Vector2i = province.town_tile
	if not p_model.is_land(town.x, town.y):
		return
	plan.glyphs.append({
		"kind": "town",
		"position": MapGeo.tile_center(town.x, town.y, tile_size),
		"size": tile_size * 0.92,
		"flip": false,
	})


## A port anchor sits on the water side of its tile, clear of the coastline ink
## and of any province name.
static func _sea_offset(p_model: MapModel, tile: Vector2i) -> Vector2:
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		if p_model.is_sea(tile.x + offset.x, tile.y + offset.y):
			return Vector2(offset)
	return Vector2.ZERO
