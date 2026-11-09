class_name TopBarOrnament
extends Control
## Engraved backing for the cartouche: a varnished beam, a gilded double rule
## and a faint compass rose. Drawn, not imported, so it scales with the bar and
## adds no atlas weight (REQ-P1-02, REQ-P4-04).

const BANDS: int = 16


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	_beam(w, h)
	_compass(Vector2(w * 0.54, h * 0.5), minf(h * 0.38, 22.0))


## Vertical varnish: warm at the top light, near-black in the shadow.
func _beam(w: float, h: float) -> void:
	var band: float = h / float(BANDS)
	for i in BANDS:
		var t: float = float(i) / float(BANDS - 1)
		var shade: Color = Color(0.145, 0.113, 0.079).lerp(Color(0.052, 0.043, 0.034), t)
		draw_rect(Rect2(0.0, band * float(i), w, band + 1.0), shade)
	var top := Palette.GOLD_DIM
	top.a = 0.28
	draw_line(Vector2(0.0, 0.5), Vector2(w, 0.5), top, 1.0)
	var lower := Palette.GOLD_DIM
	lower.a = 0.45
	draw_line(Vector2(0.0, h - 4.0), Vector2(w, h - 4.0), lower, 1.0)
	var edge := Palette.GOLD
	edge.a = 0.55
	draw_line(Vector2(0.0, h - 1.0), Vector2(w, h - 1.0), edge, 1.0)


## Eight-point rose, kept barely above the varnish so it reads as an inlay.
func _compass(center: Vector2, radius: float) -> void:
	if radius <= 2.0:
		return
	var ink := Palette.GOLD_PALE
	ink.a = 0.10
	draw_arc(center, radius, 0.0, TAU, 40, ink, 1.0, true)
	draw_arc(center, radius * 0.62, 0.0, TAU, 32, ink, 0.8, true)
	for i in 8:
		var angle: float = TAU * float(i) / 8.0 - PI * 0.5
		var dir := Vector2(cos(angle), sin(angle))
		var long: float = radius if i % 2 == 0 else radius * 0.72
		draw_line(center + dir * radius * 0.18, center + dir * long, ink, 1.0, true)
	draw_circle(center, 1.2, ink)
