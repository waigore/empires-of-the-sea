class_name MapGround
extends RefCounted
## Small ground marks that fill a province between the big symbols: low scrub,
## ploughed strips and tussocks. Kept apart from `MapGlyphs` so neither file
## grows past the architecture line cap, and so a province can be given a
## second, smaller stamp without repeating the first one.

const INK: Color = Color(0.149, 0.118, 0.082, 0.72)


## Low scrub: three sage clumps on a shared stem. Darker and finer than a
## hardwood crown, so a scrub province reads differently from a forest.
static func scrub(item: CanvasItem, center: Vector2, size: float, flip: float) -> void:
	var radius: float = size * 0.24
	for i in 3:
		var offset := Vector2(
			(float(i) - 1.0) * radius * 1.30 * flip,
			radius * (0.22 if i % 2 == 0 else -0.10)
		)
		var spot: Vector2 = center + offset
		item.draw_circle(spot, radius, Color(0.298, 0.357, 0.251, 0.60))
		item.draw_arc(spot, radius, 0, TAU, 10, Color(0.153, 0.196, 0.133, 0.58), 0.9, true)
	item.draw_line(
		center + Vector2(0, radius), center + Vector2(0, size * 0.36), INK, 0.9, true
	)


## Ploughed strips: a fan of shallow furrows, the sign of worked farmland.
static func field(item: CanvasItem, center: Vector2, size: float) -> void:
	var ink := Color(0.451, 0.376, 0.243, 0.40)
	for i in 4:
		var offset: float = (float(i) - 1.5)
		var half: float = size * (0.30 - absf(offset) * 0.035)
		var y: float = offset * size * 0.15
		item.draw_line(
			center + Vector2(-half, y), center + Vector2(half, y + size * 0.05), ink, 0.9, true
		)


## Marsh reeds: three leaning stems on a waterline, darker than grass tufts.
static func reed(item: CanvasItem, center: Vector2, size: float) -> void:
	for i in 3:
		var offset: float = (float(i) - 1.0) * size * 0.18
		item.draw_line(
			center + Vector2(offset, size * 0.40),
			center + Vector2(offset * 1.7, -size * 0.36),
			Color(0.259, 0.325, 0.216, 0.62), 1.1, true
		)
	item.draw_line(
		center + Vector2(-size * 0.30, size * 0.40),
		center + Vector2(size * 0.30, size * 0.40),
		Color(0.208, 0.267, 0.180, 0.42), 0.9, true
	)


## Two strokes of grass, the quietest mark on a plain.
static func grass(item: CanvasItem, center: Vector2, size: float) -> void:
	for i in 2:
		var offset: float = (float(i) - 0.5) * size * 0.22
		item.draw_line(
			center + Vector2(offset, size * 0.30),
			center + Vector2(offset * 2.1, -size * 0.14),
			Color(0.420, 0.376, 0.235, 0.42), 1.0, true
		)
