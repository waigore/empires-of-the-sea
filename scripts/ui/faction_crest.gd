class_name FactionCrest
extends Control
## One court's shield, drawn as vectors so it stays crisp at every size and needs
## no atlas (REQ-P1-08, REQ-P4-04; DR-20261118-30). The arms themselves are
## [FactionHeraldry]'s; the outline and charges are [FactionCrestMarks]'s; this
## control only paints them, so a sheet can never invent a court's colours
## (REQ-P2-03) and the view stays a thin painter (REQ-P3-01, REQ-P3-03).
##
## A court the catalog does not know draws nothing and keeps its footprint, the
## way a missing medallion does.

## The size a court row wears: the list's rows are 46 points tall, and 30 is the
## smallest a charged shield reads at (REQ-P1-03).
const ROW_SIZE: float = 30.0
## The size the open court's page wears over its title.
const HEAD_SIZE: float = 34.0
## How much of the shield a charge fills: the rest is the field around it.
const CHARGE_SHARE: float = 0.62
## The ink edge under a gold charge, as a share of its size: a gold mark on a
## gold or olive field would sink into it, so every charge is fimbriated — the
## same marks painted once larger in ink, then the charge over them.
const FIMBRIATION: float = 1.14

var arms: Dictionary = {}


func _init(faction_id: int = -1, p_size: float = ROW_SIZE) -> void:
	arms = FactionHeraldry.blazon(faction_id)
	custom_minimum_size = Vector2(p_size, p_size)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A container owns this control's rect, so a resize must repaint the shield.
	resized.connect(queue_redraw)


## Re-arms the shield for another court: the dossier's head wears the arms of
## the court it is open on, and one control re-dresses rather than a new node
## every open (REQ-P4-04).
func set_faction(faction_id: int) -> void:
	arms = FactionHeraldry.blazon(faction_id)
	queue_redraw()


## The shield a court wears in its row.
static func of(faction_id: int, p_size: float = ROW_SIZE) -> FactionCrest:
	return FactionCrest.new(faction_id, p_size)


func _draw() -> void:
	if arms.is_empty():
		return
	var box: float = minf(size.x, size.y)
	if box < 8.0:
		return
	var centre: Vector2 = size * 0.5
	var half: float = box * 0.5
	var outline: PackedVector2Array = FactionCrestMarks.shield_points(centre, half)
	draw_colored_polygon(outline, arms["field"] as Color)
	_paint(FactionCrestMarks.division_marks(
		centre, half, arms["party"] as Color, String(arms["division"])
	))
	var charge: String = String(arms["charge"])
	var ink: Color = arms["tincture"]
	var field: Color = arms["field"]
	var reach: float = half * CHARGE_SHARE
	if ink != Palette.INK:
		_paint(FactionCrestMarks.charge_marks(
			charge, centre, reach * FIMBRIATION, Palette.INK, Palette.INK
		))
	_paint(FactionCrestMarks.charge_marks(charge, centre, reach, ink, field))
	# Two rules: an ink line so the shield reads on parchment, then the rank's own
	# bordure over it (a Great Power's bright gilt, a Minor's dim one, a Tribe's
	# plain ink).
	var rim: PackedVector2Array = _closed(outline)
	draw_polyline(rim, Palette.INK, maxf(1.6, box * 0.075), true)
	draw_polyline(rim, arms["bordure"] as Color, maxf(1.0, box * 0.045), true)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = points.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


## Paints one list of marks: a filled polygon, a rectangle, a stroked line, a
## polyline, an arc or a circle — the six shapes the mark table uses.
func _paint(marks: Array[Dictionary]) -> void:
	for mark: Dictionary in marks:
		match String(mark["kind"]):
			"rect":
				draw_rect(mark["rect"] as Rect2, mark["color"] as Color)
			"poly":
				draw_colored_polygon(
					mark["points"] as PackedVector2Array, mark["color"] as Color
				)
			"line":
				draw_line(
					mark["from"] as Vector2, mark["to"] as Vector2,
					mark["color"] as Color, float(mark["width"]), true
				)
			"polyline":
				draw_polyline(
					mark["points"] as PackedVector2Array, mark["color"] as Color,
					float(mark["width"]), true
				)
			"arc":
				draw_arc(
					mark["centre"] as Vector2, float(mark["radius"]),
					float(mark["from"]), float(mark["to"]), int(mark.get("steps", 16)),
					mark["color"] as Color, float(mark["width"]), true
				)
			"circle":
				draw_circle(
					mark["centre"] as Vector2, float(mark["radius"]), mark["color"] as Color
				)
