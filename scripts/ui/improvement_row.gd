class_name ImprovementRow
extends PanelContainer
## One estate in the management ledger: name, level pips, projected yield,
## blockers in plain text, and the build/cancel/focus actions.
##
## Two geometries: the atlas row keeps its six columns, a phone row folds level
## and yield into the heading and stacks the plain-text detail over the full
## width, so no line is squeezed into a narrow column on a 411-point screen
## (REQ-P1-07). `compact` is set before `setup`.

signal build_pressed(tile: Vector2i)
signal cancel_pressed(tile: Vector2i)
signal focus_pressed(tile: Vector2i)

var data: Dictionary = {}
## Phone rows get thumb-sized actions instead of the atlas 30 px strip.
var compact: bool = false

var _icon: Icon = null
var _name: Label = null
var _status_chip: Label = null
var _subtitle: Label = null
var _detail: Label = null
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
	# A thumb drag that starts on the row must reach the ledger's scroll area,
	# so only the buttons take mouse input; the rest of the row is a drag handle.
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.13, 0.11, 0.08, 0.86),
			Color(0.54, 0.43, 0.12, 0.55),
			1,
			2,
			Vector4(8, 5, 8, 5) if compact else Vector4(10, 8, 10, 8)
		)
	)
	if compact:
		_build_compact()
	else:
		_build_wide()


## Atlas row: icon | name/subtitle | level | yield | state | actions.
func _build_wide() -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(line)

	_icon = Icon.new("tree", 26, Palette.GOLD)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(_icon)

	var info := _info_column(line, 1)
	var heading := _heading(info)
	_name = _label(heading, "", 17, Palette.GOLD_PALE, UiTheme.serif())
	_status_chip = _chip(heading, 10)
	_subtitle = _label(info, "", 11, Color(0.82, 0.76, 0.64))
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var level_box := VBoxContainer.new()
	level_box.custom_minimum_size = Vector2(54, 0)
	level_box.add_theme_constant_override("separation", 2)
	line.add_child(level_box)
	_level = _label(level_box, "", 18, Palette.GOLD)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pips = _pip_row(level_box)

	var output_box := VBoxContainer.new()
	output_box.custom_minimum_size = Vector2(76, 0)
	output_box.add_theme_constant_override("separation", 0)
	line.add_child(output_box)
	_output = _label(output_box, "", 19, Palette.TEXT)
	_output.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commodity = _label(output_box, "", 10, Palette.TEXT_DIM)
	_commodity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var state := VBoxContainer.new()
	state.add_theme_constant_override("separation", 3)
	state.custom_minimum_size = Vector2(250, 0)
	line.add_child(state)
	_status = _label(state, "", 11, Color(0.82, 0.76, 0.64))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cost = _label(state, "", 10, Color(0.80, 0.70, 0.48, 0.9))
	_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason = _label(state, "", 10, Color(0.86, 0.58, 0.36, 0.95))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_actions(line)


## Phone row: icon | name, level, yield and every detail line over the full
## width | thumb actions. No fixed side columns, so the text is not boxed in.
func _build_compact() -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(line)

	_icon = Icon.new("tree", 22, Palette.GOLD)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(_icon)

	var info := _info_column(line, 1)
	var heading := _heading(info, 6)
	_name = _label(heading, "", 15, Palette.GOLD_PALE, UiTheme.serif())
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_status_chip = _chip(heading, 9)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_PASS
	heading.add_child(gap)
	_level = _label(heading, "", 13, Palette.GOLD)
	_pips = _pip_row(heading)
	_output = _label(heading, "", 13, Palette.TEXT)

	_detail = _label(info, "", 10, Color(0.82, 0.76, 0.64))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cost = _label(info, "", 10, Color(0.80, 0.70, 0.48, 0.9))
	_reason = _label(info, "", 10, Color(0.86, 0.58, 0.36, 0.95))
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_actions(line)


func _info_column(line: HBoxContainer, separation: int) -> VBoxContainer:
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", separation)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(info)
	return info


func _heading(info: VBoxContainer, separation: int = 8) -> HBoxContainer:
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", separation)
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(heading)
	return heading


func _pip_row(parent: Control) -> HBoxContainer:
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 2)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(pips)
	return pips


func _actions(line: HBoxContainer) -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.mouse_filter = Control.MOUSE_FILTER_PASS
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


func _label(
	parent: Control, text: String, size: int, color: Color, font: Font = null
) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if font != null:
		label.add_theme_font_override("font", font)
	parent.add_child(label)
	return label


func _chip(parent: Control, size: int) -> Label:
	var chip := Label.new()
	chip.add_theme_font_size_override("font_size", size)
	chip.add_theme_color_override("font_color", Palette.INK)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(chip)
	return chip


func _fill() -> void:
	var tile: Vector2i = data["tile"]
	var level: int = int(data["level"])
	var status: String = String(data["status"])
	var reveal_text: String = "%s · %d, %d · %s" % [
		String(data["province_name"]),
		tile.x,
		tile.y,
		"connected" if bool(data["connected"]) else "not connected",
	]
	var status_text: String = String(data["status_text"])
	_icon.kind = ImprovementCatalog.icon_kind(int(data["resource"]))
	# The pictogram is the commodity (timber green, iron blue-grey, gold, straw);
	# the status chip and pips beside it carry how far the works have come.
	_icon.tint = Palette.resource_ink(_icon.kind)
	_icon.queue_redraw()
	_name.text = String(data["name"])
	_status_chip.text = status.to_upper()
	var chip: Color = _status_color(status)
	_status_chip.add_theme_stylebox_override(
		"normal", UiTheme.box(chip, chip, 0, 2, Vector4(5, 1, 5, 1))
	)
	if _subtitle != null:
		_subtitle.text = reveal_text
	if _detail != null:
		# Phone rows trade the side state column for one full-width line: where
		# the estate is, and what the tile is doing.
		_detail.text = "%s · %s" % [reveal_text, status_text]
	if _status != null:
		_status.text = status_text
	_level.text = "L%d" % level if level > 0 else "—"
	_fill_pips(level)
	if _commodity != null:
		_output.text = str(int(data["output"]))
		_commodity.text = ImprovementCatalog.commodity_label(String(data["commodity"]))
	else:
		_output.text = "%d %s" % [
			int(data["output"]),
			ImprovementCatalog.commodity_label(String(data["commodity"])),
		]
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
	if bool(data.get("tech_limited", false)):
		_build_button.text = "Needs Tech"
	_build_button.disabled = not bool(data["can_build"])
	_build_button.visible = level < int(data["max_level"]) and not working
	_cancel.visible = working


func _fill_pips(level: int) -> void:
	for child: Node in _pips.get_children():
		child.queue_free()
	var size := Vector2(5, 9) if compact else Vector2(6, 11)
	for i in ImprovementCatalog.MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = size
		pip.color = Palette.GOLD if i < level else Color(0.30, 0.25, 0.18, 0.9)
		pip.mouse_filter = Control.MOUSE_FILTER_PASS
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
	button.custom_minimum_size = Vector2(0, 40 if compact else 30)
	button.add_theme_font_size_override("font_size", 12)
	return button


func _tile() -> Vector2i:
	return data.get("tile", Vector2i(-1, -1))
