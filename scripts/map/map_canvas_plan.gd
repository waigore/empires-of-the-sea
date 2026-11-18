class_name MapCanvasPlan
extends RefCounted
## Pure placement plan for the static map artwork: where province and sea names
## sit, which terrain symbols are scattered (and never on top of a name), where
## the sea lanes to the other region are marked, and where the compass rose can
## float clear of the coast. No nodes, no drawing — `MapCanvas` runs the plan.
##
## Labels carry `kind` ("province", "sea", "passage") and `size` in pixels;
## symbols carry `kind` ("mountain", "port", "capital", …), `position` and `size`.
## Mark scatter lives on `MapCanvasMarks`; Passage wash and edges on
## `MapCanvasPassages` — this file keeps the label clearing, names and compass
## so the chart pipeline stays one domain per module (REQ-P3-01).

## The clear text band a province name keeps free of marks (see `under_label`):
## horizontally either side of the type, above its cap height, below its feet.
const LABEL_HALF_WIDTH: float = 74.0
const LABEL_CLEAR_ABOVE: float = 18.0
const LABEL_CLEAR_BELOW: float = 26.0
## Air between a name stepped above its town and the hamlet's roof and spire.
const TOWN_AIR: float = 8.0
## A province with this much land carries its name at full size; a pocket
## province still carries it, one step smaller, so no province is nameless on
## the chart (issue #665: Málaga and Zaragoza fell under the old hard floor).
const NAME_ROOM: int = 26
const NAME_SIZE: int = 22
const POCKET_NAME_SIZE: int = 15

var labels: Array[Dictionary] = []
var glyphs: Array[Dictionary] = []
## World-space centres of the warp-zone passages on this region.
var passages: Array[Vector2] = []
## World-space rectangles covering the water of every warp zone, merged into
## horizontal runs so the Passage wash costs one rectangle per row of the zone.
var passage_water: Array[Rect2] = []
## World-space edges where a warp zone meets ordinary water or land, so the
## Passage wash has a drawn boundary instead of fading into the sea.
var passage_edges: Array[PackedVector2Array] = []
var compass_position: Vector2 = Vector2.ZERO
var compass_visible: bool = false


## Marks every warp zone toward another region with a ring and a quiet label so
## the way across is legible on a chart (wiki: map-topology).
func build(p_model: MapModel, p_world: WorldMap, tile_size: float) -> void:
	labels.clear()
	glyphs.clear()
	passages.clear()
	passage_water.clear()
	passage_edges.clear()
	compass_visible = false
	_add_names(p_model, tile_size)
	MapCanvasPassages.add(self, p_model, p_world, tile_size)
	MapCanvasMarks.scatter(self, p_model, tile_size)
	_find_compass_spot(p_model, tile_size)


func _add_names(p_model: MapModel, tile_size: float) -> void:
	for province: ProvinceState in p_model.provinces:
		labels.append({
			"text": province.name,
			"position": _name_position(province, p_model, tile_size),
			"size": NAME_SIZE if province.area >= NAME_ROOM else POCKET_NAME_SIZE,
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


## A province name sits on the province centre, except where its own town stands
## on it: the town tile is the estate anchor a crown works from (builders are
## sent there, roads must reach it), so the type steps above the hamlet instead
## of the hamlet hiding under the type. A capital's name already sits below its
## star. A town is a place, like a port, so only its own province's name gives
## way to it — a neighbour's name may still fall across the mark.
func _name_position(
	province: ProvinceState, p_model: MapModel, tile_size: float
) -> Vector2:
	var anchor: Vector2 = Vector2(province.center) * tile_size
	if province.capital or province.town_tile.x < 0:
		return anchor
	var town: Vector2i = province.town_tile
	if not p_model.is_land(town.x, town.y):
		return anchor
	var at: Vector2 = MapGeo.tile_center(town.x, town.y, tile_size)
	if absf(at.x - anchor.x) >= LABEL_HALF_WIDTH or not _in_label_band(at, anchor):
		return anchor
	return Vector2(anchor.x, at.y - LABEL_CLEAR_BELOW - TOWN_AIR)


## Province names sit in a clearing: a scattered symbol never lands on a label,
## so the type stays readable however dense the terrain is. Only full-size type
## reserves one — a pocket name is set smaller than a single stamp and sits
## under its parchment halo, so the scatter may pass behind it. That also keeps
## a pocket-dense chart painted instead of blanketing its ground in type.
func under_label(at: Vector2) -> bool:
	for label: Dictionary in labels:
		if String(label["kind"]) != "province" or int(label["size"]) < NAME_SIZE:
			continue
		var anchor: Vector2 = label["position"]
		if absf(at.x - anchor.x) < LABEL_HALF_WIDTH and _in_label_band(at, anchor):
			return true
	return false


static func _in_label_band(at: Vector2, anchor: Vector2) -> bool:
	return at.y > anchor.y - LABEL_CLEAR_ABOVE and at.y < anchor.y + LABEL_CLEAR_BELOW


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
