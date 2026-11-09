class_name TopBar
extends RefCounted
## Cartouche bar: crest, nation and turn, region/focus, the three ledgers and the
## stat chips. Extracted from HudChrome so that shared file stays under the P3
## size bar; HudLayout re-anchors the parts captured on `hud` (REQ-P3-01).


static func build(hud: GameHud) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = GameHud.BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiTheme.box(
		Color(0.09, 0.07, 0.05, 0.95), Palette.GOLD_DIM, 0, 0, Vector4(20, 8, 20, 8)
	)
	style.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", style)
	hud.add_child(bar)
	hud.top_bar = bar

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	bar.add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	hud.top_row = row

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 18)
	chip_row.alignment = BoxContainer.ALIGNMENT_END
	chip_row.visible = false
	column.add_child(chip_row)
	hud.chip_row = chip_row

	row.add_child(Icon.new("crest", 40, Palette.GOLD))

	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -4)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var nation := Label.new()
	nation.text = "ESPAÑA"
	nation.add_theme_font_size_override("font_size", 20)
	nation.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.add_child(nation)
	hud._nation_label = nation

	hud._turn_label = Label.new()
	hud._turn_label.text = TurnTime.label_for_turn(1)
	hud._turn_label.add_theme_font_size_override("font_size", 13)
	hud._turn_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	title.add_child(hud._turn_label)

	var region := Button.new()
	region.text = "OLD WORLD ›"
	region.custom_minimum_size = Vector2(0, 40)
	region.add_theme_font_size_override("font_size", GameHud.BAR_FONT)
	region.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	region.tooltip_text = "Cycle Old World / New World"
	ChromeIcons.apply(region, "globe", 22)
	region.pressed.connect(func() -> void: hud.region_toggle_pressed.emit())
	row.add_child(region)
	hud._region_button = region

	var focus := Button.new()
	focus.text = "CAPITAL"
	focus.custom_minimum_size = Vector2(0, 42)
	focus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	focus.add_theme_font_size_override("font_size", GameHud.BAR_FONT)
	focus.tooltip_text = "Focus capital (F)"
	ChromeIcons.apply(focus, "capitol", 22)
	focus.pressed.connect(func() -> void: hud.focus_capital_pressed.emit())
	row.add_child(focus)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var ledger := Button.new()
	ledger.text = "LEDGER"
	ledger.custom_minimum_size = Vector2(90, 40)
	ledger.add_theme_font_size_override("font_size", GameHud.BAR_FONT)
	ledger.tooltip_text = "Treasury and production ledger"
	ChromeIcons.apply(ledger, "ledger", 22)
	_mark_icon_only_on_compact(ledger)
	ledger.pressed.connect(func() -> void: hud.economy_pressed.emit())
	row.add_child(ledger)

	var research := Button.new()
	research.text = "RESEARCH"
	research.custom_minimum_size = Vector2(104, 40)
	research.add_theme_font_size_override("font_size", GameHud.BAR_FONT)
	research.tooltip_text = "Scholars and discoveries"
	ChromeIcons.apply(research, "research", 22)
	_mark_icon_only_on_compact(research)
	research.pressed.connect(func() -> void: hud.research_pressed.emit())
	row.add_child(research)

	var court := Button.new()
	court.text = "COURT"
	court.tooltip_text = "Diplomacy"
	court.custom_minimum_size = Vector2(86, 40)
	court.add_theme_font_size_override("font_size", GameHud.BAR_FONT)
	ChromeIcons.apply(court, "crown", 22)
	_mark_icon_only_on_compact(court)
	court.pressed.connect(func() -> void: hud.diplomacy_pressed.emit())
	row.add_child(court)

	var treasury := _chip("coin", "TREASURY")
	hud._treasury_chip = treasury["root"]
	hud._treasury_label = treasury["value"]
	hud.chips.append(hud._treasury_chip)
	row.add_child(hud._treasury_chip)

	var prestige := _chip("star", "PRESTIGE")
	hud._prestige_label = prestige["value"]
	hud.chips.append(prestige["root"])
	row.add_child(prestige["root"])

	var fleets := _chip("ship", "SHIPS")
	hud._fleet_label = fleets["value"]
	hud.chips.append(fleets["root"])
	row.add_child(fleets["root"])

	var civilians := _civilian_chip(hud)
	hud._civilian_label = civilians["value"]
	hud.chips.append(civilians["root"])
	row.add_child(civilians["root"])

	var troops := _chip("crown", "TROOPS")
	hud._army_label = troops["value"]
	hud.chips.append(troops["root"])
	row.add_child(troops["root"])


## Fixed width: the bar's budget must not move as the numbers grow, or the
## stack decision (and every chip after it) shifts under the player's thumb.
static func _chip(icon_kind: String, caption: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(78, 0)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(Icon.new(icon_kind, 20, Palette.GOLD))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -3)
	row.add_child(column)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(cap)

	var value := Label.new()
	value.text = "0"
	value.custom_minimum_size = Vector2(40, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 17)
	value.add_theme_color_override("font_color", Palette.TEXT)
	column.add_child(value)
	return {"root": row, "value": value, "caption": cap}


## The civilian chip is also the roster's front door: the whole chip is a
## button, so the count still reads as a stat while it opens the ledger
## (REQ-P5-01: empire action on the main surface, not buried in a dossier).
static func _civilian_chip(hud: GameHud) -> Dictionary:
	var chip := _chip("compass", "CIVILIANS")
	(chip["caption"] as Label).text = "CREW ›"
	var row: HBoxContainer = chip["root"]
	row.custom_minimum_size = Vector2(68, 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(78, 40)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = "Every civilian in the realm (C)"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void: hud.civilian_roster_pressed.emit())
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4.0
	row.offset_right = -4.0
	button.add_child(row)
	# The wrapper keeps the chip out of the ledger-door button set while the
	# inner button stays the full tap target.
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(78, 40)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(button)
	return {"root": wrap, "value": chip["value"]}


## Marks a secondary ledger door whose caption gives way to its medallion on a
## phone, where the cartouche has no room for six labelled buttons (REQ-P1-05).
static func _mark_icon_only_on_compact(button: Button) -> void:
	button.set_meta("compact_icon_only", true)
	button.set_meta("caption", button.text)
	button.set_meta("min_width", button.custom_minimum_size.x)
