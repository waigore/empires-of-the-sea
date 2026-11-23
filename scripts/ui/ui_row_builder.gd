class_name UiRowBuilder
extends RefCounted
## Shared widgets for the sidebar ledgers, dossier sheets and plate screens: a
## fixed-height row, a themed label, a serif plate label, a small button, a
## spacer and a non-deferred clear. Every panel reads these instead of carrying
## its own `_label` / `_line` / `_caption` / `_clear` copy (REQ-P3-01, RUB-P3-01).


static func row(height: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(0, height)
	box.add_theme_constant_override("separation", 8)
	# A drag that starts on a row belongs to the list it sits in: the row and its
	# text pass the event on, so a thumb can scroll over them (REQ-P1-05).
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	return box


static func label(text: String, size: int, color: Color) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	out.mouse_filter = Control.MOUSE_FILTER_PASS
	return out


static func caption(text: String, size: int, color: Color, width: float = 0.0) -> Label:
	var out := label(text, size, color)
	if width > 0.0:
		out.custom_minimum_size = Vector2(width, 0)
	return out


## A prose line: wraps at the sheet's width, and reserves a column when `width`
## is positive so a ledger's facts stay aligned. An autowrapped label reports a
## one-pixel minimum width, so a row that lays one out beside a fixed column
## hands it a single glyph and the sentence prints down the margin (issues #669,
## #693); the line takes whatever width its row has left instead.
static func wrapped_line(text: String, size: int, color: Color, width: float = 0.0) -> Label:
	var out := label(text, size, color)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if width > 0.0:
		out.custom_minimum_size = Vector2(width, 0)
	return out


## The plate screens' serif voice (battle plates, setup copy): the period face
## on a label; `serif_wrapped` adds the prose wrap a narrow plate needs.
static func serif_line(text: String, size: int, color: Color) -> Label:
	var out := label(text, size, color)
	out.add_theme_font_override("font", UiTheme.serif())
	return out


## A plate's prose line: serif, wrapped so a phone never clips the sentence.
static func serif_wrapped(text: String, size: int, color: Color) -> Label:
	var out := serif_line(text, size, color)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return out


static func button(
	text: String, height: float = 38.0, width: float = 78.0, font_size: int = 13
) -> Button:
	var out := Button.new()
	out.text = text
	out.custom_minimum_size = Vector2(width, height)
	out.add_theme_font_size_override("font_size", font_size)
	return out


## A step door under a reading: the caption, the one hint that names what it
## opens, and the press. Every ledger sheet's door wears this dress, so a phone
## keeps a thumb-sized tap wherever a reading raises the next question
## (REQ-P3-01, REQ-P5-01, REQ-P5-04).
static func door(caption: String, hint: String, press: Callable, expand: bool = true) -> Button:
	var out := Button.new()
	out.text = caption
	out.tooltip_text = hint
	out.custom_minimum_size = Vector2(0, 34)
	if expand:
		out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out.add_theme_font_size_override("font_size", 12)
	out.pressed.connect(press)
	return out


## An empty themed line the caller fills afterwards.
static func line(size: int, color: Color) -> Label:
	return label("", size, color)


## Compact seal for a dossier header row: 40×40 with an 18pt glyph.
static func small_button(text: String, tip: String) -> Button:
	var out := button(text, 40.0, 40.0)
	out.add_theme_font_size_override("font_size", 18)
	out.tooltip_text = tip
	return out


## The hairline that divides a sheet's blocks: the sheet's gold at a third
## strength, so the rule reads on parchment without a second ink. A rule never
## eats a scroll drag (REQ-P1-02, REQ-P1-05).
static func rule(ink: Color = Palette.RULE_INK, thickness: int = 1) -> Control:
	var line := ColorRect.new()
	line.color = ink
	line.custom_minimum_size = Vector2(0, thickness)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func spacer(parent: Node, height: float = 10.0) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, height)
	parent.add_child(pad)


## Removes and frees every child at once, so a rebuilt body never doubles up.
static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Removes and frees every child but `keep`, so a rebuilt body keeps the press
## or arm it carries while its rows are redrawn (REQ-P3-01).
static func clear_except(parent: Node, keep: Node) -> void:
	for child: Node in parent.get_children():
		if child == keep:
			continue
		parent.remove_child(child)
		child.queue_free()
