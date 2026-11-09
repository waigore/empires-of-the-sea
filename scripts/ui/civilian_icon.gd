class_name CivilianIcon
extends Control
## One civilian medallion at a fixed size: the generated painting when it is
## imported, otherwise a plain parchment disc so the row never collapses
## (REQ-P1-03). Purely presentational.

var type_id: String = "explorer"


func _init(p_type_id: String = "explorer", p_size: float = 44.0) -> void:
	type_id = CivilianCatalog.normalize(p_type_id)
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_type(p_type_id: String) -> void:
	type_id = CivilianCatalog.normalize(p_type_id)
	queue_redraw()


func _draw() -> void:
	var texture: Texture2D = CivilianArt.medallion(type_id)
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
		return
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.46
	draw_circle(center, radius, Palette.PAPER)
	draw_circle(center, radius, Palette.GOLD_DIM, false, 1.4, true)
