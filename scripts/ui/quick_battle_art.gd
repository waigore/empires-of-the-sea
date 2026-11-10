class_name QuickBattleArt
extends RefCounted
## Painters for the Quick Battle plate: the ground a battle is fought over and
## the wall and gates a siege is fought through (wiki: quick-battle § Terrain,
## siege-mechanics § Gates and Sortie). Pure canvas helpers so
## [QuickBattleField] stays a thin view (REQ-P3-01, REQ-P1-03).

const HORIZON: float = 0.60


## Ground band from the horizon down, painted for the lane terrain. The features
## are deterministic by index so a replay looks the same every time.
static func draw_ground(
	canvas: CanvasItem, width: float, height: float, horizon: float,
	terrain: String, time: float
) -> void:
	var top: Color = _base(terrain, 0)
	var mid: Color = _base(terrain, 1)
	var deep: Color = _base(terrain, 2)
	canvas.draw_rect(Rect2(0, horizon, width, height - horizon), top)
	canvas.draw_rect(Rect2(0, horizon + (height - horizon) * 0.30, width, height), mid)
	canvas.draw_rect(Rect2(0, horizon + (height - horizon) * 0.66, width, height), deep)
	match terrain:
		"woods":
			_draw_woods(canvas, width, height, horizon, time)
		"hill":
			_draw_hills(canvas, width, height, horizon)
		"town":
			_draw_town(canvas, width, height, horizon)
		"marsh":
			_draw_marsh(canvas, width, height, horizon, time)
		_:
			_draw_open(canvas, width, height, horizon, time)


## The fort wall with its three gates. `broken` gates are rubble; the standing
## ones are dark arches. Drawn before the garrison so the men read as manning it.
static func draw_wall(
	canvas: CanvasItem, width: float, height: float, fort: int,
	broken: int, color: Color, time: float
) -> void:
	if fort <= 0:
		return
	var ground: float = height * 0.74
	var left: float = width * 0.56
	var right: float = width * 0.98
	var wall_h: float = 14.0 + float(fort) * 6.0
	var top: float = ground - wall_h
	var stone := Color(0.60, 0.57, 0.50)
	var shadow := Color(0.31, 0.29, 0.26)
	var crenel: float = 7.0
	canvas.draw_rect(Rect2(left, top, right - left, wall_h), stone)
	canvas.draw_rect(Rect2(left, ground - 4.0, right - left, 4.0), shadow)
	# Courses and merlons.
	canvas.draw_line(Vector2(left, top + wall_h * 0.5), Vector2(right, top + wall_h * 0.5), shadow, 1.0)
	var merlon: float = left
	while merlon < right:
		canvas.draw_rect(Rect2(merlon, top - crenel, 7.0, crenel), stone.darkened(0.08))
		merlon += 14.0
	# Standard on the gatehouse.
	var pole: Vector2 = Vector2(left + 8.0, top - crenel)
	canvas.draw_line(pole, pole + Vector2(0, -22), Color(0.22, 0.16, 0.10), 1.8)
	var wave: float = sin(time * 2.4) * 2.0
	canvas.draw_colored_polygon(PackedVector2Array([
		pole + Vector2(0, -22), pole + Vector2(15.0 + wave, -18.0),
		pole + Vector2(12.0 + wave, -9.0), pole + Vector2(0, -12.0),
	]), color.lightened(0.2))
	var gates: int = 3
	var span: float = (right - left) / float(gates + 1)
	for index in gates:
		var centre: float = left + span * float(index + 1)
		var is_broken: bool = index < broken
		_draw_gate(canvas, centre, ground, is_broken, stone, shadow, top)


static func _draw_gate(
	canvas: CanvasItem, x: float, ground: float, broken: bool,
	stone: Color, shadow: Color, top: float
) -> void:
	var gate_w: float = 15.0
	var gate_h: float = ground - top - 3.0
	if broken:
		# The breach: a rubble ramp and a dark hole where the gate stood.
		canvas.draw_rect(Rect2(x - gate_w * 0.7, ground - gate_h * 0.55, gate_w * 1.4, gate_h * 0.55),
			Color(0.10, 0.08, 0.06))
		for stone_index in 5:
			var sx: float = x - gate_w * 0.9 + float(stone_index) * 6.0
			canvas.draw_circle(Vector2(sx, ground - 2.0 - float(stone_index % 2) * 3.0),
				3.0, stone.darkened(0.2))
		return
	canvas.draw_rect(Rect2(x - gate_w * 0.5, ground - gate_h, gate_w, gate_h),
		Color(0.13, 0.10, 0.07))
	canvas.draw_rect(Rect2(x - gate_w * 0.5, ground - gate_h, gate_w, 3.0), shadow)
	# Iron banding reads at plate size.
	for band in 3:
		var y: float = ground - gate_h + 4.0 + float(band) * gate_h * 0.26
		canvas.draw_line(Vector2(x - gate_w * 0.5, y), Vector2(x + gate_w * 0.5, y),
			Color(0.42, 0.35, 0.22), 1.0)


static func _base(terrain: String, band: int) -> Color:
	var rows: Dictionary = {
		"open": [Color(0.46, 0.64, 0.26), Color(0.39, 0.57, 0.22), Color(0.31, 0.48, 0.18)],
		"hill": [Color(0.49, 0.62, 0.30), Color(0.41, 0.53, 0.24), Color(0.32, 0.43, 0.19)],
		"woods": [Color(0.32, 0.48, 0.24), Color(0.27, 0.41, 0.20), Color(0.20, 0.33, 0.16)],
		"town": [Color(0.52, 0.54, 0.38), Color(0.45, 0.45, 0.33), Color(0.35, 0.35, 0.26)],
		"marsh": [Color(0.34, 0.44, 0.32), Color(0.29, 0.38, 0.29), Color(0.22, 0.30, 0.24)],
	}
	var colors: Array = rows.get(terrain, rows["open"]) as Array
	return colors[clampi(band, 0, 2)] as Color


static func _draw_open(
	canvas: CanvasItem, width: float, height: float, horizon: float, time: float
) -> void:
	for index in 7:
		var x: float = fmod(float(index) * 173.0 + 40.0, width)
		var y: float = horizon + 10.0 + fmod(float(index) * 37.0, height - horizon - 24.0)
		canvas.draw_circle(Vector2(x, y), 22.0 + float(index % 3) * 10.0,
			Color(0.92, 0.82, 0.42, 0.06))
	for row in 5:
		var y: float = horizon + 18.0 + float(row) * (height - horizon) * 0.16
		canvas.draw_line(Vector2(0, y), Vector2(width, y + 3.0),
			Color(0.24, 0.38, 0.14, 0.22), 1.0)
	for index in 34:
		var x: float = fmod(float(index) * 97.0 + 13.0, width)
		var y: float = horizon + 8.0 + fmod(float(index) * 53.0, height - horizon - 12.0)
		var sway: float = sin(time * 1.4 + float(index)) * 2.0
		canvas.draw_line(Vector2(x, y), Vector2(x + sway, y - 8.0), Color(0.22, 0.36, 0.14), 1.5)
		if index % 4 == 0:
			canvas.draw_circle(Vector2(x + sway, y - 9.0), 2.0, Color(1.0, 0.84, 0.28))
		elif index % 7 == 0:
			canvas.draw_circle(Vector2(x + sway, y - 8.0), 1.8, Color(0.92, 0.45, 0.30))


static func _draw_hills(
	canvas: CanvasItem, width: float, height: float, horizon: float
) -> void:
	for ridge in 3:
		var lift: float = 10.0 + float(ridge) * 7.0
		var points := PackedVector2Array()
		for step in 9:
			var x: float = width * float(step) / 8.0
			var y: float = horizon + 12.0 + lift - sin(float(step) * 1.1 + float(ridge)) * lift
			points.append(Vector2(x, y))
		points.append(Vector2(width, height))
		points.append(Vector2(0, height))
		canvas.draw_colored_polygon(points, Color(0.33, 0.45, 0.22, 0.35 - float(ridge) * 0.07))
	for index in 16:
		var x: float = fmod(float(index) * 131.0 + 23.0, width)
		var y: float = horizon + 20.0 + fmod(float(index) * 47.0, height - horizon - 20.0)
		canvas.draw_line(Vector2(x - 5.0, y), Vector2(x + 6.0, y - 3.0),
			Color(0.26, 0.34, 0.16, 0.45), 1.2)


static func _draw_woods(
	canvas: CanvasItem, width: float, height: float, horizon: float, time: float
) -> void:
	# A treeline behind, then scattered trunks the shot has to pass.
	for index in 9:
		var x: float = width * (0.04 + float(index) * 0.11)
		var y: float = horizon + 8.0 + float(index % 3) * 7.0
		var scale: float = 16.0 + float(index % 4) * 4.0
		canvas.draw_rect(Rect2(x - 2.0, y - scale * 0.6, 4.0, scale * 0.7),
			Color(0.26, 0.19, 0.11))
		canvas.draw_circle(Vector2(x, y - scale * 0.8), scale * 0.62, Color(0.20, 0.34, 0.18))
		canvas.draw_circle(Vector2(x - scale * 0.3, y - scale * 0.6), scale * 0.4,
			Color(0.24, 0.39, 0.21))
	for index in 12:
		var x: float = fmod(float(index) * 149.0 + 61.0, width)
		var y: float = horizon + 22.0 + fmod(float(index) * 59.0, height - horizon - 26.0)
		var sway: float = sin(time * 1.1 + float(index)) * 1.5
		canvas.draw_line(Vector2(x, y), Vector2(x + sway, y - 14.0), Color(0.18, 0.28, 0.13), 2.0)
		canvas.draw_circle(Vector2(x + sway, y - 16.0), 4.0, Color(0.20, 0.33, 0.17))


static func _draw_town(
	canvas: CanvasItem, width: float, height: float, horizon: float
) -> void:
	# Rooftops behind the wall: the town the fort rings.
	var base: float = horizon + (height - horizon) * 0.28
	for index in 7:
		var x: float = width * (0.50 + float(index) * 0.068)
		var roof_h: float = 12.0 + float(index % 3) * 5.0
		var body_h: float = 10.0 + float(index % 2) * 6.0
		var wall_color := Color(0.72, 0.66, 0.53) if index % 2 == 0 else Color(0.62, 0.55, 0.44)
		canvas.draw_rect(Rect2(x, base - body_h, 17.0, body_h), wall_color)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(x - 2.0, base - body_h), Vector2(x + 8.5, base - body_h - roof_h),
			Vector2(x + 19.0, base - body_h),
		]), Color(0.44, 0.24, 0.17))
	# A church tower and spire behind the gatehouse.
	var tower_x: float = width * 0.83
	canvas.draw_rect(Rect2(tower_x, base - 38.0, 14.0, 38.0), Color(0.74, 0.69, 0.57))
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(tower_x - 3.0, base - 38.0), Vector2(tower_x + 7.0, base - 58.0),
		Vector2(tower_x + 17.0, base - 38.0),
	]), Color(0.38, 0.22, 0.16))
	# Cobbles in the foreground.
	for index in 40:
		var x: float = fmod(float(index) * 83.0 + 29.0, width)
		var y: float = base + 6.0 + fmod(float(index) * 41.0, height - base - 10.0)
		canvas.draw_circle(Vector2(x, y), 2.0, Color(0.30, 0.29, 0.24, 0.28))


static func _draw_marsh(
	canvas: CanvasItem, width: float, height: float, horizon: float, time: float
) -> void:
	for index in 5:
		var x: float = fmod(float(index) * 211.0 + 42.0, width)
		var y: float = horizon + 24.0 + fmod(float(index) * 67.0, height - horizon - 34.0)
		canvas.draw_circle(Vector2(x, y), 26.0 + float(index % 2) * 12.0,
			Color(0.26, 0.40, 0.42, 0.55))
		canvas.draw_circle(Vector2(x, y), 20.0 + float(index % 2) * 10.0,
			Color(0.42, 0.57, 0.55, 0.30))
	for index in 22:
		var x: float = fmod(float(index) * 113.0 + 17.0, width)
		var y: float = horizon + 12.0 + fmod(float(index) * 43.0, height - horizon - 16.0)
		var sway: float = sin(time * 1.6 + float(index)) * 2.5
		canvas.draw_line(Vector2(x, y), Vector2(x + sway, y - 13.0), Color(0.30, 0.38, 0.20), 1.4)
		canvas.draw_circle(Vector2(x + sway, y - 14.0), 2.0, Color(0.55, 0.45, 0.22))
