class_name HudChrome
extends RefCounted
## Builds the map HUD's bars, toasts, minimap, zoom, end-turn seal, and panels.
## GameHud keeps the runtime API; this only assembles the widgets.


static func build(hud: GameHud) -> void:
	_top_bar(hud)
	_toasts(hud)
	_minimap(hud)
	_zoom(hud)
	_end_turn(hud)
	_province_panel(hud)
	_fleet_panel(hud)
	_economy_panel(hud)
	_civilian_panel(hud)
	_tooltip(hud)


static func _top_bar(hud: GameHud) -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 68.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiTheme.box(
		Color(0.09, 0.07, 0.05, 0.95), Palette.GOLD_DIM, 0, 0, Vector4(20, 8, 20, 8)
	)
	style.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", style)
	hud.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

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
	region.custom_minimum_size = Vector2(0, 38)
	region.add_theme_font_size_override("font_size", 12)
	region.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	region.pressed.connect(func() -> void: hud.region_toggle_pressed.emit())
	row.add_child(region)
	hud._region_button = region

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var ledger := Button.new()
	ledger.text = "LEDGER"
	ledger.custom_minimum_size = Vector2(96, 40)
	ledger.add_theme_font_size_override("font_size", 14)
	ledger.pressed.connect(func() -> void: hud.economy_pressed.emit())
	row.add_child(ledger)

	var treasury := _chip("coin", "TREASURY")
	hud._treasury_chip = treasury["root"]
	hud._treasury_label = treasury["value"]
	row.add_child(hud._treasury_chip)

	var prestige := _chip("star", "PRESTIGE")
	hud._prestige_label = prestige["value"]
	row.add_child(prestige["root"])

	var fleets := _chip("ship", "SHIPS")
	hud._fleet_label = fleets["value"]
	row.add_child(fleets["root"])

	var civilians := _chip("compass", "CIVILIANS")
	hud._civilian_label = civilians["value"]
	row.add_child(civilians["root"])


static func _chip(icon_kind: String, caption: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(Icon.new(icon_kind, 22, Palette.GOLD))

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
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", Palette.TEXT)
	column.add_child(value)
	return {"root": row, "value": value}


static func _toasts(hud: GameHud) -> void:
	hud._toast_box = VBoxContainer.new()
	hud._toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hud._toast_box.offset_left = -230.0
	hud._toast_box.offset_right = 230.0
	hud._toast_box.offset_top = 84.0
	hud._toast_box.offset_bottom = 84.0
	hud._toast_box.add_theme_constant_override("separation", 6)
	hud._toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud._toast_box)


static func _minimap(hud: GameHud) -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	frame.offset_left = 18.0
	frame.offset_top = -196.0
	frame.offset_right = 268.0
	frame.offset_bottom = -18.0
	frame.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.92), Palette.GOLD_DIM, 1, 3, Vector4(8, 8, 8, 8))
	)
	hud.add_child(frame)

	hud._minimap = Minimap.new()
	hud._minimap.custom_minimum_size = Vector2(232, 160)
	hud._minimap.jump_requested.connect(func(world_position: Vector2) -> void:
		hud.minimap_jump.emit(world_position)
	)
	frame.add_child(hud._minimap)


static func _zoom(hud: GameHud) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -78.0
	box.offset_top = -212.0
	box.offset_right = -20.0
	box.offset_bottom = -110.0
	box.add_theme_constant_override("separation", 6)
	hud.add_child(box)

	var zoom_in := _square_button("+")
	zoom_in.pressed.connect(func() -> void: hud.zoom_in_pressed.emit())
	box.add_child(zoom_in)

	var zoom_out := _square_button("−")
	zoom_out.pressed.connect(func() -> void: hud.zoom_out_pressed.emit())
	box.add_child(zoom_out)


static func _square_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(58, 46)
	button.add_theme_font_size_override("font_size", 24)
	return button


static func _end_turn(hud: GameHud) -> void:
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wrap.offset_left = -232.0
	wrap.offset_top = -96.0
	wrap.offset_right = -20.0
	wrap.offset_bottom = -20.0
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(wrap)

	hud._glow = Panel.new()
	hud._glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style := UiTheme.box(Color(0, 0, 0, 0), Palette.GOLD, 2, 4, Vector4.ZERO)
	glow_style.shadow_color = Color(0.83, 0.69, 0.22, 0.45)
	glow_style.shadow_size = 12
	hud._glow.add_theme_stylebox_override("panel", glow_style)
	wrap.add_child(hud._glow)

	hud._end_turn_button = Button.new()
	hud._end_turn_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._end_turn_button.offset_left = 4.0
	hud._end_turn_button.offset_top = 4.0
	hud._end_turn_button.offset_right = -4.0
	hud._end_turn_button.offset_bottom = -4.0
	hud._end_turn_button.text = "END TURN"
	hud._end_turn_button.add_theme_font_size_override("font_size", 20)
	hud._end_turn_button.add_theme_color_override("font_color", Palette.INK)
	hud._end_turn_button.add_theme_color_override("font_hover_color", Palette.INK)
	hud._end_turn_button.add_theme_color_override("font_pressed_color", Palette.INK)
	hud._end_turn_button.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.GOLD, Palette.GOLD_PALE, 1, 3, Vector4(10, 6, 10, 6))
	)
	hud._end_turn_button.add_theme_stylebox_override(
		"hover", UiTheme.box(Palette.GOLD_PALE, Color(1, 0.96, 0.85), 1, 3, Vector4(10, 6, 10, 6))
	)
	hud._end_turn_button.add_theme_stylebox_override(
		"pressed", UiTheme.box(Palette.GOLD_DIM, Palette.GOLD, 1, 3, Vector4(10, 6, 10, 6))
	)
	hud._end_turn_button.pressed.connect(func() -> void: hud.end_turn_pressed.emit())
	wrap.add_child(hud._end_turn_button)

	var pulse := hud.create_tween().set_loops()
	pulse.tween_property(hud._glow, "modulate:a", 0.35, 1.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(hud._glow, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)


static func _province_panel(hud: GameHud) -> void:
	hud._panel_wrap = Control.new()
	hud._panel_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hud._panel_wrap.offset_left = -GameHud.PANEL_MARGIN
	hud._panel_wrap.offset_right = GameHud.PANEL_WIDTH - GameHud.PANEL_MARGIN
	hud._panel_wrap.offset_top = 84.0
	hud._panel_wrap.offset_bottom = -104.0
	hud._panel_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._panel_wrap.visible = false
	hud.add_child(hud._panel_wrap)

	hud._panel = ProvincePanel.new()
	hud._panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud._panel.action_pressed.connect(func(action: String) -> void: hud.panel_action.emit(action))
	hud._panel.close_pressed.connect(func() -> void: hud.panel_closed.emit())
	hud._panel_wrap.add_child(hud._panel)


static func _fleet_panel(hud: GameHud) -> void:
	hud._fleet_wrap = Control.new()
	hud._fleet_wrap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud._fleet_wrap.offset_left = -200.0
	hud._fleet_wrap.offset_right = 200.0
	hud._fleet_wrap.offset_top = -178.0
	hud._fleet_wrap.offset_bottom = -22.0
	hud._fleet_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._fleet_wrap.visible = false
	hud.add_child(hud._fleet_wrap)

	hud._fleet_panel = FleetPanel.new()
	hud._fleet_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud._fleet_panel.close_pressed.connect(func() -> void: hud.fleet_closed.emit())
	hud._fleet_wrap.add_child(hud._fleet_panel)


static func _economy_panel(hud: GameHud) -> void:
	hud._economy_wrap = Control.new()
	hud._economy_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hud._economy_wrap.offset_left = -520.0
	hud._economy_wrap.offset_right = -GameHud.PANEL_MARGIN
	hud._economy_wrap.offset_top = 84.0
	hud._economy_wrap.offset_bottom = -104.0
	hud._economy_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	hud._economy_wrap.visible = false
	hud.add_child(hud._economy_wrap)

	hud._economy_panel = EconomyPanel.new()
	hud._economy_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud._economy_panel.close_pressed.connect(func() -> void: hud.panels.hide_economy())
	hud._economy_wrap.add_child(hud._economy_panel)


static func _civilian_panel(hud: GameHud) -> void:
	hud._civilian_wrap = Control.new()
	hud._civilian_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hud._civilian_wrap.offset_left = -GameHud.PANEL_MARGIN
	hud._civilian_wrap.offset_right = GameHud.PANEL_WIDTH - GameHud.PANEL_MARGIN
	hud._civilian_wrap.offset_top = 84.0
	hud._civilian_wrap.offset_bottom = -104.0
	hud._civilian_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._civilian_wrap.visible = false
	hud.add_child(hud._civilian_wrap)

	hud._civilian_panel = CivilianPanel.new()
	hud._civilian_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud._civilian_panel.action_pressed.connect(func(action: String) -> void:
		hud.civilian_action.emit(action)
	)
	hud._civilian_panel.cancel_pressed.connect(func() -> void: hud.civilian_cancel.emit())
	hud._civilian_panel.close_pressed.connect(func() -> void: hud.civilian_closed.emit())
	hud._civilian_wrap.add_child(hud._civilian_panel)


static func _tooltip(hud: GameHud) -> void:
	hud._tooltip = PanelContainer.new()
	var style := UiTheme.box(
		Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 3, Vector4(12, 6, 12, 6)
	)
	style.border_width_left = 3
	style.border_color = Palette.GOLD_DIM
	hud._tooltip.add_theme_stylebox_override("panel", style)
	hud._tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._tooltip.visible = false
	hud.add_child(hud._tooltip)

	hud._tooltip_label = Label.new()
	hud._tooltip_label.add_theme_font_size_override("font_size", 14)
	hud._tooltip_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	hud._tooltip.add_child(hud._tooltip_label)


static func show_tooltip(hud: GameHud, text: String) -> void:
	hud._tooltip_label.text = text
	hud._tooltip.visible = true
	hud._tooltip.reset_size()


static func hide_tooltip(hud: GameHud) -> void:
	hud._tooltip.visible = false


## Cartouche text for the crown in play (the map screen's player faction).
static func set_nation(hud: GameHud, name: String) -> void:
	hud._nation_label.text = name.to_upper()


## Region button caption: "OLD WORLD ›" / "NEW WORLD ›".
static func set_region_label(hud: GameHud, label: String) -> void:
	hud._region_button.text = "%s ›" % label.to_upper()


static func format(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
