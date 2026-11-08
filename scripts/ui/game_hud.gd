class_name GameHud
extends Control
## Screen furniture: cartouche bar, treasury chips, minimap, zoom controls,
## end-turn seal and toasts. Side dossiers live on HudPanels (REQ-P3-01).

signal end_turn_pressed
signal zoom_in_pressed
signal zoom_out_pressed
signal minimap_jump(world_position: Vector2)
signal panel_action(action: String)
signal panel_closed
signal fleet_closed
signal civilian_action(action: String)
signal civilian_cancel
signal civilian_closed
signal economy_pressed
signal research_pressed
signal diplomacy_pressed
signal diplomacy_order(kind: String, target: int, arg: String)
signal region_toggle_pressed

const PANEL_WIDTH: float = 360.0
const PANEL_MARGIN: float = 16.0

var panels: HudPanels = null

var _turn_label: Label = null
var _nation_label: Label = null
var _region_button: Button = null
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
var _economy_wrap: Control = null
var _economy_panel: EconomyPanel = null
var _research_wrap: Control = null
var _research_panel: ResearchPanel = null
var _diplomacy_wrap: Control = null
var _diplomacy_panel: DiplomacyPanel = null
var _treasury_value: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	panels = HudPanels.new()
	HudChrome.build(self)
	panels.bind(self)


func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		var mouse: Vector2 = get_global_mouse_position()
		var limit: Vector2 = get_viewport_rect().size - _tooltip.size - Vector2(8, 8)
		_tooltip.position = Vector2(
			clampf(mouse.x + 18.0, 8.0, maxf(limit.x, 8.0)),
			clampf(mouse.y + 18.0, 8.0, maxf(limit.y, 8.0))
		)


func set_turn(turn: int, year: int) -> void:
	_turn_label.text = "Turn %d  ·  %d" % [turn, year]


func set_treasury(value: int, animate: bool = true) -> void:
	var from: int = _treasury_value
	_treasury_value = value
	if not animate:
		_treasury_label.text = HudChrome.format(value)
		return
	var tween := create_tween()
	tween.tween_method(
		func(step: float) -> void:
			_treasury_label.text = HudChrome.format(int(round(step))),
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


func set_minimap(model: MapModel, map_size: Vector2) -> void:
	_minimap.build(model, map_size)


func update_view_rect(rect: Rect2) -> void:
	_minimap.set_view_rect(rect)


func flash_income(amount: int) -> void:
	var label := Label.new()
	label.text = "+%s" % HudChrome.format(amount)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.position = _treasury_chip.get_global_rect().position + Vector2(0, 4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 46.0, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)
