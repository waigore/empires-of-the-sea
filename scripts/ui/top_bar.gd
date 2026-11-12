class_name TopBar
extends RefCounted
## Cartouche bar: crest, nation and turn, the region seal, four command seals
## and the status plaques. Every element either answers a question the player
## asks every turn or performs an action; the bar carries no vanity counters.
## HudLayout re-anchors the parts captured on `hud` (REQ-P1-02, REQ-P1-05).

const SEAL_SIZE := Vector2(58.0, 44.0)
const REGION_SIZE := Vector2(68.0, 44.0)
const TREASURY_SIZE := Vector2(122.0, 40.0)
const CHIP_SIZE := Vector2(88.0, 40.0)


static func build(hud: GameHud) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = GameHud.BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiTheme.box(
		Color(0.06, 0.05, 0.04, 0.98), Palette.GOLD_DIM, 0, 0, Vector4.ZERO
	)
	style.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", style)
	hud.add_child(bar)
	hud.top_bar = bar

	var ornament := TopBarOrnament.new()
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(ornament)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	column.add_child(row)
	hud.top_row = row

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip_row.alignment = BoxContainer.ALIGNMENT_END
	chip_row.visible = false
	column.add_child(chip_row)
	hud.chip_row = chip_row

	row.add_child(Icon.new("crest", 34, Palette.GOLD))
	row.add_child(_identity(hud))
	row.add_child(_region_seal(hud))

	var command := HBoxContainer.new()
	command.add_theme_constant_override("separation", 3)
	row.add_child(command)
	command.add_child(_seal(
		"capitol", "CAPITAL", "Centre the map on your seat (F)",
		func() -> void: hud.focus_capital_pressed.emit()
	))
	command.add_child(_seal(
		"ledger", "LEDGER", "Treasury, trade and upkeep",
		func() -> void: hud.economy_pressed.emit()
	))
	command.add_child(_seal(
		"research", "RESEARCH", "College slots and funding",
		func() -> void: hud.research_pressed.emit()
	))
	command.add_child(_seal(
		"crown", "COURT", "Diplomacy, alliances and war",
		func() -> void: hud.diplomacy_pressed.emit()
	))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_add_chips(hud, row)


static func _identity(hud: GameHud) -> VBoxContainer:
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -5)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var nation := Label.new()
	nation.text = "ESPAÑA"
	nation.add_theme_font_size_override("font_size", 19)
	nation.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.add_child(nation)
	hud._nation_label = nation

	hud._turn_label = Label.new()
	hud._turn_label.text = TurnTime.label_for_turn(1)
	hud._turn_label.add_theme_font_size_override("font_size", 12)
	hud._turn_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	title.add_child(hud._turn_label)
	return title


## Region stays visible as context, but only offers a switch when a second
## region exists; a one-region world gets a placid label, not a dead button.
static func _region_seal(hud: GameHud) -> Button:
	var button := _seal(
		"globe", "OLD WORLD", "Switch region — Old World / New World",
		func() -> void: hud.region_toggle_pressed.emit(), false
	)
	button.custom_minimum_size = REGION_SIZE
	button.name = "RegionSeal"
	hud._region_button = button
	hud._region_label = button.get_child(0).get_child(1) as Label
	return button


static func _add_chips(hud: GameHud, row: HBoxContainer) -> void:
	var treasury := _chip("TreasuryChip", "coin", "TREASURY", true)
	treasury["root"].pressed.connect(func() -> void: hud.economy_pressed.emit())
	hud.chips.append(treasury["root"])
	row.add_child(treasury["root"])

	var fleets := _chip("FleetChip", "ship", "SHIPS", false)
	fleets["root"].pressed.connect(func() -> void: hud.fleet_status_pressed.emit())
	hud.chips.append(fleets["root"])
	row.add_child(fleets["root"])

	var civilians := _chip("CivilianChip", "people", "CREW ›", false)
	civilians["root"].pressed.connect(func() -> void: hud.civilian_roster_pressed.emit())
	civilians["root"].tooltip_text = "Every civilian in the realm (C)"
	hud.chips.append(civilians["root"])
	row.add_child(civilians["root"])

	var troops := _chip("ArmyChip", "swords", "TROOPS", false)
	troops["root"].pressed.connect(func() -> void: hud.army_status_pressed.emit())
	hud.chips.append(troops["root"])
	row.add_child(troops["root"])

	# The plaque values and their copy belong to HudStatChips, not the bar.
	hud.stats.bind(hud, treasury, fleets, civilians, troops)


## One command seal: pictogram over a one-word caption, so the icon carries the
## glance and the word carries first-time discovery without a wide text button.
static func _seal(
	icon_kind: String, caption: String, tip: String, action: Callable,
	compact_icon_only: bool = true
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SEAL_SIZE
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override(
		"normal", _plaque(Color(0.13, 0.10, 0.07, 0.58), Color(0.54, 0.43, 0.12, 0.55))
	)
	button.add_theme_stylebox_override(
		"hover", _plaque(Color(0.22, 0.17, 0.11, 0.88), Palette.GOLD)
	)
	button.add_theme_stylebox_override(
		"pressed", _plaque(Color(0.09, 0.07, 0.05, 0.95), Palette.GOLD_PALE)
	)
	button.add_theme_stylebox_override(
		"disabled", _plaque(Color(0.13, 0.10, 0.07, 0.58), Color(0.54, 0.43, 0.12, 0.55))
	)
	button.add_theme_stylebox_override(
		"focus", _plaque(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE)
	)
	button.pressed.connect(action)
	if compact_icon_only:
		button.set_meta("compact_icon_only", true)
		button.set_meta("wide_width", SEAL_SIZE.x)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var medallion := TextureRect.new()
	medallion.name = "Medallion"
	medallion.texture = ChromeIcons.texture(icon_kind)
	medallion.custom_minimum_size = Vector2(22, 22)
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medallion.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(medallion)

	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return button


## A status plaque: icon, running value and (for the treasury) the net delta.
## The whole plaque is the target, so the display doubles as a shortcut.
static func _chip(name_text: String, icon_kind: String, caption: String, delta: bool) -> Dictionary:
	var button := Button.new()
	button.name = name_text
	button.custom_minimum_size = TREASURY_SIZE if delta else CHIP_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.set_meta("chip", true)
	button.set_meta("wide_width", TREASURY_SIZE.x if delta else CHIP_SIZE.x)
	button.set_meta("compact_width", 76.0 if delta else 64.0)
	button.set_meta("wide_column", 74.0 if delta else 48.0)
	button.set_meta("compact_column", 36.0 if delta else 24.0)
	button.add_theme_stylebox_override(
		"normal", _plaque(Color(0.16, 0.13, 0.09, 0.70), Color(0.54, 0.43, 0.12, 0.50))
	)
	button.add_theme_stylebox_override(
		"hover", _plaque(Color(0.24, 0.19, 0.12, 0.92), Palette.GOLD)
	)
	button.add_theme_stylebox_override(
		"pressed", _plaque(Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_PALE)
	)
	button.add_theme_stylebox_override(
		"focus", _plaque(Color(0.0, 0.0, 0.0, 0.0), Palette.GOLD_PALE)
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
	return {"root": button, "value": value, "delta": delta_label}


static func _plaque(fill: Color, border: Color) -> StyleBoxFlat:
	var style := UiTheme.box(fill, border, 1, 2, Vector4.ZERO)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0.0, 1.0)
	return style


## Compact cartouche: command doors and status plaques keep their medallions
## (the region keeps its label, because the map's identity is context, not a
## command) and drop their caption words. Values stay visible at every width.
static func apply_compact(hud: GameHud, compact: bool) -> void:
	for node: Node in hud.top_row.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.has_meta("compact_icon_only"):
			continue
		var label := button.find_child("Caption", true, false) as Label
		if label != null:
			label.visible = not compact
		button.custom_minimum_size.x = (
			44.0 if compact else float(button.get_meta("wide_width", SEAL_SIZE.x))
		)
	for chip: Control in hud.chips:
		var cap := chip.find_child("Caption", true, false) as Label
		if cap != null:
			cap.visible = not compact
		chip.custom_minimum_size.x = float(chip.get_meta(
			"compact_width" if compact else "wide_width", chip.custom_minimum_size.x
		))
		var column := chip.find_child("ValueColumn", true, false) as Control
		if column != null:
			column.custom_minimum_size.x = float(chip.get_meta(
				"compact_column" if compact else "wide_column", column.custom_minimum_size.x
			))
