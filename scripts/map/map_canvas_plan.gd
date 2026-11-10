class_name MapCanvasPlan
extends RefCounted
## Pure placement plan for the static map artwork: where province and sea names
## sit, which terrain symbols are scattered (and never on top of a name), where
## the sea lanes to the other region are marked, and where the compass rose can
## float clear of the coast. No nodes, no drawing — `MapCanvas` runs the plan.
##
## Labels carry `kind` ("province", "sea", "passage") and `size` in pixels;
## symbols carry `kind` ("mountain", "port", "capital", …), `position` and `size`.

var labels: Array[Dictionary] = []
var glyphs: Array[Dictionary] = []
## World-space centres of the warp-zone passages on this region.
var passages: Array[Vector2] = []
var compass_position: Vector2 = Vector2.ZERO
var compass_visible: bool = false


## Marks every warp zone toward another region with a ring and a quiet label so
## the way across is legible on a chart (wiki: map-topology).
func build(p_model: MapModel, p_world: WorldMap, tile_size: float) -> void:
	labels.clear()
	glyphs.clear()
	passages.clear()
	compass_visible = false
	_add_names(p_model, tile_size)
	_add_passages(p_model, p_world, tile_size)
	_scatter_symbols(p_model, tile_size)
	_find_compass_spot(p_model, tile_size)


func _add_names(p_model: MapModel, tile_size: float) -> void:
	for province: ProvinceState in p_model.provinces:
		if province.area < 26:
			continue
		labels.append({
			"text": province.name,
			"position": Vector2(province.center) * tile_size,
			"size": 22,
			"kind": "province",
			"capital": province.capital,
		})
	for zone: SeaZoneState in p_model.sea_zones:
		if zone.area < 260:
			continue
		labels.append({
			"text": MapGlyphs.spaced(zone.name),
			"position": zone.center * tile_size,
			"size": 13,
			"kind": "sea",
		})


func _add_passages(p_model: MapModel, p_world: WorldMap, tile_size: float) -> void:
	if p_world == null:
		return
	for zone_id: int in p_world.warp_zones(p_model.region_id):
		var center: Vector2 = p_model.sea_zone_center(zone_id) * tile_size
		if center == Vector2.ZERO:
			continue
		passages.append(center)
		labels.append({
			"text": "Passage",
			"position": center + Vector2(0, 26),
			"size": 12,
			"kind": "passage",
		})


func _scatter_symbols(p_model: MapModel, tile_size: float) -> void:
	for y in p_model.height:
		for x in p_model.width:
			_scatter_terrain(p_model, x, y, tile_size)
	for province: ProvinceState in p_model.provinces:
		_place_ports(province, p_model, tile_size)
		_place_capital(province, tile_size)
		_place_town(province, p_model, tile_size)


func _scatter_terrain(p_model: MapModel, x: int, y: int, tile_size: float) -> void:
	var terrain: int = p_model.terrain_at(x, y)
	if terrain == MapModel.Terrain.OCEAN or terrain == MapModel.Terrain.SHALLOW:
		return
	var kind: String = "grass"
	var chance: float = 0.12
	var second: String = ""
	var second_chance: float = 0.0
	match terrain:
		MapModel.Terrain.MOUNTAINS:
			kind = "mountain"
			chance = 0.86
			second = "hill"
			second_chance = 0.56
		MapModel.Terrain.HILLS:
			kind = "hill"
			chance = 0.62
			second = "grass"
			second_chance = 0.36
		MapModel.Terrain.HARDWOOD_FOREST:
			kind = "tree"
			chance = 0.72
			second = "tree"
			second_chance = 0.56
		MapModel.Terrain.SCRUB_FOREST:
			kind = "scrub"
			chance = 0.58
			second = "scrub"
			second_chance = 0.34
		MapModel.Terrain.DESERT:
			kind = "dune"
			chance = 0.30
			second = "grass"
			second_chance = 0.18
		MapModel.Terrain.SWAMP:
			kind = "reed"
			chance = 0.46
			second = "reed"
			second_chance = 0.30
		_:
			kind = "field" if MapGlyphs.hash01(x + 3, y + 8) > 0.62 else "grass"
			chance = 0.22
			second = "grass"
			second_chance = 0.12
	_place_symbol(p_model, x, y, tile_size, kind, chance, 0, 1.0)
	if second.is_empty():
		return
	_place_symbol(p_model, x, y, tile_size, second, second_chance, 47, 0.62)


## One scattered mark for this tile, if its hash clears the chance and the spot
## is not inside a province name. `push` moves the hash stream so the primary
## and the secondary stamp never fall on the same spot.
func _place_symbol(
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
	if under_label(at):
		return
	var scale: float = (0.55 + MapGlyphs.hash01(x + 5 + push, y + 9) * 0.45) * heft
	glyphs.append({
		"kind": kind,
		"position": at,
		"size": tile_size * scale,
		"flip": MapGlyphs.hash01(x + 13 + push, y + 3) > 0.5,
	})


func _place_ports(province: ProvinceState, p_model: MapModel, tile_size: float) -> void:
	for port: Vector2i in MapGlyphs.port_tiles(province):
		var anchor: Vector2 = MapGeo.tile_center(port.x, port.y, tile_size)
		anchor += _sea_offset(p_model, port) * tile_size * 0.62
		if under_label(anchor):
			continue
		glyphs.append({
			"kind": "port",
			"position": anchor,
			"size": tile_size * 0.8,
			"flip": false,
		})


func _place_capital(province: ProvinceState, tile_size: float) -> void:
	if not province.capital:
		return
	var anchor: Vector2 = Vector2(province.center) * tile_size
	var capital: Vector2i = province.capital_tile
	if capital.x >= 0:
		anchor = MapGeo.tile_center(capital.x, capital.y, tile_size)
	glyphs.append({
		"kind": "capital",
		"position": anchor,
		"size": tile_size * 1.1,
		"flip": false,
		"owner": province.owner,
	})


## Town per province (wiki: capital-and-connectivity § Town per province): every
## non-capital province shows a hamlet mark on its town tile, so the extraction
## anchor a crown's estates tie to is visible on the chart. A capital province
## already carries the star, which is its town.
func _place_town(
	province: ProvinceState, p_model: MapModel, tile_size: float
) -> void:
	if province.capital or province.town_tile.x < 0:
		return
	var town: Vector2i = province.town_tile
	if not p_model.is_land(town.x, town.y):
		return
	var anchor: Vector2 = MapGeo.tile_center(town.x, town.y, tile_size)
	if under_label(anchor):
		return
	glyphs.append({
		"kind": "town",
		"position": anchor,
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


## Province names sit in a clearing: a scattered symbol never lands on a label,
## so the type stays readable however dense the terrain is.
func under_label(at: Vector2) -> bool:
	for label: Dictionary in labels:
		if String(label["kind"]) != "province":
			continue
		var anchor: Vector2 = label["position"]
		if absf(at.x - anchor.x) < 74.0 and at.y > anchor.y - 18.0 and at.y < anchor.y + 26.0:
			return true
	return false


func _find_compass_spot(p_model: MapModel, tile_size: float) -> void:
	var target := Vector2(float(p_model.width) * 0.12, float(p_model.height) * 0.86)
	for radius in range(0, 24, 2):
		for angle in range(0, 360, 30):
			var offset := Vector2(cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * radius
			var tile: Vector2i = MapGeo.tile_at_world(target + offset, tile_size)
			if p_model.is_sea(tile.x, tile.y) and p_model.sea_zone_at(tile.x, tile.y) != MapModel.NO_ID:
				compass_position = MapGeo.tile_center(tile.x, tile.y, tile_size)
				compass_visible = true
				return
