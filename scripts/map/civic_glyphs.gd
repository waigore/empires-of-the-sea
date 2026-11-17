class_name CivicGlyphs
extends RefCounted
## Chart marks for the crown's civilians, drawn where a chart has no room for a
## medallion: the Explorer's compass needle inked straight into the map, and the
## ring that marks the ground the court's own pass would send an idle crew to.
##
## Static like `MapGlyphs`: the reading owns the node and the reveal, this owns
## the ink (`REQ-P3-03`). The mark is the one `CivilianMarker` wears, so a cue and
## the unit on the chart say the same thing (`REQ-P1-08`).

const TILE_SIZE: float = 22.0
## The pick ring's radius: wide enough to clear a crew's medallion (10.2) and
## still sit inside one tile.
const PICK_RING: float = 8.6
## Dashes around the pick ring, and the share of each step the ink covers.
const PICK_DASHES: int = 8
const PICK_DASH_SHARE: float = 0.55
## The march's dotted step: on, then the gap to the next dot.
const MARCH_DOT: float = 3.0
const MARCH_PERIOD: float = 7.0


## The Explorer's mark — a standing needle on a cross of hairlines — at `size`
## tall, `ink` for the cross and `needle` for the point.
static func explorer(
	item: CanvasItem, center: Vector2, size: float, ink: Color, needle: Color
) -> void:
	var half: float = size * 0.5
	var weight: float = maxf(size * 0.08, 1.0)
	item.draw_line(
		center + Vector2(0, -half * 0.86), center + Vector2(0, half * 0.86),
		ink, weight, true
	)
	item.draw_line(
		center + Vector2(-half * 0.86, 0), center + Vector2(half * 0.86, 0),
		ink, weight, true
	)
	item.draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0, -half * 1.02),
			center + Vector2(half * 0.34, 0),
			center + Vector2(0, half * 1.02),
			center + Vector2(-half * 0.34, 0),
		]),
		needle
	)
	item.draw_circle(center, maxf(half * 0.2, 1.0), needle.lightened(0.55))


## The ground the court's own pass would send each idle crew to, in world space:
## one mark per tile, the crew it would come from (a march only) and the fog the
## mark is read under. Pure, so a suite can assert the geometry without a canvas
## (`REQ-P3-03`). A pick whose crew is not on this chart, is already at work, or
## whose ground the crown has not charted is never marked (`REQ-P2-03`).
static func marks(
	picks: Dictionary,
	units: Array[CivilianState],
	model: MapModel,
	visibility: VisibilityModel,
	tile_size: float = TILE_SIZE
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if picks.is_empty() or model == null:
		return result
	var crews: Dictionary = {}
	for unit: CivilianState in units:
		if unit != null:
			crews[unit.id] = unit
	var seen: Dictionary = {}
	for raw: Variant in picks.keys():
		var pick: Dictionary = picks[raw]
		var tile: Vector2i = pick.get("tile", CivilianState.NO_TILE)
		if tile.x < 0 or tile.y < 0 or seen.has(tile):
			continue
		var crew: CivilianState = crews.get(int(raw), null)
		if crew == null or crew.is_working():
			continue
		var charted: int = _charted(model, visibility, tile)
		if charted == VisibilityModel.Level.UNKNOWN:
			continue
		seen[tile] = true
		var march: bool = crew.tile.x >= 0 and crew.tile != tile
		result.append({
			"tile": tile,
			"center": MapGeo.tile_center(tile.x, tile.y, tile_size),
			"from": (
				MapGeo.tile_center(crew.tile.x, crew.tile.y, tile_size)
				if march
				else Vector2.ZERO
			),
			"march": march,
			"charted": charted,
		})
	return result


## The marks inked: the step from the crew to the ground it would walk to, then
## the ring that says the court would work there. A charted-but-fogged mark fades
## with the rest of the reading, so remembered ground never reads as fresh.
static func draw_marks(
	canvas: CanvasItem, marks: Array, reveal: float, ink: Color, tint: Color
) -> void:
	for raw: Variant in marks:
		var mark: Dictionary = raw
		var alpha: float = reveal * (
			1.0 if int(mark["charted"]) == VisibilityModel.Level.FULLY_VISIBLE else 0.88
		)
		if alpha <= 0.01:
			continue
		var line := Color(ink.r, ink.g, ink.b, ink.a * alpha)
		var ring := Color(tint.r, tint.g, tint.b, tint.a * alpha)
		if bool(mark["march"]):
			march(canvas, mark["from"], mark["center"], line)
		pick(canvas, mark["center"], PICK_RING, line, ring)


## The court's own pick: a dashed ring on the ground the pass would send the crew
## to, with a plotted point at its centre. Dashes say "not yet" and the point
## says "here", so the mark never reads as the solid status ring an estate wears
## (`REQ-P1-08`, `REQ-P5-06`).
static func pick(
	item: CanvasItem, center: Vector2, radius: float, ink: Color, tint: Color
) -> void:
	var step: float = TAU / float(PICK_DASHES)
	for i in PICK_DASHES:
		var start: float = float(i) * step
		item.draw_arc(
			center, radius, start, start + step * PICK_DASH_SHARE, 6, tint, 1.6, true
		)
	var half: float = maxf(radius * 0.30, 1.6)
	var point := PackedVector2Array([
		center + Vector2(0, -half),
		center + Vector2(half, 0),
		center + Vector2(0, half),
		center + Vector2(-half, 0),
	])
	item.draw_colored_polygon(point, tint)
	item.draw_polyline(_closed(point), ink, 1.0, true)


## The step the court would order: a dotted hairline from the crew's own tile to
## the ground it would walk to, so a pick off the crew's tile reads as a march
## and not as a second crew (`REQ-P5-06`).
static func march(item: CanvasItem, from: Vector2, to: Vector2, ink: Color) -> void:
	var span: float = from.distance_to(to)
	if span <= 0.5:
		return
	var at: float = MARCH_PERIOD * 0.5
	while at < span - 2.0:
		item.draw_line(
			from.lerp(to, at / span),
			from.lerp(to, minf(at + MARCH_DOT, span) / span),
			ink, 1.3, true
		)
		at += MARCH_PERIOD


## The fog a mark is read under: no visibility model means the caller reads the
## whole chart (a rules-only suite, a lens built before the fog exists).
static func _charted(
	model: MapModel, visibility: VisibilityModel, tile: Vector2i
) -> int:
	if visibility == null:
		return VisibilityModel.Level.FULLY_VISIBLE
	return visibility.level_at(tile.x, tile.y)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if result.size() > 0:
		result.append(result[0])
	return result

