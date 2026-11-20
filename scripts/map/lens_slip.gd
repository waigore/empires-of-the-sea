class_name LensSlip
extends RefCounted
## The printed reading every chart lens shares: one chamfered slip, one paper,
## one ink edge, one band ribbon and one hover rule (REQ-P1-02, REQ-P3-01). A
## band's colour wash lives in `WashBake`, the same soft edge for every lens
## (REQ-P1-03).
##
## Each lens decides *what* a slip says — a survey plaque's resource columns, the
## sea's hull and foe, the defence garrison — and this kit decides what paper it
## is printed on. The recipe lived in every lens, so a palette tweak could leave
## one reading looking like a plastic tile beside the others; it lives here once.
##
## Pure drawing: the caller's CanvasItem takes the ink, so a lens stays a view
## over its survey snapshot and the kit never reads rules state (REQ-P3-03).

## The slip's corners are cut this far back, so paper reads as paper.
const CHAMFER: float = 3.0
## A general slip's ink edge; a wider plaque reads one step darker.
const EDGE_WIDTH: float = 1.4
const PLAQUE_EDGE_WIDTH: float = 1.5
const SHADOW := Color(0.10, 0.08, 0.05, 0.32)
const SHADOW_OFFSET := Vector2(1.4, 2.2)
const FILL := Color(0.945, 0.902, 0.792, 0.99)
const EDGE_ALPHA: float = 0.90
## The engraved rule a plaque carries inside its edge.
const RULE := Color(0.420, 0.337, 0.216, 0.30)
const RULE_WIDTH: float = 0.8
const RULE_INSET: float = 2.0
const RIBBON: float = 2.4
const RIBBON_OFFSET := Vector2(2.0, 4.0)
## A ribbon stops this far inside the slip's top and bottom edges.
const RIBBON_INSET: float = 8.0
## The gold rule under a hovered reading: inset from each side, this far up.
const HOVER_SIDE: float = 2.0
const HOVER_LIFT: float = 4.0
const HOVER_HEIGHT: float = 2.0


## The slip's outline: a rectangle with its corners cut back (period paper).
static func shape(rect: Rect2, chamfer: float = CHAMFER) -> PackedVector2Array:
	var p: Vector2 = rect.position
	var e: Vector2 = rect.end
	return PackedVector2Array([
		Vector2(p.x + chamfer, p.y),
		Vector2(e.x - chamfer, p.y),
		Vector2(e.x, p.y + chamfer),
		Vector2(e.x, e.y - chamfer),
		Vector2(e.x - chamfer, e.y),
		Vector2(p.x + chamfer, e.y),
		Vector2(p.x, e.y - chamfer),
		Vector2(p.x, p.y + chamfer),
	])


## The same points moved by `offset`, for a shadow or a second rule.
static func offset(shape_points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point: Vector2 in shape_points:
		moved.append(point + by)
	return moved


## A shape closed back onto its first point, for `draw_polyline`.
static func closed(shape_points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = shape_points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


## Prints the parchment slip under a reading: the shadow, the paper, the ink edge
## and the band ribbon down the left. The lens prints its emblem and lines on top.
static func draw_slip(
	canvas: CanvasItem, rect: Rect2, alpha: float, ribbon: Color
) -> void:
	_print(canvas, rect, alpha, ribbon, EDGE_WIDTH, false)


## The wider plaque: the same slip one ink step darker, with the engraved rule
## inside its edge — the survey card that carries columns rather than a line.
static func draw_plaque(
	canvas: CanvasItem, rect: Rect2, alpha: float, ribbon: Color
) -> void:
	_print(canvas, rect, alpha, ribbon, PLAQUE_EDGE_WIDTH, true)


## The one gold rule a reading wears under the cursor, so a hover reads alike on
## every lens (REQ-P5-01).
static func hover_rule(canvas: CanvasItem, rect: Rect2, alpha: float) -> void:
	canvas.draw_rect(
		Rect2(
			Vector2(rect.position.x + HOVER_SIDE, rect.end.y - HOVER_LIFT),
			Vector2(rect.size.x - HOVER_SIDE * 2.0, HOVER_HEIGHT)
		),
		Color(Palette.GOLD.r, Palette.GOLD.g, Palette.GOLD.b, alpha)
	)


static func _print(
	canvas: CanvasItem,
	rect: Rect2,
	alpha: float,
	ribbon: Color,
	edge_width: float,
	engraved: bool
) -> void:
	var outline: PackedVector2Array = shape(rect)
	canvas.draw_colored_polygon(
		offset(outline, SHADOW_OFFSET),
		_with_alpha(SHADOW, SHADOW.a * alpha)
	)
	canvas.draw_colored_polygon(outline, _with_alpha(FILL, FILL.a * alpha))
	canvas.draw_polyline(
		closed(outline), Palette.ink(EDGE_ALPHA * alpha), edge_width, true
	)
	if engraved:
		canvas.draw_polyline(
			closed(shape(rect.grow(-RULE_INSET), RULE_INSET)),
			_with_alpha(RULE, RULE.a * alpha), RULE_WIDTH, true
		)
	var band: Color = ribbon
	band.a *= alpha
	canvas.draw_rect(
		Rect2(
			rect.position + RIBBON_OFFSET,
			Vector2(RIBBON, rect.size.y - RIBBON_INSET)
		),
		band
	)


static func _with_alpha(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, alpha)
