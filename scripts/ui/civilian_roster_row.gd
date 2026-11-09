class_name CivilianRosterRow
extends PanelContainer
## One civilian in the roster: painted medallion, posting, order status and a
## Visit action that opens the unit's map. The row itself is also a tap target
## (REQ-P5-01, REQ-P5-04).

signal visit_pressed(region: int, unit_id: int)

var data: Dictionary = {}
var compact: bool = false

var _icon: CivilianIcon = null
var _name: Label = null
var _chip: Label = null
var _place: Label = null
var _status: Label = null
var _progress: ProgressBar = null
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

	_icon = CivilianIcon.new(String(data.get("type_id", "explorer")), 44.0 if compact else 52.0)
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
	state.add_theme_constant_override("separation", 4)
	state.custom_minimum_size = Vector2(190, 0)
	state.visible = not compact
	line.add_child(state)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Palette.TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_child(_status)

	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 5)
	_progress.add_theme_stylebox_override(
		"background", UiTheme.box(Color(0.28, 0.23, 0.16, 0.9), Color(0, 0, 0, 0), 0, 2, Vector4.ZERO)
	)
	_progress.add_theme_stylebox_override(
		"fill", UiTheme.box(Palette.GOLD, Palette.GOLD_PALE, 0, 2, Vector4.ZERO)
	)
	state.add_child(_progress)

	_visit = Button.new()
	_visit.text = "Visit"
	_visit.custom_minimum_size = Vector2(72 if compact else 78, 42 if compact else 36)
	_visit.add_theme_font_size_override("font_size", 13)
	_visit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_visit.pressed.connect(_visit_unit)
	line.add_child(_visit)


func _fill() -> void:
	var working: bool = bool(data.get("working", false))
	_name.text = String(data.get("role", "Civilian"))
	_chip.text = "AT WORK" if working else "IDLE"
	var chip_color: Color = Palette.GOLD if working else Color(0.66, 0.60, 0.46)
	_chip.add_theme_stylebox_override(
		"normal", UiTheme.box(chip_color, chip_color, 0, 2, Vector4(6, 1, 6, 1))
	)
	_place.text = "%s  ·  %s  ·  tile %d, %d" % [
		String(data.get("province_name", "Open country")),
		String(data.get("region_label", "Uncharted")),
		Vector2i(data.get("tile", Vector2i.ZERO)).x,
		Vector2i(data.get("tile", Vector2i.ZERO)).y,
	]
	if compact:
		_place.text = "%s  ·  %s  ·  %s" % [
			String(data.get("province_name", "Open country")),
			String(data.get("region_label", "Uncharted")),
			String(data.get("short_status", "Idle")),
		]
	_status.text = String(data.get("status_text", ""))
	_progress.visible = working and not compact
	_progress.value = float(data.get("progress", 0.0))
	_visit.tooltip_text = "Open %s on the map" % String(data.get("province_name", "this unit"))


func _visit_unit() -> void:
	visit_pressed.emit(int(data.get("region", 0)), int(data.get("unit_id", -1)))


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_visit_unit()
