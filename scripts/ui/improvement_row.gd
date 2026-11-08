class_name ImprovementRow
extends PanelContainer
## One estate in the management ledger: name, level pips, projected yield,
## blockers in plain text, and the build/cancel/focus actions.

signal build_pressed(tile: Vector2i)
signal cancel_pressed(tile: Vector2i)
signal focus_pressed(tile: Vector2i)

var data: Dictionary = {}

var _icon: Icon = null
var _name: Label = null
var _status_chip: Label = null
var _subtitle: Label = null
var _level: Label = null
var _pips: HBoxContainer = null
var _output: Label = null
var _commodity: Label = null
var _status: Label = null
var _cost: Label = null
var _reason: Label = null
var _build_button: Button = null
var _cancel: Button = null
var _focus: Button = null


func setup(row: Dictionary) -> void:
	data = row
	_build()
	_fill()


func _build() -> void:
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.13, 0.11, 0.08, 0.86),
			Color(0.54, 0.43, 0.12, 0.55),
			1,
			2,
			Vector4(10, 8, 10, 8)
		)
	)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	add_child(line)

	_icon = Icon.new("tree", 26, Palette.GOLD)
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
	_name.add_theme_font_size_override("font_size", 17)
	_name.add_theme_color_override("font_color", Palette.GOLD_PALE)
	heading.add_child(_name)

	_status_chip = Label.new()
	_status_chip.add_theme_font_size_override("font_size", 10)
	_status_chip.add_theme_color_override("font_color", Palette.INK)
	heading.add_child(_status_chip)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_subtitle)

	var level_box := VBoxContainer.new()
	level_box.custom_minimum_size = Vector2(54, 0)
	level_box.add_theme_constant_override("separation", 2)
	line.add_child(level_box)

	_level = Label.new()
	_level.add_theme_font_size_override("font_size", 18)
	_level.add_theme_color_override("font_color", Palette.GOLD)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_box.add_child(_level)

	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 2)
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	level_box.add_child(_pips)

	var output_box := VBoxContainer.new()
	output_box.custom_minimum_size = Vector2(76, 0)
	output_box.add_theme_constant_override("separation", 0)
	line.add_child(output_box)

	_output = Label.new()
	_output.add_theme_font_size_override("font_size", 19)
	_output.add_theme_color_override("font_color", Palette.TEXT)
	_output.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_box.add_child(_output)

	_commodity = Label.new()
	_commodity.add_theme_font_size_override("font_size", 10)
	_commodity.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_commodity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	output_box.add_child(_commodity)

	var state := VBoxContainer.new()
	state.add_theme_constant_override("separation", 3)
	state.custom_minimum_size = Vector2(250, 0)
	line.add_child(state)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.82, 0.76, 0.64))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_child(_status)

	_cost = Label.new()
	_cost.add_theme_font_size_override("font_size", 10)
	_cost.add_theme_color_override("font_color", Color(0.80, 0.70, 0.48, 0.9))
	_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_child(_cost)

	_reason = Label.new()
	_reason.add_theme_font_size_override("font_size", 10)
	_reason.add_theme_color_override("font_color", Color(0.86, 0.58, 0.36, 0.95))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.add_child(_reason)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	line.add_child(actions)

	_build_button = _button("Build")
	_build_button.pressed.connect(func() -> void: build_pressed.emit(_tile()))
	actions.add_child(_build_button)

	_cancel = _button("Cancel")
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit(_tile()))
	actions.add_child(_cancel)

	_focus = _button("Map")
	_focus.pressed.connect(func() -> void: focus_pressed.emit(_tile()))
	actions.add_child(_focus)


func _fill() -> void:
	var tile: Vector2i = data["tile"]
	var level: int = int(data["level"])
	var status: String = String(data["status"])
	_icon.kind = ImprovementCatalog.icon_kind(int(data["resource"]))
	_icon.tint = _status_color(status)
	_icon.queue_redraw()
	_name.text = String(data["name"])
	_status_chip.text = status.to_upper()
	var chip: Color = _status_color(status)
	_status_chip.add_theme_stylebox_override(
		"normal", UiTheme.box(chip, chip, 0, 2, Vector4(5, 1, 5, 1))
	)
	_subtitle.text = "%s · %d, %d · %s" % [
		String(data["province_name"]),
		tile.x,
		tile.y,
		"connected" if bool(data["connected"]) else "not connected",
	]
	_level.text = "L%d" % level if level > 0 else "—"
	_fill_pips(level)
	_output.text = str(int(data["output"]))
	_commodity.text = ImprovementCatalog.commodity_label(String(data["commodity"]))
	_status.text = String(data["status_text"])
	_cost.text = ""
	if level < int(data["max_level"]):
		_cost.text = "Cost %s · %d turn%s" % [
			String(data["cost_text"]),
			int(data["duration"]),
			"" if int(data["duration"]) == 1 else "s",
		]
	_reason.text = String(data["build_reason"])
	var working: bool = bool(data["working"])
	_cost.visible = level < int(data["max_level"]) and not working
	_reason.visible = not bool(data["can_build"]) and level < int(data["max_level"]) and not working
	_build_button.text = "Build L1" if level <= 0 else "Raise L%d" % int(data["next_level"])
	if int(data["builder_id"]) < 0:
		_build_button.text = "No Builder"
	_build_button.disabled = not bool(data["can_build"])
	_build_button.visible = level < int(data["max_level"]) and not working
	_cancel.visible = working


func _fill_pips(level: int) -> void:
	for child: Node in _pips.get_children():
		child.queue_free()
	for i in ImprovementCatalog.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 11)
		pip.color = Palette.GOLD if i < level else Color(0.30, 0.25, 0.18, 0.9)
		_pips.add_child(pip)


func _status_color(status: String) -> Color:
	match status:
		"building":
			return Palette.GOLD_PALE
		"producing":
			return Palette.GOLD
		"disconnected":
			return Color(0.76, 0.42, 0.30)
		"unprospected":
			return Color(0.74, 0.60, 0.34)
		"vacant":
			return Palette.TEXT_DIM
	return Palette.MOSS


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_size_override("font_size", 12)
	return button


func _tile() -> Vector2i:
	return data.get("tile", Vector2i(-1, -1))
