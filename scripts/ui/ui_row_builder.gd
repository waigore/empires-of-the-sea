class_name UiRowBuilder
extends RefCounted
## Shared row widgets for the sidebar ledgers: a fixed-height row, a themed
## label, a small button, a spacer and a non-deferred clear. Replaces the private
## `_label` / `_small_button` / `_add_spacer` copies each panel used to carry
## (REQ-P3-01, RUB-P3-01).


static func row(height: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(0, height)
	box.add_theme_constant_override("separation", 8)
	return box


static func label(text: String, size: int, color: Color) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	return out


static func caption(text: String, size: int, color: Color, width: float) -> Label:
	var out := label(text, size, color)
	out.custom_minimum_size = Vector2(width, 0)
	return out


static func button(text: String, height: float = 38.0, width: float = 78.0) -> Button:
	var out := Button.new()
	out.text = text
	out.custom_minimum_size = Vector2(width, height)
	out.add_theme_font_size_override("font_size", 13)
	return out


static func spacer(parent: Node, height: float = 10.0) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, height)
	parent.add_child(pad)


## Removes and frees every child at once, so a rebuilt body never doubles up.
static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
