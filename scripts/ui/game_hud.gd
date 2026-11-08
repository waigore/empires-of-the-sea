class_name GameHud
extends Control
## Screen furniture: cartouche bar, treasury chips, minimap, zoom controls,
## end-turn seal, province dossier and toasts. Built in code so every widget can
## be animated and asserted from tests.

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
signal region_toggle_pressed

const PANEL_WIDTH: float = 360.0
const PANEL_MARGIN: float = 16.0

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
var _panel_open: bool = false
var _fleet_open: bool = false
var _civilian_open: bool = false
var _economy_wrap: Control = null
var _economy_panel: EconomyPanel = null
var _economy_open: bool = false
var _treasury_value: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	HudChrome.build(self)


func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		var mouse: Vector2 = get_global_mouse_position()
		var limit: Vector2 = get_viewport_rect().size - _tooltip.size - Vector2(8, 8)
		_tooltip.position = Vector2(
			clampf(mouse.x + 18.0, 8.0, maxf(limit.x, 8.0)),
			clampf(mouse.y + 18.0, 8.0, maxf(limit.y, 8.0))
		)


# --- public API -------------------------------------------------------------


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


func show_province(model: MapModel, province_id: int) -> void:
	hide_economy()
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
	hide_economy()
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
	hide_economy()
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


func economy_panel() -> EconomyPanel:
	return _economy_panel


func show_economy(economy: PlayerEconomy, market: WorldMarket, report: Dictionary) -> void:
	# The ledger takes the right edge; close the dossiers outright so their
	# slide-out tween cannot bleed text through the ledger's fade-in.
	hide_province()
	hide_fleet()
	hide_civilian()
	_panel_wrap.visible = false
	_panel_open = false
	_fleet_wrap.visible = false
	_fleet_open = false
	_civilian_wrap.visible = false
	_civilian_open = false
	_economy_panel.refresh(economy, market, report)
	_economy_wrap.visible = true
	_economy_open = true
	var tween := create_tween()
	tween.tween_property(_economy_wrap, "modulate:a", 1.0, 0.22).from(0.0)


func hide_economy() -> void:
	if not _economy_open:
		return
	_economy_open = false
	_economy_wrap.visible = false


func is_economy_open() -> bool:
	return _economy_open
