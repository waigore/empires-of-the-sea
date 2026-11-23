class_name AutoSeal
extends Button
## One of Auto mode's three bar seals — the AUTO plaque, the pace and the log
## door (wiki: auto-mode; issue #725). AutoBar decides what a seal says and when
## it shows; this control owns only its own look: the plaque face in one of two
## tonal states, and the centred icon-plus-caption row on that face.
##
## One home for the face so the three seals cannot drift apart, and one place
## that knows which tone a hover or a press wears (REQ-P3-01, REQ-P4-04).
##
## The small arsenic-white captions (`Palette.GOLD_PALE`) sit on the dark face
## of the seal; a seal the seat holds wears the warmer face and the bright rule.

## The rest face of a seal beside the cartouche: quiet and dark.
const FILL: Color = Color(0.13, 0.10, 0.07, 0.86)
## The face a seal wears once Auto holds the seat.
const FILL_LIVE: Color = Color(0.22, 0.17, 0.11, 0.92)
## The deeper face under a pointer or a held touch (hover 0.94, pressed 0.96).
const FILL_HOVER: Color = Color(0.22, 0.17, 0.11, 0.94)
const FILL_PRESSED: Color = Color(0.09, 0.07, 0.05, 0.96)

var _face: HBoxContainer = null
var _icon: Icon = null
var _caption: Label = null
var _detail: Label = null


## `stacked` seals print their caption over a dimmer detail line (the AUTO
## plaque's state phrase); a plain seal prints one bold line beside its icon.
func _init(
	p_name: String,
	p_icon: String,
	p_caption: String,
	p_tooltip: String,
	p_min_size: Vector2,
	p_stacked: bool = false
) -> void:
	name = p_name
	tooltip_text = p_tooltip
	custom_minimum_size = p_min_size
	focus_mode = Control.FOCUS_ALL
	_face = _row()
	add_child(_face)
	_icon = Icon.new(p_icon, 20.0 if p_stacked else 16.0, Palette.GOLD)
	_icon.name = "Medallion"
	_face.add_child(_icon)
	var column: Control = VBoxContainer.new() if p_stacked else _face
	if p_stacked:
		var stack := column as VBoxContainer
		stack.add_theme_constant_override("separation", -2)
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.add_child(stack)
	_caption = _label(p_caption, 13.0 if p_stacked else 12.0, Palette.GOLD_PALE)
	_caption.name = "Caption"
	column.add_child(_caption)


## The centred row the icon and caption ride, inset from the seal's face so a
## long caption never touches the border.
func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## A caption that never eats the seal's press.
func _label(text: String, font_size: float, ink: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(font_size))
	label.add_theme_color_override("font_color", ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The plaque's second line (the seat's state phrase), under the AUTO caption.
func set_detail() -> Label:
	_detail = _label("", 10.0, Palette.TEXT_DIM)
	_detail.name = "AutoState"
	var stack: VBoxContainer = _caption.get_parent() as VBoxContainer
	stack.add_child(_detail)
	return _detail


## What the seal's one bold line says.
func set_caption(text: String) -> void:
	_caption.text = text


## The seal's caption label, for a caller that hides or re-fits it (the pace
## seal drops its rate while Auto is paused).
func caption() -> Label:
	return _caption


## What the plaque's dim second line says.
func set_state_text(text: String) -> void:
	if _detail != null:
		_detail.text = text


## The brighter second line a live seat wears.
func set_state_ink(ink: Color) -> void:
	if _detail != null:
		_detail.add_theme_color_override("font_color", ink)


## Swaps the pictogram (the pace seal turns play into pause). The painter reads
## `kind` at draw time; the redraw is this seal's own (REQ-P4-04).
func set_icon(kind: String) -> void:
	_icon.kind = kind
	_icon.queue_redraw()


## The face follows the seat: live while Auto holds it, dim otherwise, and one
## deeper face under the pointer or a held touch.
func set_live(live: bool) -> void:
	add_theme_stylebox_override("normal", frame(FILL_LIVE if live else FILL))
	add_theme_stylebox_override("hover", frame(FILL_HOVER, Palette.GOLD))
	add_theme_stylebox_override("pressed", frame(FILL_PRESSED, Palette.GOLD_PALE))
	add_theme_stylebox_override("focus", frame(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE))


## The seal's face: the plaque fill, a thin border, the corner and the soft drop
## shadow every cartouche seal wears.
static func frame(fill: Color, border: Color = Palette.GOLD_DIM) -> StyleBoxFlat:
	var style: StyleBoxFlat = UiTheme.box(fill, border, 1, 3, Vector4(8, 2, 8, 2))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0.0, 1.0)
	return style
