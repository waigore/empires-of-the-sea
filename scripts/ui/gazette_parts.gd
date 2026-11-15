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


## An empty sheet's line: the plate and its body print the same words.
const EMPTY_LINE: String = "Nothing reached the presses this turn."


## A sheet's items, grouped World -> Our court -> Courts of interest: a heading
## is printed whenever the class changes (wiki: the-gazette § Classes). Lives
## here because both the live sheet and its archive print the same body.
static func sections(body: Node, sheet: Dictionary) -> void:
	var items: Array = sheet.get("items", []) as Array
	if items.is_empty():
		body.add_child(label(EMPTY_LINE, 14, Palette.INK))
		return
	var last: int = -1
	for raw: Variant in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw
		var cls: int = int(item.get("class", Gazette.Class.COURT))
		if cls != last:
			if last >= 0:
				body.add_child(spacer(8))
			body.add_child(rule(Palette.INK_FAINT))
			body.add_child(label(Gazette.heading(cls), 11, Color(0.45, 0.33, 0.12)))
			last = cls
		var text: String = String(item.get("text", ""))
		if not text.is_empty():
			body.add_child(label(text, 14, Palette.INK))
