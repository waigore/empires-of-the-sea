class_name BattlePlateWall
extends RefCounted
## Painted fort curtain, gate breaches and the standards that fly on the wall.
## Pure canvas helpers so [QuickBattleField] stays a thin view (REQ-P3-01) and no
## rule outcome is decided here (REQ-P2-03).

const GATES: int = 3

## The curtain's share of the plate height: a base a levy wall already stands
## above the field, and a step per level of the ladder. The whole five-level line
## is drawn (Wood 1 … Star 5), because the plate prints the level it is hiding
## behind: a Bastion or a Star wall drawn at Modern's height reads as a Modern
## fort beside a wall block that names the higher level (wiki: siege-mechanics
## § Fort Levels — one ladder of five, DR-20261122-16).
const HEIGHT_BASE: float = 0.10
const HEIGHT_STEP: float = 0.030


## Height of a fort's wall at this plate height: a curtain a garrison can stand
## on, growing with the era.
static func wall_height(height: float, fort: int) -> float:
	return height * (
		HEIGHT_BASE + HEIGHT_STEP * float(FortRules.clamp_level(fort))
	)


## The painted wall a level stands behind. Three paintings ship — wood, stone
## and modern — so the ladder's last two eras stand taller on the Modern
## painting and never index past the shelf.
static func wall_art(fort: int) -> String:
	var index: int = mini(maxi(fort, 1), BattlePlateAssets.WALLS.size() - 1)
	return BattlePlateAssets.WALLS[index]


## Where the garrison stands when a wall shields it: the parapet walk, so the
## wall reads as theirs and the attackers come at it from below.
static func parapet_y(height: float, fort: int) -> float:
	return height * BattlePlateAssets.GROUND - wall_height(height, fort) + height * 0.012


## Three painted wall segments, one gatehouse each, with rubble where a gate has
## been beaten down (wiki: siege-mechanics § Gates). The painting is the level's
## era where one exists: three ship (wood, stone, modern), and the ladder's last
## two eras stand on the Modern painting, taller by `wall_height`.
static func draw(
	canvas: CanvasItem, width: float, height: float, fort: int, broken: int,
	color: Color, time: float
) -> void:
	if fort <= 0:
		return
	var tex: Texture2D = BattlePlateAssets.texture(wall_art(fort))
	if tex == null:
		return
	var ground: float = height * BattlePlateAssets.GROUND
	var left: float = width * 0.56
	var right: float = width * 0.98
	var wall_h: float = wall_height(height, fort)
	var span: float = (right - left) / float(GATES)
	# The wall's shadow on the field, and grass growing against its foot.
	for band in 3:
		var t: float = float(band) / 3.0
		canvas.draw_rect(
			Rect2(left - 10.0 - t * 8.0, ground + t * 3.0,
				right - left + 20.0 + t * 16.0, 3.5),
			Color(0.08, 0.06, 0.03, 0.30 - t * 0.09)
		)
	for index in GATES:
		var centre: float = left + span * (float(index) + 0.5)
		_segment(canvas, tex, centre, ground, span, wall_h, Color(1.0, 0.98, 0.94))
	for index in mini(broken, GATES):
		_breach(canvas, left + span * (float(index) + 0.5), ground, span, wall_h, time)
	for tuft in 14:
		var x: float = left + fposmod(float(tuft) * 37.0, right - left)
		var tall: float = 3.0 + fposmod(float(tuft) * 13.0, 5.0)
		canvas.draw_line(
			Vector2(x, ground - 1.0), Vector2(x + 1.5, ground - tall),
			Color(0.22, 0.28, 0.12, 0.85), 1.2
		)
	draw_standard(canvas, Vector2(left + span * 0.16, ground - wall_h + 2.0), color, time)


## The merlons alone, painted again over the garrison so the defenders stand
## behind the parapet instead of on top of it.
static func draw_crest(
	canvas: CanvasItem, width: float, height: float, fort: int
) -> void:
	if fort <= 0:
		return
	var tex: Texture2D = BattlePlateAssets.texture(wall_art(fort))
	if tex == null:
		return
	var ground: float = height * BattlePlateAssets.GROUND
	var left: float = width * 0.56
	var right: float = width * 0.98
	var wall_h: float = wall_height(height, fort)
	var span: float = (right - left) / float(GATES)
	var art := Vector2(float(tex.get_width()), float(tex.get_height()))
	var crown: float = 0.15
	for index in GATES:
		var centre: float = left + span * (float(index) + 0.5)
		var drawn: Vector2 = _segment_drawn(art, span, wall_h)
		var rect := Rect2(centre - drawn.x * 0.5, ground - drawn.y,
			drawn.x, drawn.y * crown)
		var source := Rect2(0.0, 0.0, art.x, art.y * crown)
		canvas.draw_texture_rect_region(tex, rect, source, Color(1.0, 0.98, 0.94))


static func _segment_drawn(art: Vector2, span: float, wall_h: float) -> Vector2:
	var segment := Vector2(span * 1.04, wall_h)
	return art * maxf(segment.x / art.x, segment.y / art.y)


static func _segment(
	canvas: CanvasItem, tex: Texture2D, centre: float, ground: float, span: float,
	wall_h: float, tint: Color
) -> void:
	var art := Vector2(float(tex.get_width()), float(tex.get_height()))
	var drawn: Vector2 = _segment_drawn(art, span, wall_h)
	canvas.draw_texture_rect(
		tex, Rect2(centre - drawn.x * 0.5, ground - drawn.y, drawn.x, drawn.y), false, tint
	)


## A beaten-down gate: a jagged hole, a heap of rubble at its foot and the dust
## the last round left hanging (wiki: siege-mechanics § Gates).
static func _breach(
	canvas: CanvasItem, centre: float, ground: float, span: float, wall_h: float,
	time: float
) -> void:
	var width: float = span * 0.56
	var height: float = wall_h * 0.62
	var half: float = width * 0.5
	var mouth := PackedVector2Array([
		Vector2(centre - half, ground),
		Vector2(centre - half * 0.92, ground - height * 0.52),
		Vector2(centre - half * 0.56, ground - height * 0.80),
		Vector2(centre - half * 0.18, ground - height * 0.97),
		Vector2(centre + half * 0.26, ground - height * 0.86),
		Vector2(centre + half * 0.66, ground - height * 0.99),
		Vector2(centre + half * 0.94, ground - height * 0.58),
		Vector2(centre + half, ground),
	])
	canvas.draw_colored_polygon(mouth, Color(0.05, 0.04, 0.03, 0.96))
	# The hole still has depth: a dim interior behind the gate line.
	var inner := PackedVector2Array()
	for point: Vector2 in mouth:
		inner.append(Vector2(
			centre + (point.x - centre) * 0.72,
			ground - (ground - point.y) * 0.80
		))
	canvas.draw_colored_polygon(inner, Color(0.17, 0.14, 0.11, 0.85))
	# Broken stone still clinging to the lip of the hole.
	for chip in 9:
		var t: float = float(chip) / 8.0
		var edge: Vector2 = mouth[mini(chip, mouth.size() - 1)]
		var depth: float = 3.0 + fposmod(float(chip) * 7.0, 5.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			edge,
			edge + Vector2(-depth * 0.7, -depth * 1.4),
			edge + Vector2(depth * 0.8, -depth * 0.9 - t * 2.0),
		]), Color(0.55, 0.52, 0.45, 0.9))
	# The heap spills out of the gate onto the field, so it reads at a glance.
	var rubble: Texture2D = BattlePlateAssets.texture(BattlePlateAssets.RUBBLE)
	if rubble != null:
		var art := Vector2(float(rubble.get_width()), float(rubble.get_height()))
		var drawn_h: float = wall_h * 0.42
		var drawn := art * (drawn_h / art.y)
		var breathe: float = 1.0 + sin(time * 1.3 + centre) * 0.02
		canvas.draw_texture_rect(
			rubble,
			Rect2(centre - drawn.x * breathe * 0.5, ground - drawn.y * 0.62 * breathe,
				drawn.x * breathe, drawn.y * breathe),
			false, Color(1.0, 0.97, 0.92, 0.98)
		)
	# Fallen blocks spilling out of the gate onto the field.
	for chip in 5:
		var t: float = float(chip) / 4.0
		var block_x: float = centre + (t - 0.5) * width * 1.7
		var block_w: float = width * (0.16 + float(chip % 3) * 0.05)
		var block_h: float = wall_h * (0.05 + float((chip + 1) % 3) * 0.015)
		var block_y: float = ground - block_h * 0.5 - float(chip % 3) * wall_h * 0.02
		canvas.draw_rect(
			Rect2(block_x - block_w * 0.5, block_y - block_h, block_w, block_h),
			Color(0.54, 0.51, 0.45, 0.95)
		)
		canvas.draw_rect(
			Rect2(block_x - block_w * 0.5, block_y - block_h, block_w, block_h * 0.34),
			Color(0.44, 0.41, 0.36, 0.95)
		)
	canvas.draw_line(
		Vector2(centre - width * 0.30, ground), Vector2(centre + width * 0.10, ground - height * 0.58),
		Color(0.27, 0.18, 0.10, 0.95), 2.4
	)
	canvas.draw_line(
		Vector2(centre + width * 0.32, ground), Vector2(centre - width * 0.04, ground - height * 0.44),
		Color(0.21, 0.14, 0.08, 0.95), 1.8
	)
	# Dust still hanging in the air above the breach.
	for puff in 3:
		var rise: float = fposmod(time * 0.05 + float(puff) * 0.23, 1.0)
		var dust := Vector2(
			centre + (float(puff) - 1.0) * width * 0.24,
			ground - height * (1.02 + rise * 0.55)
		)
		for ring in 2:
			canvas.draw_circle(
				dust, width * (0.18 + rise * 0.16) * (1.0 - float(ring) * 0.4),
				Color(0.80, 0.75, 0.66, 0.12 * (1.0 - rise) * (1.0 - float(ring) * 0.5))
			)


static func draw_standard(canvas: CanvasItem, pos: Vector2, color: Color, time: float) -> void:
	var wave: float = sin(time * 2.4) * 2.0
	canvas.draw_line(pos, pos + Vector2(0, -26), Color(0.20, 0.14, 0.08), 1.8)
	canvas.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(0, -26), pos + Vector2(16.0 + wave, -22.0),
		pos + Vector2(13.0 + wave, -10.0), pos + Vector2(0, -13.0),
	]), color.lightened(0.18))
	canvas.draw_circle(pos + Vector2(5.0, -18.0), 2.0, Palette.GOLD_PALE)
