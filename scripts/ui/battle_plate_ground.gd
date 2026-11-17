class_name BattlePlateGround
extends RefCounted
## The painted field: terrain panoramas, horizon haze and the banded fallback
## when art is missing. Pure canvas helpers so [QuickBattleField] stays a thin
## view (REQ-P3-01) and no rule outcome is decided here (REQ-P2-03).


## The painted field from the horizon down, anchored on the painting's own
## horizon so a wide overlay and a tall simulator both sit correctly.
static func draw(
	canvas: CanvasItem, width: float, height: float, horizon: float, terrain: String
) -> void:
	var entry: Dictionary = BattlePlateAssets.PLATES.get(
		terrain, BattlePlateAssets.PLATES["open"]
	) as Dictionary
	var tex: Texture2D = BattlePlateAssets.texture(String(entry.get("path", "")))
	if tex == null:
		_fallback(canvas, width, height, horizon)
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


## Banded field for a missing plate: the plate never fails to paint.
static func _fallback(
	canvas: CanvasItem, width: float, height: float, horizon: float
) -> void:
	var rows: Array[Color] = [
		Color(0.46, 0.64, 0.26), Color(0.39, 0.57, 0.22), Color(0.31, 0.48, 0.18),
	]
	canvas.draw_rect(Rect2(0, 0, width, horizon), Color(0.55, 0.68, 0.78))
	for band in 3:
		var top: float = horizon + (height - horizon) * 0.34 * float(band)
		canvas.draw_rect(Rect2(0, top, width, height - top), rows[band])
