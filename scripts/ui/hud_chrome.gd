class_name HudChrome
extends RefCounted
## Builds the map HUD's bars, toasts, minimap, zoom, end-turn seal and plates.
## GameHud keeps the runtime API; this only assembles the widgets. The side
## dossiers are HudDossiers' job, the despatch plates HudDespatches' (REQ-P3-01).


static func build(hud: GameHud) -> void:
	TopBar.build(hud)
	_minimap(hud)
	_zoom(hud)
	_lens_key(hud)
	_despatches(hud)
	_end_turn(hud)
	HudDossiers.build(hud)
	_tooltip(hud)
	_victory_plate(hud)
	_quick_battle_plate(hud)
	_gazette_plate(hud)


## The despatch lane owns its toast column, queue and geometry (HudDespatches);
## the chrome only mounts it under the cartouche.
static func _despatches(hud: GameHud) -> void:
	hud.despatches = HudDespatches.new()
	hud.add_child(hud.despatches)


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
	hud.minimap_frame = frame

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
	hud.zoom_box = box

	var zoom_in := _square_button("zoom_in", "Zoom in")
	zoom_in.pressed.connect(func() -> void: hud.zoom_in_pressed.emit())
	box.add_child(zoom_in)

	var zoom_out := _square_button("zoom_out", "Zoom out")
	zoom_out.pressed.connect(func() -> void: hud.zoom_out_pressed.emit())
	box.add_child(zoom_out)


## Icon-only seal: the magnifier reads at a glance, the tooltip keeps it named.
static func _square_button(icon_name: String, caption: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(58, 46)
	button.tooltip_text = caption
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ChromeIcons.apply(button, icon_name, 30)
	return button


## The four map lenses share the bar's one seal; the key cartouche is mounted
## here, hidden until a reading is raised (REQ-P5-03).
static func _lens_key(hud: GameHud) -> void:
	hud.lens_legend = LensLegend.new()
	hud.lens_legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.lens_legend.offset_left = 18.0
	hud.lens_legend.offset_top = 186.0
	hud.lens_legend.offset_right = 18.0 + LensLegend.WIDTH
	hud.lens_legend.offset_bottom = 186.0 + LensLegend.HEIGHT
	hud.lens_legend.visible = false
	hud.add_child(hud.lens_legend)


static func _end_turn(hud: GameHud) -> void:
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wrap.offset_left = -232.0
	wrap.offset_top = -96.0
	wrap.offset_right = -20.0
	wrap.offset_bottom = -20.0
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(wrap)
	hud.end_turn_wrap = wrap

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
	ChromeIcons.apply(hud._end_turn_button, "hourglass", 24)
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


## Campaign-end plate: built last so it covers every dossier (wiki: victory).
static func _victory_plate(hud: GameHud) -> void:
	hud.victory_overlay = VictoryOverlay.new()
	hud.victory_overlay.z_index = 40
	hud.victory_overlay.dismissed.connect(func() -> void: hud.victory_dismissed.emit())
	hud.add_child(hud.victory_overlay)


## Quick Battle plate: above the dossiers, below the campaign-end plate. The HUD
## replays the queued battles and releases the court's held news (REQ-P5-06).
static func _quick_battle_plate(hud: GameHud) -> void:
	hud.quick_battle_overlay = QuickBattleOverlay.new()
	hud.quick_battle_overlay.z_index = 35
	hud.quick_battle_overlay.finished.connect(
		func() -> void: hud._on_quick_battle_finished()
	)
	hud.add_child(hud.quick_battle_overlay)


## The crown's news sheet: over the dossiers, under the Quick Battle and
## campaign-end plates, and soft — it never takes the whole screen.
static func _gazette_plate(hud: GameHud) -> void:
	hud.gazette_plate = GazettePlate.new()
	hud.gazette_plate.z_index = 30
	# The sheet pushes the despatch lane below its masthead while it is up.
	hud.gazette_plate.despatches = hud.despatches
	hud.add_child(hud.gazette_plate)
	# A cartouche seal reopens the news, beside the estates door on the rail.
	var seal := _square_button("gazette", "The Gazette — this turn's news and the archive")
	seal.position = Vector2(186.0, 132.0)
	seal.pressed.connect(func() -> void: hud.gazette_pressed.emit())
	hud.add_child(seal)


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
	if hud.touch_ui:
		return
	hud._tooltip_label.text = text
	hud._tooltip.visible = true
	hud._tooltip.reset_size()


static func hide_tooltip(hud: GameHud) -> void:
	hud._tooltip.visible = false


## Cartouche text for the crown in play (the map screen's player faction).
static func set_nation(hud: GameHud, name: String) -> void:
	hud._nation_label.text = name.to_upper()


## Region button caption: "OLD WORLD" / "NEW WORLD". A map with one region is
## context, not a choice, so the seal goes inert instead of offering a no-op.
static func set_region_label(hud: GameHud, label: String, switchable: bool = true) -> void:
	if hud._region_label != null:
		hud._region_label.text = label.to_upper()
	if hud._region_button == null:
		return
	hud._region_button.disabled = not switchable
	hud._region_button.focus_mode = (
		Control.FOCUS_ALL if switchable else Control.FOCUS_NONE
	)
	hud._region_button.tooltip_text = (
		"Switch region — %s" % label if switchable else "%s — only charted region" % label
	)
