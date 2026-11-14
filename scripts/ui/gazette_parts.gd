class_name GazetteParts
extends RefCounted
## The printed page's kit: a serif line, a rule and a gap. The Gazette plate and
## its watchlist editor both print on the same paper, so the three primitives
## live here instead of in each sheet (REQ-P3-01).


## A serif line in the sheet's ink; `italic` is the paper's aside voice.
static func label(text: String, pixels: int, ink: Color, italic: bool = false) -> Label:
	var line := Label.new()
	line.text = text
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_override("font", UiTheme.serif_italic() if italic else UiTheme.serif())
	line.add_theme_font_size_override("font_size", pixels)
	line.add_theme_color_override("font_color", ink)
	return line


## A printed rule: the hairline that divides a gazette's columns.
static func rule(ink: Color, thickness: int = 1) -> Control:
	var line := ColorRect.new()
	line.color = ink
	line.custom_minimum_size = Vector2(0, thickness)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## A gap between printed blocks.
static func spacer(height: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap
