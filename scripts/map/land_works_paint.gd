class_name LandWorksPaint
extends RefCounted
## Estate glyphs the civilian layer leaves on the chart: roads, rails, resource
## marks and ports. Kept as CanvasItem ink so `CivilianLayer` only owns markers
## and orders (REQ-P3-01; wiki: extraction-and-improvements).


static func paint(
	item: CanvasItem, model: MapModel, works: LandWorks, tile_size: float
) -> void:
	if item == null or model == null or works == null:
		return
	for tile: Vector2i in works.developed_tiles(model):
		var point: Vector2 = MapGeo.tile_center(tile.x, tile.y, tile_size)
		var transport: int = works.transport_at(model, tile)
		if transport >= LandWorks.TRANSPORT_ROAD:
			road(item, point, transport >= LandWorks.TRANSPORT_RAIL)
		var level: int = works.improvement_at(model, tile)
		if level > 0:
			improvement(item, point, model.resource_at(tile.x, tile.y), level)
		if works.has_port(model, tile):
			port(item, point)


## A road is a dashed ink line; a railroad adds sleepers so level 4 reads at a
## glance (wiki: extraction-and-improvements § Transport Level).
static func road(item: CanvasItem, point: Vector2, rail: bool = false) -> void:
	var ink := Color(0.36, 0.26, 0.16, 0.65)
	if rail:
		item.draw_line(point + Vector2(-9, 0), point + Vector2(9, 0), ink, 1.6, true)
		for i in 3:
			var x: float = -6.0 + float(i) * 6.0
			item.draw_line(
				point + Vector2(x, -3.0), point + Vector2(x, 3.0), ink, 1.4, true
			)
		return
	item.draw_line(point + Vector2(-9, 0), point + Vector2(-3, 0), ink, 2.4, true)
	item.draw_line(point + Vector2(3, 0), point + Vector2(9, 0), ink, 2.4, true)


static func improvement(
	item: CanvasItem, point: Vector2, resource: int, level: int
) -> void:
	var ink := Palette.INK
	var tint: Color = _color(resource)
	var mark: Vector2 = point + Vector2(0, -3.0)
	match ImprovementCatalog.category(resource):
		"wood":
			item.draw_colored_polygon(
				PackedVector2Array([
					mark + Vector2(0, -5.0),
					mark + Vector2(4.2, 2.2),
					mark + Vector2(-4.2, 2.2),
				]),
				tint
			)
			item.draw_line(mark + Vector2(0, 2.0), mark + Vector2(0, 5.0), ink, 1.2, true)
		"mine":
			item.draw_colored_polygon(
				PackedVector2Array([
					mark + Vector2(0, -4.6),
					mark + Vector2(4.2, 0),
					mark + Vector2(0, 4.6),
					mark + Vector2(-4.2, 0),
				]),
				tint
			)
		"riches":
			item.draw_circle(mark, 3.8, tint)
			item.draw_circle(mark, 3.8, ink, false, 1.0, true)
		_:
			item.draw_line(mark + Vector2(0, 4.6), mark + Vector2(0, -3.0), ink, 1.3, true)
			for i in 3:
				var y: float = -3.0 + float(i) * 2.4
				item.draw_line(
					mark + Vector2(0, y), mark + Vector2(-3.4, y - 1.4), tint, 1.5, true
				)
				item.draw_line(
					mark + Vector2(0, y), mark + Vector2(3.4, y - 1.4), tint, 1.5, true
				)
	for i in level:
		var origin: Vector2 = point + Vector2(-7.5 + float(i) * 5.0, 8.0)
		item.draw_rect(Rect2(origin, Vector2(3.4, 3.4)), Palette.GOLD)
		item.draw_rect(Rect2(origin, Vector2(3.4, 3.4)), ink, false, 0.8)


static func port(item: CanvasItem, point: Vector2) -> void:
	var ink := Color(0.18, 0.24, 0.32, 0.85)
	item.draw_arc(point + Vector2(0, 5.0), 4.6, PI, TAU, 12, ink, 1.6, true)
	item.draw_line(point + Vector2(0, 0.6), point + Vector2(0, 5.0), ink, 1.4, true)


static func _color(resource: int) -> Color:
	match ImprovementCatalog.category(resource):
		"wood":
			return Color(0.34, 0.45, 0.27)
		"mine":
			return Color(0.47, 0.43, 0.38)
		"riches":
			return Palette.GOLD
		_:
			return Palette.GOLD_DIM
