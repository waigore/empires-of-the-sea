class_name UnitMedallion
extends Control
## One unit's painted medallion at a fixed size: the generated plate when it is
## imported, otherwise a plain parchment disc so a roster row never collapses
## (REQ-P1-03). Purely presentational; the type id only picks the texture.

var texture: Texture2D = null


func _init(p_texture: Texture2D = null, p_size: float = 36.0) -> void:
	texture = p_texture
	custom_minimum_size = Vector2(p_size, p_size)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A hull's own plate, so a shipyard row and a fleet roster read alike.
static func of_ship(type_id: String, p_size: float = 30.0) -> UnitMedallion:
	return UnitMedallion.new(ShipArt.medallion(type_id), p_size)


## A regiment's own plate for the roster and the drill yard.
static func of_regiment(type_id: String, p_size: float = 28.0) -> UnitMedallion:
	return UnitMedallion.new(RegimentArt.medallion(type_id), p_size)


func _draw() -> void:
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
		return
	var centre: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.46
	draw_circle(centre, radius, Palette.PAPER)
	draw_circle(centre, radius, Palette.GOLD_DIM, false, 1.4, true)
