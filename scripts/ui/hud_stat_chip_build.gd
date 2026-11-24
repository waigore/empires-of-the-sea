class_name HudStatChipBuild
extends RefCounted
## One status plaque's tree: icon, running value and (for the treasury) the net
## delta. The parts the compact fit narrows travel back with the widgets, so no
## layout pass reaches into the plaque by node name (REQ-P3-01, REQ-P3-02).

const TREASURY_SIZE := Vector2(122.0, 40.0)
const CHIP_SIZE := Vector2(88.0, 40.0)


## Builds one plaque button and returns the parts the binder and the compact
## fit keep — never a tree search by node name.
static func make(
	name_text: String, icon_kind: String, caption: String, delta: bool
) -> Dictionary:
	var button := Button.new()
	button.name = name_text
	button.custom_minimum_size = TREASURY_SIZE if delta else CHIP_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_stylebox_override(
		"normal", UiTheme.cartouche(Color(0.16, 0.13, 0.09, 0.70), Palette.with_alpha(Palette.GOLD_DIM, 0.50))
	)
	button.add_theme_stylebox_override(
		"hover", UiTheme.cartouche(Color(0.24, 0.19, 0.12, 0.92), Palette.GOLD)
	)
	button.add_theme_stylebox_override(
		"pressed", UiTheme.cartouche(Palette.with_alpha(Palette.PARCHMENT, 0.96), Palette.GOLD_PALE)
	)
	button.add_theme_stylebox_override(
		"focus", UiTheme.cartouche(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE)
	)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_right = -6.0
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var medallion := TextureRect.new()
	medallion.name = "Medallion"
	medallion.texture = ChromeIcons.texture(icon_kind)
	medallion.custom_minimum_size = Vector2(22, 22)
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(medallion)

	var column := VBoxContainer.new()
	column.name = "ValueColumn"
	column.custom_minimum_size = Vector2(74.0 if delta else 48.0, 0.0)
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)

	var cap := Label.new()
	cap.name = "Caption"
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 9)
	cap.add_theme_color_override("font_color", Palette.TEXT_DIM)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(cap)

	var delta_label: Label = null
	if delta:
		var push := Control.new()
		push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		push.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(push)
		delta_label = Label.new()
		delta_label.text = "+0"
		delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		delta_label.add_theme_font_size_override("font_size", 9)
		delta_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
		delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(delta_label)

	var value := Label.new()
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", Palette.TEXT)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(value)
	return {
		"root": button,
		"value": value,
		"delta": delta_label,
		"caption": cap,
		"column": column,
		"wide_width": TREASURY_SIZE.x if delta else CHIP_SIZE.x,
		"compact_width": 76.0 if delta else 64.0,
		"wide_column": 74.0 if delta else 48.0,
		"compact_column": 36.0 if delta else 24.0,
	}
