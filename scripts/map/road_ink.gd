class_name RoadInk
extends RefCounted
## Road and railroad strokes for the survey lens (wiki: capital-and-connectivity
## § Capital Setup, extraction-and-improvements § Transport Level). Static like
## `MapGlyphs`: the lens owns the node and the reveal, this owns the ink, so the
## drawing stays out of the projection and the plaque code (REQ-P3-03).

const TILE_SIZE: float = 22.0
const ROAD_INK := Color(0.30, 0.22, 0.14)
const UNDERLAY := Color(0.96, 0.92, 0.80)


## One stroke per projected segment. A linked road is solid ink over a pale
## underlay; a railroad adds sleepers; a road the crown's network does not reach
## is dashed and fainter, so "cut off" reads without a second colour language.
static func draw_routes(canvas: CanvasItem, segments: Array, reveal: float) -> void:
	for raw: Variant in segments:
		var segment: Dictionary = raw
		var alpha: float = reveal * (0.72 if bool(segment["linked"]) else 0.36)
		if bool(segment.get("fogged", false)):
			alpha *= 0.62
		var from: Vector2i = segment["a"]
		var to: Vector2i = segment["b"]
		var a: Vector2 = MapGeo.tile_center(from.x, from.y, TILE_SIZE)
		var b: Vector2 = MapGeo.tile_center(to.x, to.y, TILE_SIZE)
		var ink := Color(ROAD_INK.r, ROAD_INK.g, ROAD_INK.b, alpha)
		if not bool(segment["linked"]):
			_dashes(canvas, a, b, ink)
			continue
		canvas.draw_line(
			a, b, Color(UNDERLAY.r, UNDERLAY.g, UNDERLAY.b, alpha * 0.42), 4.6, true
		)
		canvas.draw_line(a, b, ink, 2.1, true)
		if bool(segment["rail"]):
			_sleepers(canvas, a, b, ink)


## Connectivity reading under the badge: a short road mark and
## `linked/developed`, so a province says how much of its extraction actually
## reaches the crown (green all linked, amber some, crimson none).
static func draw_link(
	canvas: CanvasItem,
	font: Font,
	counts: Dictionary,
	origin: Vector2,
	width: float,
	alpha: float
) -> void:
	var developed: int = int(counts.get("developed", 0))
	var linked: int = int(counts.get("linked", 0))
	var tint := Color(Palette.INK.r, Palette.INK.g, Palette.INK.b, 0.52)
	if developed > 0:
		tint = Palette.SURVEY_YIELDING
		if linked < developed:
			tint = Palette.SURVEY_BUILDING if linked > 0 else Palette.SURVEY_VACANT
	tint.a *= alpha
	canvas.draw_line(origin, origin + Vector2(5, 0), tint, 1.8, true)
	canvas.draw_line(origin + Vector2(9, 0), origin + Vector2(14, 0), tint, 1.8, true)
	var text: String = "—" if developed == 0 else "%d/%d" % [linked, developed]
	canvas.draw_string(
		font, origin + Vector2(18, 3.5), text, HORIZONTAL_ALIGNMENT_LEFT,
		width - 18.0, 10, tint
	)


## A cut road: short dashes rather than a solid line, so a break in the network
## is visible at fit zoom.
static func _dashes(canvas: CanvasItem, a: Vector2, b: Vector2, ink: Color) -> void:
	var run: float = a.distance_to(b)
	var direction: Vector2 = (b - a) / maxf(run, 0.001)
	var at: float = 1.0
	while at < run - 1.0:
		canvas.draw_line(
			a + direction * at, a + direction * minf(at + 6.0, run - 1.0), ink,
			1.6, true
		)
		at += 11.0


## Railroad sleepers across the line: level 4 reads at a glance without a legend
## colour of its own (wiki: extraction-and-improvements § Transport Level).
static func _sleepers(canvas: CanvasItem, a: Vector2, b: Vector2, ink: Color) -> void:
	var run: float = a.distance_to(b)
	var direction: Vector2 = (b - a) / maxf(run, 0.001)
	var normal := Vector2(-direction.y, direction.x)
	var at: float = 5.5
	while at < run:
		var point: Vector2 = a + direction * at
		canvas.draw_line(point - normal * 3.4, point + normal * 3.4, ink, 1.4, true)
		at += 8.5
