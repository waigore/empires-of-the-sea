class_name BattlePlateFigures
extends RefCounted
## Painted miniatures on the plate: foot, guns and riders, with health bars and
## chevrons. Pure canvas helpers so [QuickBattleField] stays a thin view
## (REQ-P3-01) and no rule outcome is decided here (REQ-P2-03).


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
	var tex: Texture2D = BattlePlateAssets.texture(BattlePlateAssets.CANNON)
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
	var tex: Texture2D = BattlePlateAssets.texture(BattlePlateAssets.HORSE)
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
