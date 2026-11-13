class_name ForceLedgerRow
extends PanelContainer
## One army or squadron in the muster roll: its medallion, where it stands, what
## it carries and a Visit action that opens its map and dossier. The row itself
## is also a tap target, so a phone needs no hover (REQ-P5-01, REQ-P5-04).

signal visit_pressed(region: int, kind: String, id: int)

var data: Dictionary = {}
var compact: bool = false

var _icon: Icon = null
var _name: Label = null
var _chip: Label = null
var _place: Label = null
var _line: Label = null
var _state: Label = null
var _visit: Button = null


func setup(row: Dictionary) -> void:
	data = row
	_build()
	_fill()


func _build() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.13, 0.11, 0.08, 0.88),
			Color(0.54, 0.43, 0.12, 0.55),
			1,
			3,
			Vector4(8, 5, 8, 5) if compact else Vector4(10, 7, 10, 7)
		)
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10 if compact else 12)
	add_child(line)

	_icon = Icon.new(_icon_kind(), 40.0 if compact else 46.0, Palette.GOLD)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(_icon)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	info.add_child(heading)

	_name = Label.new()
	_name.add_theme_font_override("font", UiTheme.serif())
	_name.add_theme_font_size_override("font_size", 17 if compact else 19)
	_name.add_theme_color_override("font_color", Palette.GOLD_PALE)
	heading.add_child(_name)

	_chip = Label.new()
	_chip.add_theme_font_size_override("font_size", 9)
	_chip.add_theme_color_override("font_color", Palette.INK)
	heading.add_child(_chip)

	_place = Label.new()
	_place.add_theme_font_size_override("font_size", 11)
	_place.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_place)

	var state := VBoxContainer.new()
	state.add_theme_constant_override("separation", 3)
	state.custom_minimum_size = Vector2(190, 0)
	state.visible = not compact
	line.add_child(state)

	_line = Label.new()
	_line.add_theme_font_size_override("font_size", 12)
	_line.add_theme_color_override("font_color", Palette.TEXT)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_child(_line)

	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 11)
	_state.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_child(_state)

	_visit = Button.new()
	_visit.text = "Visit"
	_visit.custom_minimum_size = Vector2(72 if compact else 78, 42 if compact else 36)
	_visit.add_theme_font_size_override("font_size", 13)
	_visit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_visit.pressed.connect(_visit_force)
	line.add_child(_visit)


func _fill() -> void:
	var kind: String = String(data.get("kind", ForceLedger.KIND_ARMY))
	_name.text = String(data.get("title", "Force"))
	_chip.text = kind.to_upper()
	var chip_color: Color = Palette.GOLD if kind == ForceLedger.KIND_SQUADRON else Palette.GOLD_DIM
	_chip.add_theme_stylebox_override(
		"normal", UiTheme.box(chip_color, chip_color, 0, 2, Vector4(6, 1, 6, 1))
	)
	var place: String = String(data.get("place", "Open country"))
	_place.text = "%s  ·  %s" % [place, String(data.get("region_label", "Uncharted"))]
	if compact:
		_place.text = "%s  ·  %s  ·  %s" % [
			place,
			String(data.get("line", "")),
			String(data.get("region_label", "Uncharted")),
		]
	_line.text = String(data.get("line", ""))
	_state.text = String(data.get("state", ""))
	_visit.tooltip_text = "Open %s on the map" % place


func _icon_kind() -> String:
	var kind: String = String(data.get("kind", ForceLedger.KIND_ARMY))
	return "anchor" if kind == ForceLedger.KIND_SQUADRON else "crest"


func _visit_force() -> void:
	visit_pressed.emit(
		int(data.get("region", 0)),
		String(data.get("kind", ForceLedger.KIND_ARMY)),
		int(data.get("id", -1))
	)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_visit_force()
