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
signal fleet_action(action: String)
signal fleet_closed
signal civilian_action(action: String)
signal civilian_cancel
signal civilian_closed
signal army_action(action: String)
signal army_closed
signal economy_pressed
signal research_pressed
signal diplomacy_pressed
signal diplomacy_order(kind: String, target: int, arg: String)
## The civilian chip opens the whole-empire roster (REQ-P5-01).
signal civilian_roster_pressed
signal region_toggle_pressed
signal focus_capital_pressed
## The survey lens toggle changed state (button or keyboard).
signal lens_pressed(active: bool)
## The diplomatic lens toggle changed state (button or keyboard).
signal diplomacy_lens_pressed(active: bool)
## Status plaques double as shortcuts to the crown's forces in this region.
signal fleet_status_pressed
signal army_status_pressed
## The player closed the campaign plate to keep viewing the map.
signal victory_dismissed

const PANEL_WIDTH: float = 360.0
const PANEL_MARGIN: float = 16.0
const BAR_HEIGHT: float = 60.0
const BAR_HEIGHT_COMPACT: float = 56.0

var panels: HudPanels = null
## Survey key, shown only while the lens is on.
var lens_legend: LensLegend = null
## Touch platforms: no hover, so hover tooltips stay silent.
var touch_ui: bool = false

var top_bar: Control = null
var top_row: HBoxContainer = null
## Stat chips fall onto a second bar row when the cartouche row cannot fit.
var chip_row: HBoxContainer = null
var chips: Array[Control] = []
var minimap_frame: Control = null
var zoom_box: Control = null
var end_turn_wrap: Control = null
## Campaign-end plate (wiki: victory); null until the chrome builds it.
var victory_overlay: VictoryOverlay = null
## Quick Battle plate (wiki: quick-battle); null until the chrome builds it.
var quick_battle_overlay: QuickBattleOverlay = null
## Whole-empire civilian ledger, built by HudChrome over the map (REQ-P5-01).
var civilian_roster: CivilianRosterPanel = null
## Turns stay shut once the rules decide the campaign (wiki: victory).
var campaign_over: bool = false

var _turn_label: Label = null
var _quick_queue: Array[Dictionary] = []
var _nation_label: Label = null
var _region_button: Button = null
var _region_label: Label = null
var _treasury_label: Label = null
var _income_label: Label = null
var _fleet_label: Label = null
var _civilian_label: Label = null
var _army_label: Label = null
var _treasury_chip: Button = null
var _fleet_chip: Button = null
var _civilian_chip: Button = null
var _army_chip: Button = null
var _toast_box: VBoxContainer = null
var _minimap: Minimap = null
var _panel_wrap: Control = null
var _panel: ProvincePanel = null
var _fleet_wrap: Control = null
var _fleet_panel: FleetPanel = null
var _civilian_wrap: Control = null
var _civilian_panel: CivilianPanel = null
var _army_wrap: Control = null
var _army_panel: ArmyPanel = null
var _tooltip: PanelContainer = null
var _tooltip_label: Label = null
var _end_turn_button: Button = null
## Cartouche toggle for the resource survey lens; HudChrome owns the legend.
var _lens_button: Button = null
## Left-rail toggle for the diplomatic lens, beside the survey seal.
var _diplomacy_lens_button: Button = null
var _glow: Panel = null
var _economy_wrap: Control = null
var _economy_panel: EconomyPanel = null
var _research_wrap: Control = null
var _research_panel: ResearchPanel = null
var _diplomacy_wrap: Control = null
var _diplomacy_panel: DiplomacyPanel = null
var _treasury_value: int = 0
var _income_value: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	touch_ui = PlatformDisplay.is_handheld()
	panels = HudPanels.new()
	HudChrome.build(self)
	panels.bind(self)
	resized.connect(_relayout)
	_relayout()


## Chrome geometry follows the viewport: desktop keeps the atlas layout, a phone
## gets the compact one (HudLayout), and the notch never eats a control.
func _relayout() -> void:
	if panels == null:
		return
	apply_safe_area(PlatformDisplay.safe_insets(get_window()))
	HudLayout.new().apply(self)


func apply_safe_area(insets: Vector4) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = insets.x
	offset_top = insets.y
	offset_right = -insets.z
	offset_bottom = -insets.w


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
	_refresh_treasury_tooltip()
	if not animate:
		_treasury_label.text = HudChrome.format(value)
		return
	var tween := create_tween()
	tween.tween_method(
		func(step: float) -> void:
			_treasury_label.text = HudChrome.format(int(round(step))),
		float(from), float(value), 0.6
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Net treasury movement per turn, shown beside the treasury count so the player
## reads solvency without opening the ledger. Zero is dim, not a fake gain.
func set_income(value: int) -> void:
	_income_value = value
	if _income_label == null:
		return
	_income_label.text = HudChrome.format_delta(value)
	_income_label.add_theme_color_override(
		"font_color",
		Palette.TEXT_DIM if value == 0 else (
			Palette.GOLD_PALE if value > 0 else Palette.CRIMSON.lerp(Color.WHITE, 0.35)
		)
	)
	_refresh_treasury_tooltip()


func _refresh_treasury_tooltip() -> void:
	if _treasury_chip == null:
		return
	_treasury_chip.tooltip_text = "Treasury %s · %s per turn — open the ledger" % [
		HudChrome.format(_treasury_value), HudChrome.format_delta(_income_value)
	]


func set_fleets(value: int) -> void:
	_fleet_label.text = str(value)
	if _fleet_chip != null:
		_fleet_chip.tooltip_text = "Ships — %d · find the next squadron" % value


func set_civilians(value: int) -> void:
	_civilian_label.text = str(value)
	if _civilian_chip != null:
		_civilian_chip.tooltip_text = (
			"Civilians — %d · open the empire roster (C)" % value
		)


func set_armies(value: int) -> void:
	_army_label.text = str(value)
	if _army_chip != null:
		_army_chip.tooltip_text = "Troops — %d regiments · find the next army" % value


## Campaign decided: raise the plate and shut the end-turn seal for good
## (wiki: victory § Victory Screen).
func show_victory(state: VictoryState, player_faction: int, holdings: int) -> void:
	set_campaign_over(true)
	if victory_overlay != null:
		victory_overlay.show_victory(state, player_faction, holdings)


## Calendar cap closed the age undecided: same sealed plate, campaign-complete
## copy instead of a victory (wiki: victory § Calendar campaign end).
func show_campaign_complete(leader: int, turn: int, player_faction: int) -> void:
	set_campaign_over(true)
	if victory_overlay != null:
		victory_overlay.show_campaign_complete(leader, turn, player_faction)


## The human Great Power fell: same sealed plate family, defeat copy
## (wiki: victory § Great Power defeat; DR-20261109-05).
func show_defeat(defeat: DefeatState, player_faction: int) -> void:
	set_campaign_over(true)
	if victory_overlay != null:
		victory_overlay.show_defeat(defeat, player_faction)


## Turns never reopen; only the plate may step aside to keep viewing the map.
func set_campaign_over(over: bool) -> void:
	campaign_over = over
	_end_turn_button.disabled = over
	_end_turn_button.text = "CAMPAIGN ENDED" if over else "END TURN"
	# Longer caption + seal: drop the pictogram so the plate keeps one line.
	_end_turn_button.icon = null if over else ChromeIcons.texture("hourglass")
	_glow.visible = not over
	if not over:
		return
	panels.hide_province()
	panels.hide_fleet()
	panels.hide_civilian()
	panels.hide_army()
	panels.hide_economy()
	panels.hide_research()
	DiplomacyHud.hide(panels)


func is_victory_shown() -> bool:
	return victory_overlay != null and victory_overlay.is_shown()


## The rules resolved one of the human's land battles as Quick Battle. Queue the
## plates so a multi-battle turn replays them one at a time, never stacked.
func show_quick_battle(battle: Dictionary, province: String) -> void:
	if quick_battle_overlay == null:
		return
	if quick_battle_overlay.is_shown():
		_quick_queue.append({"battle": battle, "province": province})
		return
	quick_battle_overlay.show_battle(battle, province, FactionCatalog.names())


func is_quick_battle_shown() -> bool:
	return quick_battle_overlay != null and quick_battle_overlay.is_shown()


## Mirrors a lens state onto its toggle and the shared key cartouche, without
## echoing the button signal (the screen owns the state). Only one lens is ever
## on, so the key shows the key kind that was just raised.
func set_lens(active: bool, kind: String = LensLegend.KIND_SURVEY) -> void:
	var button: Button = (
		_diplomacy_lens_button if kind == LensLegend.KIND_DIPLOMACY else _lens_button
	)
	if button != null and button.button_pressed != active:
		button.set_pressed_no_signal(active)
	if lens_legend == null:
		return
	lens_legend.set_kind(kind)
	lens_legend.visible = (
		(_lens_button != null and _lens_button.button_pressed)
		or (_diplomacy_lens_button != null and _diplomacy_lens_button.button_pressed)
	)


func _on_quick_battle_finished() -> void:
	if _quick_queue.is_empty():
		return
	var next: Dictionary = _quick_queue.pop_front()
	quick_battle_overlay.show_battle(
		next["battle"], String(next["province"]), FactionCatalog.names()
	)


func toast(text: String) -> void:
	# The observer hides the human chrome; building toast plates for a hidden
	# court would only churn nodes every turn (REQ-P4-04).
	if not visible:
		return
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


func set_minimap(
	model: MapModel, map_size: Vector2, visibility: VisibilityModel = null
) -> void:
	_minimap.build(model, map_size, visibility)


## Ownership moved without the chart changing (a conquest, a treaty swap).
func refresh_minimap() -> void:
	_minimap.refresh_ownership()


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
