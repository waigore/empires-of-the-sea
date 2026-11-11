class_name UnitMedallion
extends TextureRect
## One unit's painted plate at a fixed size, cut on the shell's brass frame
## (REQ-P1-03, REQ-P4-04; tools/art/unit-medallions.md). A missing plate leaves
## an empty gap of the same width, so a roster row never shifts its columns.


func _init(p_texture: Texture2D = null, p_size: float = 30.0) -> void:
	texture = p_texture
	custom_minimum_size = Vector2(p_size, p_size)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A hull's own plate, so a shipyard row and a fleet roster read alike.
static func of_ship(type_id: String, p_size: float = 30.0) -> UnitMedallion:
	return UnitMedallion.new(ShipArt.medallion(type_id), p_size)


## A regiment's own plate for the roster and the drill yard.
static func of_regiment(type_id: String, p_size: float = 28.0) -> UnitMedallion:
	return UnitMedallion.new(RegimentArt.medallion(type_id), p_size)
