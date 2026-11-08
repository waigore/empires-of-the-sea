class_name Icon
extends Control
## Small hand-drawn pictograms used by the HUD. Vector, so they stay crisp at
## every scale and need no atlas (REQ-P4-04).

var kind: String = "coin"
var tint: Color = Palette.GOLD


func _init(p_kind: String = "coin", p_size: float = 18.0, p_tint: Color = Palette.GOLD) -> void:
	kind = p_kind
	tint = p_tint
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5
	match kind:
		"coin":
			_draw_coin(center, radius)
		"star":
			_draw_star(center, radius)
		"ship":
			_draw_ship(center, radius)
		"anchor":
			_draw_anchor(center, radius)
		"tree":
			_draw_tree(center, radius)
		"ore":
			_draw_ore(center, radius)
		"wheat":
			_draw_wheat(center, radius)
		"fish":
			_draw_fish(center, radius)
		"crest":
			_draw_crest(center, radius)
		"crown":
			_draw_crown(center, radius)
		"compass":
			_draw_compass(center, radius)
		"bell":
			_draw_bell(center, radius)
		_:
			draw_circle(center, radius * 0.6, tint)


func _draw_coin(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.92, tint)
	draw_circle(center, radius * 0.92, Palette.INK, false, 1.2, true)
	draw_circle(center, radius * 0.62, Color(0, 0, 0, 0), false, 1.0, true)
	draw_line(
		center + Vector2(0, -radius * 0.4), center + Vector2(0, radius * 0.4),
		Palette.INK, 1.2, true
	)
	draw_line(
		center + Vector2(-radius * 0.28, 0), center + Vector2(radius * 0.28, 0),
		Palette.INK, 1.2, true
	)


func _draw_star(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle: float = TAU * float(i) / 10.0 - PI * 0.5
		var length: float = radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * length)
	draw_colored_polygon(points, tint)


func _draw_ship(center: Vector2, radius: float) -> void:
	var ink := Palette.INK
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(-radius * 0.9, radius * 0.15),
			center + Vector2(-radius * 0.55, radius * 0.6),
			center + Vector2(radius * 0.55, radius * 0.6),
			center + Vector2(radius * 0.9, radius * 0.15),
		]),
		tint
	)
	draw_line(
		center + Vector2(0, radius * 0.15), center + Vector2(0, -radius * 0.85), ink, 1.2, true
	)
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0, -radius * 0.8),
			center + Vector2(radius * 0.6, -radius * 0.1),
			center + Vector2(0, -radius * 0.1),
		]),
		Color(0.96, 0.92, 0.81)
	)


func _draw_anchor(center: Vector2, radius: float) -> void:
	var ink := tint
	draw_arc(
		center + Vector2(0, radius * 0.2), radius * 0.7, PI * 0.1, PI * 0.9, 16, ink, 1.6, true
	)
	draw_line(
		center + Vector2(0, -radius * 0.85), center + Vector2(0, radius * 0.35), ink, 1.6, true
	)
	draw_line(
		center + Vector2(-radius * 0.4, -radius * 0.45),
		center + Vector2(radius * 0.4, -radius * 0.45), ink, 1.4, true
	)
	draw_circle(center + Vector2(0, -radius * 0.9), radius * 0.14, ink)


func _draw_tree(center: Vector2, radius: float) -> void:
	draw_line(
		center + Vector2(0, radius * 0.9), center + Vector2(0, radius * 0.1),
		Palette.INK, 1.4, true
	)
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0, -radius * 0.95),
			center + Vector2(radius * 0.7, radius * 0.2),
			center + Vector2(-radius * 0.7, radius * 0.2),
		]),
		tint
	)


func _draw_ore(center: Vector2, radius: float) -> void:
	for offset: Vector2 in [Vector2(-0.35, 0.25), Vector2(0.35, 0.25), Vector2(0, -0.35)]:
		var spot: Vector2 = center + offset * radius
		draw_colored_polygon(
			PackedVector2Array([
				spot + Vector2(0, -radius * 0.42),
				spot + Vector2(radius * 0.36, 0),
				spot + Vector2(0, radius * 0.42),
				spot + Vector2(-radius * 0.36, 0),
			]),
			tint
		)


func _draw_wheat(center: Vector2, radius: float) -> void:
	draw_line(
		center + Vector2(0, radius * 0.95), center + Vector2(0, -radius * 0.5),
		Palette.INK, 1.3, true
	)
	for i in 3:
		var y: float = -radius * 0.5 + float(i) * radius * 0.35
		draw_line(
			center + Vector2(0, y), center + Vector2(-radius * 0.5, y - radius * 0.25),
			tint, 1.6, true
		)
		draw_line(
			center + Vector2(0, y), center + Vector2(radius * 0.5, y - radius * 0.25),
			tint, 1.6, true
		)


func _draw_fish(center: Vector2, radius: float) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(-radius * 0.8, 0),
			center + Vector2(-radius * 0.2, -radius * 0.45),
			center + Vector2(radius * 0.5, 0),
			center + Vector2(-radius * 0.2, radius * 0.45),
		]),
		tint
	)
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(radius * 0.45, 0),
			center + Vector2(radius * 0.9, -radius * 0.4),
			center + Vector2(radius * 0.9, radius * 0.4),
		]),
		tint
	)


func _draw_crest(center: Vector2, radius: float) -> void:
	var shield := PackedVector2Array([
		center + Vector2(-radius * 0.72, -radius * 0.85),
		center + Vector2(radius * 0.72, -radius * 0.85),
		center + Vector2(radius * 0.72, radius * 0.1),
		center + Vector2(0, radius * 0.95),
		center + Vector2(-radius * 0.72, radius * 0.1),
	])
	draw_colored_polygon(shield, Palette.CRIMSON)
	draw_polyline(shield, Palette.GOLD, 1.6, true)
	# tower
	var tower := Rect2(
		center + Vector2(-radius * 0.3, -radius * 0.35), Vector2(radius * 0.6, radius * 0.7)
	)
	draw_rect(tower, Palette.GOLD)
	for i in 3:
		var x: float = tower.position.x + float(i) * radius * 0.24
		var merlon := Rect2(
			Vector2(x, tower.position.y - radius * 0.18), Vector2(radius * 0.14, radius * 0.2)
		)
		draw_rect(merlon, Palette.GOLD)
	draw_rect(
		Rect2(center + Vector2(-radius * 0.1, radius * 0.1), Vector2(radius * 0.2, radius * 0.25)),
		Palette.CRIMSON
	)


func _draw_crown(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array([
		center + Vector2(-radius * 0.85, radius * 0.5),
		center + Vector2(-radius * 0.85, -radius * 0.35),
		center + Vector2(-radius * 0.4, radius * 0.05),
		center + Vector2(0, -radius * 0.6),
		center + Vector2(radius * 0.4, radius * 0.05),
		center + Vector2(radius * 0.85, -radius * 0.35),
		center + Vector2(radius * 0.85, radius * 0.5),
	])
	draw_colored_polygon(points, tint)
	draw_line(
		center + Vector2(-radius * 0.85, radius * 0.5),
		center + Vector2(radius * 0.85, radius * 0.5), Palette.INK, 1.2, true
	)


func _draw_compass(center: Vector2, radius: float) -> void:
	draw_arc(center, radius * 0.9, 0, TAU, 32, tint, 1.4, true)
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0, -radius * 0.75),
			center + Vector2(radius * 0.22, 0),
			center + Vector2(0, radius * 0.75),
			center + Vector2(-radius * 0.22, 0),
		]),
		tint
	)


func _draw_bell(center: Vector2, radius: float) -> void:
	var dome := center + Vector2(0, radius * 0.2)
	var width := radius * 0.56
	draw_arc(dome, width, PI, TAU, 20, tint, maxf(1.0, radius * 0.13), true)
	var lip_y: float = dome.y + radius * 0.3
	draw_line(dome + Vector2(-width, 0), Vector2(dome.x - width, lip_y), tint,
		maxf(1.0, radius * 0.13), true)
	draw_line(dome + Vector2(width, 0), Vector2(dome.x + width, lip_y), tint,
		maxf(1.0, radius * 0.13), true)
	draw_line(Vector2(dome.x - width * 1.15, lip_y), Vector2(dome.x + width * 1.15, lip_y),
		tint, maxf(1.0, radius * 0.13), true)
	draw_circle(Vector2(dome.x, lip_y + radius * 0.16), radius * 0.12, tint)
