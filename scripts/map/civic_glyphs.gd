class_name CivicGlyphs
extends RefCounted
## Chart marks for the crown's civilians, drawn where a chart has no room for a
## medallion: the Explorer's compass needle inked straight into the map.
##
## Static like `MapGlyphs`: the reading owns the node and the reveal, this owns
## the ink (`REQ-P3-03`). The mark is the one `CivilianMarker` wears, so a cue and
## the unit on the chart say the same thing (`REQ-P1-08`).


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
