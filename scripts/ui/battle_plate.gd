class_name BattlePlate
extends RefCounted
## The painted battlefield: generated ground panoramas, painted wall segments
## and miniature sprites (assets/art/battle, see tools/art/battle-plate.md).
## Pure canvas helpers so [QuickBattleField] stays a thin view (REQ-P3-01) and
## no rule outcome is decided here (REQ-P2-03).

const GROUND: float = 0.74
const GATES: int = 3

## Each panorama is painted with its horizon at a known fraction of its height;
## the plate is cover-fitted and anchored on that line so the armies stand on
## the painted field at any aspect (the overlay is wide, the simulator tall).
const PLATES: Dictionary = {
	"open": {"path": "res://assets/art/battle/ground_open.jpg", "horizon": 0.445},
	"hill": {"path": "res://assets/art/battle/ground_hill.jpg", "horizon": 0.600},
	"woods": {"path": "res://assets/art/battle/ground_woods.jpg", "horizon": 0.520},
	"town": {"path": "res://assets/art/battle/ground_town.jpg", "horizon": 0.510},
	"marsh": {"path": "res://assets/art/battle/ground_marsh.jpg", "horizon": 0.550},
}
const WALLS: Array[String] = [
	"",
	"res://assets/art/battle/wall_wood.png",
	"res://assets/art/battle/wall_stone.png",
	"res://assets/art/battle/wall_modern.png",
]
const SOLDIER: String = "res://assets/art/battle/soldier.png"
const CANNON: String = "res://assets/art/battle/cannon.png"
const HORSE: String = "res://assets/art/battle/horse.png"
const RUBBLE: String = "res://assets/art/battle/rubble.png"

static var _cache: Dictionary = {}


## The painted field from the horizon down, anchored on the painting's own
## horizon so a wide overlay and a tall simulator both sit correctly.
static func draw_ground(
	canvas: CanvasItem, width: float, height: float, horizon: float, terrain: String
) -> void:
	var entry: Dictionary = PLATES.get(terrain, PLATES["open"]) as Dictionary
	var tex: Texture2D = _texture(String(entry.get("path", "")))
	if tex == null:
		_fallback_ground(canvas, width, height, horizon)
		return
	var frac: float = clampf(float(entry.get("horizon", 0.6)), 0.2, 0.9)
	var art := Vector2(float(tex.get_width()), float(tex.get_height()))
	var scale: float = maxf(
		maxf(width / art.x, horizon / (frac * art.y)),
		(height - horizon) / ((1.0 - frac) * art.y)
	)
	var size: Vector2 = art * scale
	var pos := Vector2((width - size.x) * 0.5, horizon - frac * size.y)
	canvas.draw_texture_rect(tex, Rect2(pos, size), false)
	_atmosphere(canvas, width, height, horizon)


## Warm haze on the horizon and a scrim under the rail; the painting carries the
## cloud, the drifting shade keeps the plate from reading as a still image.
static func _atmosphere(canvas: CanvasItem, width: float, height: float, horizon: float) -> void:
	var haze: float = maxf(height * 0.045, 6.0)
	for band in 4:
		var t: float = float(band) / 4.0
		canvas.draw_rect(
			Rect2(0.0, horizon - haze + haze * t, width, haze / 3.0),
			Color(1.0, 0.88, 0.62, 0.05 * (1.0 - t))
		)
	var t_ms: float = float(Time.get_ticks_msec()) * 0.001
	for index in 2:
		var span: float = (t_ms * 7.0 + float(index) * 640.0) / 160.0
		var cx: float = fposmod(span, 1.4) * width - width * 0.2
		var cy: float = horizon + (height - horizon) * (0.30 + 0.34 * float(index))
		var radius: float = width * 0.22
		for ring in 3:
			canvas.draw_circle(
				Vector2(cx, cy), radius * (1.0 - 0.22 * float(ring)),
				Color(0.10, 0.12, 0.10, 0.030)
			)
	var foot: float = height - horizon
	for band in 5:
		var t: float = float(band) / 5.0
		canvas.draw_rect(
			Rect2(0.0, height - foot * 0.22 + foot * 0.22 * t, width, foot * 0.22 / 5.0 + 1.0),
			Color(0.05, 0.04, 0.03, 0.07 * t)
		)


## Height of a fort's wall at this plate height: a curtain a garrison can stand
## on, growing with the era.
static func wall_height(height: float, fort: int) -> float:
	return height * (0.10 + 0.030 * float(clampi(fort, 0, 3)))


## Where the garrison stands when a wall shields it: the parapet walk, so the
## wall reads as theirs and the attackers come at it from below.
static func parapet_y(height: float, fort: int) -> float:
	return height * GROUND - wall_height(height, fort) + height * 0.012


## Three painted wall segments, one gatehouse each, with rubble where a gate has
## been beaten down (wiki: siege-mechanics § Gates).
static func draw_wall(
	canvas: CanvasItem, width: float, height: float, fort: int, broken: int,
	color: Color, time: float
) -> void:
	if fort <= 0:
		return
	var tex: Texture2D = _texture(WALLS[clampi(fort, 1, 3)])
	if tex == null:
		return
	var ground: float = height * GROUND
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
		_wall_segment(canvas, tex, centre, ground, span, wall_h, Color(1.0, 0.98, 0.94))
	for index in mini(broken, GATES):
		_draw_breach(canvas, left + span * (float(index) + 0.5), ground, span, wall_h, time)
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
static func draw_wall_crest(
	canvas: CanvasItem, width: float, height: float, fort: int
) -> void:
	if fort <= 0:
		return
	var tex: Texture2D = _texture(WALLS[clampi(fort, 1, 3)])
	if tex == null:
		return
	var ground: float = height * GROUND
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


static func _wall_segment(
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
static func _draw_breach(
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
	var rubble: Texture2D = _texture(RUBBLE)
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


## A painted miniature of its own type — musketeer, pikeman, rider, gun — with
## its shadow, health bar and chevrons. The sprite is tinted toward its faction
## so both sides read at a glance (REQ-P1-07). Every miniature is painted on one
## scale, so a gun stands lower than a man and a rider taller.
static func draw_soldier(
	canvas: CanvasItem, pos: Vector2, soldier_h: float, color: Color, facing: float,
	index: int, health: float, medals: int, type_id: String = ""
) -> void:
	var tex: Texture2D = RegimentMiniatures.texture(type_id)
	if tex == null:
		return
	var art := Vector2(float(tex.get_width()), float(tex.get_height()))
	var size := art * (soldier_h / RegimentMiniatures.FIGURE_HEIGHT)
	var tint: Color = Color(1.0, 1.0, 1.0).lerp(color.lightened(0.12), 0.55)
	# A file of identical clones reads as a texture; vary the coat a shade.
	tint = tint * (0.94 + 0.06 * float(index % 3) / 2.0)
	canvas.draw_set_transform(pos + Vector2(0.0, 1.0), 0.0, Vector2(1.0, 0.34))
	canvas.draw_circle(Vector2.ZERO, size.x * 0.34, Color(0.10, 0.08, 0.05, 0.22))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	canvas.draw_set_transform(pos, 0.0, Vector2(facing, 1.0))
	var body := Rect2(Vector2(-size.x * 0.5, -size.y), size)
	# A dark edge keeps a figure legible against stone or haze.
	var halo: float = maxf(soldier_h * 0.06, 1.0)
	canvas.draw_texture_rect(
		tex,
		Rect2(body.position - Vector2(halo, halo), body.size + Vector2(halo, halo) * 2.0),
		false, Color(0.06, 0.05, 0.03, 0.42)
	)
	canvas.draw_texture_rect(tex, body, false, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_condition(canvas, pos, size.x, size.y, health, medals)


static func _draw_condition(
	canvas: CanvasItem, pos: Vector2, width: float, height: float, health: float,
	medals: int
) -> void:
	var clamped: float = clampf(health, 0.0, 1.0)
	var bar_w: float = minf(maxf(width * 0.62, 8.0), 13.0)
	var fill: Color = Palette.HEALTH_HIGH.lerp(Palette.HEALTH_LOW, 1.0 - clamped)
	# A whole regiment at full strength needs no bar; a mauled one does.
	if clamped < 0.995:
		canvas.draw_rect(Rect2(pos.x - bar_w * 0.5, pos.y + 2.0, bar_w, 2.4),
			Color(0.08, 0.06, 0.04, 0.80))
		canvas.draw_rect(Rect2(pos.x - bar_w * 0.5, pos.y + 2.0, bar_w * clamped, 2.4), fill)
	if medals > 0:
		canvas.draw_texture_rect(
			ChromeIcons.texture("chevron"),
			Rect2(pos.x - 4.5, pos.y - height - 4.0, 9.0, 7.0), false,
			Color(1.0, 1.0, 1.0, 0.55 + 0.1 * float(medals))
		)


## A bronze gun on its field carriage, muzzle to `facing`, with the flash the
## round just made.
static func draw_cannon(
	canvas: CanvasItem, pos: Vector2, color: Color, facing: float, flash: float,
	gun_h: float = 18.0
) -> void:
	var tex: Texture2D = _texture(CANNON)
	var size := Vector2(gun_h * 1.55, gun_h)
	if tex != null:
		var art := Vector2(float(tex.get_width()), float(tex.get_height()))
		size = art * (gun_h / art.y)
		canvas.draw_set_transform(pos, 0.0, Vector2(facing, 1.0))
		canvas.draw_texture_rect(
			tex, Rect2(-size.x * 0.5, -size.y, size.x, size.y), false,
			Color(1.0, 1.0, 1.0).lerp(color.lightened(0.2), 0.35)
		)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if flash > 0.0:
		var muzzle: Vector2 = pos + Vector2(size.x * 0.46 * facing, -size.y * 0.72)
		canvas.draw_circle(muzzle, 9.0 * flash, Color(1.0, 0.82, 0.30, 0.85))
		canvas.draw_circle(muzzle, 4.5 * flash, Color(1.0, 0.99, 0.86))


static func draw_horse(
	canvas: CanvasItem, pos: Vector2, color: Color, height: float
) -> void:
	var tex: Texture2D = _texture(HORSE)
	if tex == null:
		return
	var art := Vector2(float(tex.get_width()), float(tex.get_height()))
	var size := art * (height / art.y)
	canvas.draw_set_transform(pos, 0.0, Vector2(1.0, 1.0))
	canvas.draw_texture_rect(
		tex, Rect2(-size.x * 0.5, -size.y, size.x, size.y), false,
		Color(1.0, 1.0, 1.0).lerp(color.lightened(0.15), 0.45)
	)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Soldier height for a plate: a miniature that still reads at map-overlay size.
static func soldier_height(height: float) -> float:
	return clampf(height * 0.062, 16.0, 40.0)


static func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D
	var tex: Texture2D = load(path) as Texture2D
	_cache[path] = tex
	return tex


## Banded field for a missing plate: the plate never fails to paint.
static func _fallback_ground(
	canvas: CanvasItem, width: float, height: float, horizon: float
) -> void:
	var rows: Array[Color] = [
		Color(0.46, 0.64, 0.26), Color(0.39, 0.57, 0.22), Color(0.31, 0.48, 0.18),
	]
	canvas.draw_rect(Rect2(0, 0, width, horizon), Color(0.55, 0.68, 0.78))
	for band in 3:
		var top: float = horizon + (height - horizon) * 0.34 * float(band)
		canvas.draw_rect(Rect2(0, top, width, height - top), rows[band])
