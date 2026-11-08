class_name GameHud
extends Control
## Screen furniture: cartouche bar, treasury chips, minimap, zoom controls,
## end-turn seal, province dossier and toasts. Built in code so every widget can
## be animated and asserted from tests.

signal end_turn_pressed
signal zoom_in_pressed
signal zoom_out_pressed
signal minimap_jump(world_position: Vector2)
signal region_toggle_pressed
signal panel_action(action: String)
signal panel_closed
signal fleet_closed
signal civilian_action(action: String)
signal civilian_cancel
signal civilian_closed

const PANEL_WIDTH: float = 360.0
const PANEL_MARGIN: float = 16.0

var _nation_label: Label = null
var _region_button: Button = null
var _turn_label: Label = null
var _treasury_label: Label = null
var _prestige_label: Label = null
var _fleet_label: Label = null
var _civilian_label: Label = null
var _treasury_chip: Control = null
var _toast_box: VBoxContainer = null
var _minimap: Minimap = null
var _panel_wrap: Control = null
var _panel: ProvincePanel = null
var _fleet_wrap: Control = null
var _fleet_panel: FleetPanel = null
var _civilian_wrap: Control = null
var _civilian_panel: CivilianPanel = null
var _tooltip: PanelContainer = null
var _tooltip_label: Label = null
var _end_turn_button: Button = null
var _glow: Panel = null
var _panel_open: bool = false
var _fleet_open: bool = false
var _civilian_open: bool = false
var _treasury_value: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build_top_bar()
	_build_toasts()
	_build_minimap()
	_build_zoom_controls()
	_build_end_turn()
	_build_panel()
	_build_fleet_panel()
	_build_civilian_panel()
	_build_tooltip()


func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		var mouse: Vector2 = get_global_mouse_position()
		var limit: Vector2 = get_viewport_rect().size - _tooltip.size - Vector2(8, 8)
		_tooltip.position = Vector2(
			clampf(mouse.x + 18.0, 8.0, maxf(limit.x, 8.0)),
			clampf(mouse.y + 18.0, 8.0, maxf(limit.y, 8.0))
		)


# --- construction -----------------------------------------------------------


func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 68.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiTheme.box(
		Color(0.09, 0.07, 0.05, 0.95), Palette.GOLD_DIM, 0, 0, Vector4(20, 8, 20, 8)
	)
	style.border_width_bottom = 2
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	row.add_child(Icon.new("crest", 40, Palette.GOLD))

	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -4)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	_nation_label = Label.new()
	_nation_label.text = "ESPAÑA"
	_nation_label.add_theme_font_size_override("font_size", 20)
	_nation_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	title.add_child(_nation_label)

	_turn_label = Label.new()
	_turn_label.text = TurnTime.label_for_turn(1)
	_turn_label.add_theme_font_size_override("font_size", 13)
	_turn_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	title.add_child(_turn_label)

	_region_button = Button.new()
	_region_button.text = "OLD WORLD ›"
	_region_button.custom_minimum_size = Vector2(0, 38)
	_region_button.add_theme_font_size_override("font_size", 12)
	_region_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_region_button.pressed.connect(func() -> void: region_toggle_pressed.emit())
	row.add_child(_region_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var treasury := _make_chip("coin", "TREASURY")
	_treasury_chip = treasury["root"]
	_treasury_label = treasury["value"]
	row.add_child(_treasury_chip)

	var prestige := _make_chip("star", "PRESTIGE")
	_prestige_label = prestige["value"]
	row.add_child(prestige["root"])

	var fleets := _make_chip("ship", "SHIPS")
	_fleet_label = fleets["value"]
	row.add_child(fleets["root"])

	var civilians := _make_chip("compass", "CIVILIANS")
	_civilian_label = civilians["value"]
	row.add_child(civilians["root"])


func _make_chip(icon_kind: String, caption: String) -> Dictionary:
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


func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_box.offset_left = -230.0
	_toast_box.offset_right = 230.0
	_toast_box.offset_top = 84.0
	_toast_box.offset_bottom = 84.0
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)


func _build_minimap() -> void:
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
	add_child(frame)

	_minimap = Minimap.new()
	_minimap.custom_minimum_size = Vector2(232, 160)
	_minimap.jump_requested.connect(func(world_position: Vector2) -> void:
		minimap_jump.emit(world_position)
	)
	frame.add_child(_minimap)


func _build_zoom_controls() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.offset_left = -78.0
	box.offset_top = -212.0
	box.offset_right = -20.0
	box.offset_bottom = -110.0
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var zoom_in := _make_square_button("+")
	zoom_in.pressed.connect(func() -> void: zoom_in_pressed.emit())
	box.add_child(zoom_in)

	var zoom_out := _make_square_button("−")
	zoom_out.pressed.connect(func() -> void: zoom_out_pressed.emit())
	box.add_child(zoom_out)


func _make_square_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(58, 46)
	button.add_theme_font_size_override("font_size", 24)
	return button


func _build_end_turn() -> void:
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	wrap.offset_left = -232.0
	wrap.offset_top = -96.0
	wrap.offset_right = -20.0
	wrap.offset_bottom = -20.0
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	_glow = Panel.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_style := UiTheme.box(Color(0, 0, 0, 0), Palette.GOLD, 2, 4, Vector4.ZERO)
	glow_style.shadow_color = Color(0.83, 0.69, 0.22, 0.45)
	glow_style.shadow_size = 12
	_glow.add_theme_stylebox_override("panel", glow_style)
	wrap.add_child(_glow)

	_end_turn_button = Button.new()
	_end_turn_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_turn_button.offset_left = 4.0
	_end_turn_button.offset_top = 4.0
	_end_turn_button.offset_right = -4.0
	_end_turn_button.offset_bottom = -4.0
	_end_turn_button.text = "END TURN"
	_end_turn_button.add_theme_font_size_override("font_size", 20)
	_end_turn_button.add_theme_color_override("font_color", Palette.INK)
	_end_turn_button.add_theme_color_override("font_hover_color", Palette.INK)
	_end_turn_button.add_theme_color_override("font_pressed_color", Palette.INK)
	_end_turn_button.add_theme_stylebox_override(
		"normal", UiTheme.box(Palette.GOLD, Palette.GOLD_PALE, 1, 3, Vector4(10, 6, 10, 6))
	)
	_end_turn_button.add_theme_stylebox_override(
		"hover", UiTheme.box(Palette.GOLD_PALE, Color(1, 0.96, 0.85), 1, 3, Vector4(10, 6, 10, 6))
	)
	_end_turn_button.add_theme_stylebox_override(
		"pressed", UiTheme.box(Palette.GOLD_DIM, Palette.GOLD, 1, 3, Vector4(10, 6, 10, 6))
	)
	_end_turn_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	wrap.add_child(_end_turn_button)

	var pulse := create_tween().set_loops()
	pulse.tween_property(_glow, "modulate:a", 0.35, 1.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_glow, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)


func _build_panel() -> void:
	_panel_wrap = Control.new()
	_panel_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel_wrap.offset_left = -PANEL_MARGIN
	_panel_wrap.offset_right = PANEL_WIDTH - PANEL_MARGIN
	_panel_wrap.offset_top = 84.0
	_panel_wrap.offset_bottom = -104.0
	_panel_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_wrap.visible = false
	add_child(_panel_wrap)

	_panel = ProvincePanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.action_pressed.connect(func(action: String) -> void: panel_action.emit(action))
	_panel.close_pressed.connect(func() -> void: panel_closed.emit())
	_panel_wrap.add_child(_panel)


func _build_fleet_panel() -> void:
	_fleet_wrap = Control.new()
	_fleet_wrap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_fleet_wrap.offset_left = -200.0
	_fleet_wrap.offset_right = 200.0
	_fleet_wrap.offset_top = -178.0
	_fleet_wrap.offset_bottom = -22.0
	_fleet_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fleet_wrap.visible = false
	add_child(_fleet_wrap)

	_fleet_panel = FleetPanel.new()
	_fleet_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_fleet_panel.close_pressed.connect(func() -> void: fleet_closed.emit())
	_fleet_wrap.add_child(_fleet_panel)


func _build_civilian_panel() -> void:
	_civilian_wrap = Control.new()
	_civilian_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_civilian_wrap.offset_left = -PANEL_MARGIN
	_civilian_wrap.offset_right = PANEL_WIDTH - PANEL_MARGIN
	_civilian_wrap.offset_top = 84.0
	_civilian_wrap.offset_bottom = -104.0
	_civilian_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_civilian_wrap.visible = false
	add_child(_civilian_wrap)

	_civilian_panel = CivilianPanel.new()
	_civilian_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_civilian_panel.action_pressed.connect(func(action: String) -> void:
		civilian_action.emit(action)
	)
	_civilian_panel.cancel_pressed.connect(func() -> void: civilian_cancel.emit())
	_civilian_panel.close_pressed.connect(func() -> void: civilian_closed.emit())
	_civilian_wrap.add_child(_civilian_panel)


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	var style := UiTheme.box(
		Color(0.10, 0.08, 0.06, 0.96), Palette.GOLD_DIM, 1, 3, Vector4(12, 6, 12, 6)
	)
	style.border_width_left = 3
	style.border_color = Palette.GOLD_DIM
	_tooltip.add_theme_stylebox_override("panel", style)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	add_child(_tooltip)

	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	_tooltip_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_tooltip.add_child(_tooltip_label)


# --- public API -------------------------------------------------------------


func set_turn(turn: int, year: int) -> void:
	_turn_label.text = "Turn %d  ·  %d" % [turn, year]


func set_nation(name: String) -> void:
	_nation_label.text = name.to_upper()


## Region button doubles as the Old World / New World switch (touch + mouse).
func set_region_label(label: String) -> void:
	if _region_button == null:
		return
	_region_button.text = "%s ›" % label.to_upper()


func set_treasury(value: int, animate: bool = true) -> void:
	var from: int = _treasury_value
	_treasury_value = value
	if not animate:
		_treasury_label.text = _format(value)
		return
	var tween := create_tween()
	tween.tween_method(
		func(step: float) -> void:
			_treasury_label.text = _format(int(round(step))),
		float(from), float(value), 0.6
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_prestige(value: int) -> void:
	_prestige_label.text = str(value)


func set_fleets(value: int) -> void:
	_fleet_label.text = str(value)


func set_civilians(value: int) -> void:
	_civilian_label.text = str(value)


func toast(text: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.95), Palette.GOLD, 1, 3, Vector4(18, 8, 18, 8))
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	panel.add_child(label)
	panel.modulate.a = 0.0
	_toast_box.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.8)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func show_province(model: MapModel, province_id: int) -> void:
	hide_fleet()
	hide_civilian()
	_panel.refresh(model, province_id)
	_panel_wrap.visible = true
	_panel_open = true
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel_wrap, "offset_left", -(PANEL_WIDTH + PANEL_MARGIN), 0.34)
	tween.tween_property(_panel_wrap, "offset_right", -PANEL_MARGIN, 0.34)


func hide_province() -> void:
	if not _panel_open:
		return
	_panel_open = false
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_panel_wrap, "offset_left", -PANEL_MARGIN, 0.26)
	tween.tween_property(_panel_wrap, "offset_right", PANEL_WIDTH - PANEL_MARGIN, 0.26)
	tween.chain().tween_callback(func() -> void: _panel_wrap.visible = false)


func is_panel_open() -> bool:
	return _panel_open


func show_fleet(model: MapModel, fleet: FleetState, is_player: bool) -> void:
	hide_province()
	hide_civilian()
	_fleet_panel.refresh(model, fleet, is_player)
	_fleet_wrap.visible = true
	_fleet_open = true
	var tween := create_tween()
	tween.tween_property(_fleet_wrap, "modulate:a", 1.0, 0.22).from(0.0)


func hide_fleet() -> void:
	if not _fleet_open:
		return
	_fleet_open = false
	var tween := create_tween()
	tween.tween_property(_fleet_wrap, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func() -> void: _fleet_wrap.visible = false)


func is_fleet_panel_open() -> bool:
	return _fleet_open


## Civilian dossier: shows the posting, tile works and the type's work orders.
func show_civilian(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null
) -> void:
	hide_province()
	hide_fleet()
	_civilian_panel.refresh(model, unit, works, units, stockpile, visibility)
	_civilian_wrap.visible = true
	_civilian_open = true
	_civilian_wrap.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_civilian_wrap, "offset_left", -(PANEL_WIDTH + PANEL_MARGIN), 0.34)
	tween.tween_property(_civilian_wrap, "offset_right", -PANEL_MARGIN, 0.34)
	tween.tween_property(_civilian_wrap, "modulate:a", 1.0, 0.22)


func hide_civilian() -> void:
	if not _civilian_open:
		return
	_civilian_open = false
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_civilian_wrap, "offset_left", -PANEL_MARGIN, 0.26)
	tween.tween_property(_civilian_wrap, "offset_right", PANEL_WIDTH - PANEL_MARGIN, 0.26)
	tween.tween_property(_civilian_wrap, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(func() -> void: _civilian_wrap.visible = false)


func is_civilian_panel_open() -> bool:
	return _civilian_open


## Training orders exist only in the player's capital (wiki: civilian-units
## § Civilian Types and Roles).
func set_civilian_training(visible: bool) -> void:
	_panel.set_training_visible(visible)


func set_minimap(model: MapModel, map_size: Vector2) -> void:
	_minimap.build(model, map_size)


func update_view_rect(rect: Rect2) -> void:
	_minimap.set_view_rect(rect)


func show_tooltip(text: String) -> void:
	_tooltip_label.text = text
	_tooltip.visible = true
	_tooltip.reset_size()


func hide_tooltip() -> void:
	_tooltip.visible = false


func flash_income(amount: int) -> void:
	var label := Label.new()
	label.text = "+%s" % _format(amount)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.position = _treasury_chip.get_global_rect().position + Vector2(0, 4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 46.0, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)


func _format(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
