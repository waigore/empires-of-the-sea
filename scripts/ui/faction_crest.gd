class_name FactionCrest
extends Control
## One court's shield, drawn as vectors so it stays crisp at every size and needs
## no atlas (REQ-P1-08, REQ-P4-04; DR-20261118-30). The arms themselves are
## [FactionHeraldry]'s; this control only paints them, so a sheet can never
## invent a court's colours (REQ-P2-03).
##
## What a shield is made of is plain data — the outline, the division's parting
## lines and the charge's marks — so every charge is proved without a renderer
## and the view stays a dozen lines (REQ-P3-03). A court the catalog does not
## know draws nothing and keeps its footprint, the way a missing medallion does.

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
## The heater shield's outline in half-extent units: square shoulders, a point at
## the foot. Nine points hold the curve, so the outline costs nothing a frame.
const SHIELD: Array[Vector2] = [
	Vector2(-0.76, -0.86), Vector2(0.76, -0.86), Vector2(0.76, -0.06),
	Vector2(0.58, 0.34), Vector2(0.26, 0.68), Vector2(0.0, 0.88),
	Vector2(-0.26, 0.68), Vector2(-0.58, 0.34), Vector2(-0.76, -0.06),
]

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
	var outline: PackedVector2Array = shield_points(centre, half)
	draw_colored_polygon(outline, arms["field"] as Color)
	_paint(division_marks(centre, half, arms["party"] as Color, String(arms["division"])))
	var charge: String = String(arms["charge"])
	var ink: Color = arms["tincture"]
	var field: Color = arms["field"]
	var reach: float = half * CHARGE_SHARE
	if ink != Palette.INK:
		_paint(charge_marks(charge, centre, reach * FIMBRIATION, Palette.INK, Palette.INK))
	_paint(charge_marks(charge, centre, reach, ink, field))
	# Two rules: an ink line so the shield reads on parchment, then the rank's own
	# bordure over it (a Great Power's bright gilt, a Minor's dim one, a Tribe's
	# plain ink).
	var rim: PackedVector2Array = _closed(outline)
	draw_polyline(rim, Palette.INK, maxf(1.6, box * 0.075), true)
	draw_polyline(rim, arms["bordure"] as Color, maxf(1.0, box * 0.045), true)


# --- the shield's data -------------------------------------------------------


## The outline in the control's own points, so a caller can measure the shield
## it paints.
static func shield_points(centre: Vector2, half: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for spot: Vector2 in SHIELD:
		points.append(centre + spot * half)
	return points


## The parting lines a divided field is cut with, in the party colour: two lines
## quarter the field, one band cuts it on the bend, and a plain field takes
## nothing (the same tuple that told a court from its neighbour).
static func division_marks(
	centre: Vector2, half: float, party: Color, division: String
) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var width: float = maxf(1.0, half * 0.13)
	match division:
		"quarterly":
			marks.append(_line(
				centre + Vector2(0, -half * 0.84), centre + Vector2(0, half * 0.52),
				party, width
			))
			marks.append(_line(
				centre + Vector2(-half * 0.74, -half * 0.12),
				centre + Vector2(half * 0.74, -half * 0.12), party, width
			))
		"per_bend":
			marks.append(_poly(PackedVector2Array([
				centre + Vector2(-half * 0.78, -half * 0.30),
				centre + Vector2(half * 0.10, -half * 0.86),
				centre + Vector2(half * 0.78, -half * 0.30),
				centre + Vector2(-half * 0.10, -half * 0.02),
			]), party))
	return marks


## One charge's marks: the same shape at any size, in the field's earned
## tincture. Every id in [member FactionHeraldry.CHARGES] answers with at least
## one mark, so a shield always bears something.
static func charge_marks(
	charge: String, centre: Vector2, size: float, ink: Color, field: Color
) -> Array[Dictionary]:
	var bar: float = maxf(1.4, size * 0.32)
	match charge:
		"cross":
			return [
				_rect(_at(centre, -bar * 0.5, -size * 0.9, bar, size * 1.8), ink),
				_rect(_at(centre, -size * 0.9, -bar * 0.5, size * 1.8, bar), ink),
			]
		"saltire":
			return [
				_line(centre + Vector2(-size * 0.8, -size * 0.8),
					centre + Vector2(size * 0.8, size * 0.8), ink, bar),
				_line(centre + Vector2(size * 0.8, -size * 0.8),
					centre + Vector2(-size * 0.8, size * 0.8), ink, bar),
			]
		"chevron":
			return [_poly(PackedVector2Array([
				centre + Vector2(-size * 0.86, -size * 0.24),
				centre + Vector2(0, -size * 0.72),
				centre + Vector2(size * 0.86, -size * 0.24),
				centre + Vector2(size * 0.86, size * 0.22),
				centre + Vector2(0, -size * 0.26),
				centre + Vector2(-size * 0.86, size * 0.22),
			]), ink)]
		"pale":
			return [_rect(_at(centre, -bar * 0.6, -size, bar * 1.2, size * 2.0), ink)]
		"fess":
			return [_rect(_at(centre, -size, -bar * 0.6, size * 2.0, bar * 1.2), ink)]
		"bend":
			return [_line(centre + Vector2(-size * 0.8, size * 0.8),
				centre + Vector2(size * 0.8, -size * 0.8), ink, bar)]
		"tower":
			return _tower_marks(centre, size, ink, field)
		"anchor":
			return _anchor_marks(centre, size, ink)
		"sun":
			return _sun_marks(centre, size, ink)
		"star":
			return [_poly(_star(centre, size * 0.98), ink)]
		"fleur":
			return _fleur_marks(centre, size, ink)
		"tree":
			return _tree_marks(centre, size, ink)
		"crescent":
			return [{
				"kind": "arc", "centre": centre, "radius": size * 0.78,
				"from": PI * 0.32, "to": PI * 1.68, "steps": 18,
				"width": maxf(1.6, size * 0.34), "color": ink,
			}]
		"lozenge":
			return [_poly(PackedVector2Array([
				centre + Vector2(0, -size * 0.98),
				centre + Vector2(size * 0.62, 0),
				centre + Vector2(0, size * 0.98),
				centre + Vector2(-size * 0.62, 0),
			]), ink)]
		"wave":
			return [{
				"kind": "polyline", "points": PackedVector2Array([
					centre + Vector2(-size * 0.9, size * 0.18),
					centre + Vector2(-size * 0.45, -size * 0.24),
					centre + Vector2(0, size * 0.18),
					centre + Vector2(size * 0.45, -size * 0.24),
					centre + Vector2(size * 0.9, size * 0.18),
				]), "width": maxf(1.6, size * 0.26), "color": ink,
			}]
		"arrow":
			return [
				_line(centre + Vector2(-size * 0.86, size * 0.86),
					centre + Vector2(size * 0.5, -size * 0.5), ink, bar),
				_poly(PackedVector2Array([
					centre + Vector2(size * 0.86, -size * 0.86),
					centre + Vector2(size * 0.10, -size * 0.52),
					centre + Vector2(size * 0.52, -size * 0.10),
				]), ink),
			]
		"roundel":
			return [_circle(centre, size * 0.72, ink)]
		"bars":
			var bars: Array[Dictionary] = []
			for i in 3:
				var y: float = -size * 0.62 + float(i) * size * 0.62
				bars.append(_rect(
					_at(centre, -size * 0.86, y - bar * 0.4, size * 1.72, bar * 0.8), ink
				))
			return bars
	return [_circle(centre, size * 0.55, ink)]


static func _tower_marks(
	centre: Vector2, size: float, ink: Color, field: Color
) -> Array[Dictionary]:
	var body: Rect2 = _at(centre, -size * 0.52, -size * 0.34, size * 1.04, size * 1.24)
	var marks: Array[Dictionary] = [_rect(body, ink)]
	for i in 3:
		marks.append(_rect(
			Rect2(
				Vector2(body.position.x + float(i) * size * 0.44, body.position.y - size * 0.34),
				Vector2(size * 0.24, size * 0.36)
			),
			ink
		))
	# The gate stays the field's colour, so the tower reads as a tower.
	marks.append(_rect(_at(centre, -size * 0.16, size * 0.18, size * 0.32, size * 0.72), field))
	return marks


static func _anchor_marks(centre: Vector2, size: float, ink: Color) -> Array[Dictionary]:
	return [
		_line(centre + Vector2(0, -size * 0.9), centre + Vector2(0, size * 0.5),
			ink, maxf(1.4, size * 0.22)),
		_line(centre + Vector2(-size * 0.44, -size * 0.42),
			centre + Vector2(size * 0.44, -size * 0.42), ink, maxf(1.2, size * 0.18)),
		{
			"kind": "arc", "centre": centre + Vector2(0, size * 0.12),
			"radius": size * 0.62, "from": PI * 0.08, "to": PI * 0.92, "steps": 14,
			"width": maxf(1.4, size * 0.22), "color": ink,
		},
		_circle(centre + Vector2(0, -size * 0.98), size * 0.16, ink),
	]


static func _sun_marks(centre: Vector2, size: float, ink: Color) -> Array[Dictionary]:
	var marks: Array[Dictionary] = [_circle(centre, size * 0.46, ink)]
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		marks.append(_line(
			centre + direction * size * 0.58, centre + direction * size * 0.98,
			ink, maxf(1.2, size * 0.16)
		))
	return marks


static func _fleur_marks(centre: Vector2, size: float, ink: Color) -> Array[Dictionary]:
	# A tall centre petal between two filled side petals, over a banded stem: the
	# three lobes are solid, so the mark still reads as a fleur at 26 points.
	var marks: Array[Dictionary] = [_poly(PackedVector2Array([
		centre + Vector2(0, -size * 0.98),
		centre + Vector2(size * 0.30, -size * 0.34),
		centre + Vector2(0, size * 0.10),
		centre + Vector2(-size * 0.30, -size * 0.34),
	]), ink)]
	for side: float in [-1.0, 1.0]:
		marks.append(_circle(centre + Vector2(side * size * 0.46, -size * 0.44),
			size * 0.34, ink))
	marks.append(_rect(_at(centre, -size * 0.12, 0, size * 0.24, size * 0.92), ink))
	marks.append(_rect(_at(centre, -size * 0.46, size * 0.40, size * 0.92, size * 0.20), ink))
	return marks


static func _tree_marks(centre: Vector2, size: float, ink: Color) -> Array[Dictionary]:
	# A canopy over a trunk that shows below it, so the mark reads as a tree and
	# not as a spearhead.
	return [
		_poly(PackedVector2Array([
			centre + Vector2(0, -size * 0.98),
			centre + Vector2(size * 0.78, -size * 0.10),
			centre + Vector2(-size * 0.78, -size * 0.10),
		]), ink),
		_rect(_at(centre, -size * 0.13, -size * 0.14, size * 0.26, size * 1.06), ink),
	]


static func _star(centre: Vector2, reach: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var angle: float = TAU * float(i) / 10.0 - PI * 0.5
		var length: float = reach if i % 2 == 0 else reach * 0.44
		points.append(centre + Vector2(cos(angle), sin(angle)) * length)
	return points


# --- the mark table ----------------------------------------------------------


static func _rect(box: Rect2, color: Color) -> Dictionary:
	return {"kind": "rect", "rect": box, "color": color}


static func _poly(points: PackedVector2Array, color: Color) -> Dictionary:
	return {"kind": "poly", "points": points, "color": color}


static func _line(from: Vector2, to: Vector2, color: Color, width: float) -> Dictionary:
	return {"kind": "line", "from": from, "to": to, "color": color, "width": width}


static func _circle(centre: Vector2, radius: float, color: Color) -> Dictionary:
	return {"kind": "circle", "centre": centre, "radius": radius, "color": color}


## A square in the shield's own frame, from the offset its corner sits at.
static func _at(centre: Vector2, x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(centre + Vector2(x, y), Vector2(w, h))


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
