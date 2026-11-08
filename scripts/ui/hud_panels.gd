class_name HudPanels
extends RefCounted
## Side dossiers and ledger open/close for GameHud (REQ-P3-01).
## Keeps panel animation out of GameHud so the chrome API stays under size bars.

const PANEL_WIDTH: float = GameHud.PANEL_WIDTH
const PANEL_MARGIN: float = GameHud.PANEL_MARGIN

var host: Control = null
var panel_wrap: Control = null
var panel: ProvincePanel = null
var fleet_wrap: Control = null
var fleet_panel: FleetPanel = null
var civilian_wrap: Control = null
var civilian_panel: CivilianPanel = null
var economy_wrap: Control = null
var economy_panel: EconomyPanel = null

var panel_open: bool = false
var fleet_open: bool = false
var civilian_open: bool = false
var economy_open: bool = false


func bind(hud: GameHud) -> void:
	host = hud
	panel_wrap = hud._panel_wrap
	panel = hud._panel
	fleet_wrap = hud._fleet_wrap
	fleet_panel = hud._fleet_panel
	civilian_wrap = hud._civilian_wrap
	civilian_panel = hud._civilian_panel
	economy_wrap = hud._economy_wrap
	economy_panel = hud._economy_panel


func show_province(model: MapModel, province_id: int) -> void:
	hide_fleet()
	hide_civilian()
	panel.refresh(model, province_id)
	panel_wrap.visible = true
	panel_open = true
	var tween := host.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel_wrap, "offset_left", -(PANEL_WIDTH + PANEL_MARGIN), 0.34)
	tween.tween_property(panel_wrap, "offset_right", -PANEL_MARGIN, 0.34)


func hide_province() -> void:
	if not panel_open:
		return
	panel_open = false
	var tween := host.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(panel_wrap, "offset_left", -PANEL_MARGIN, 0.26)
	tween.tween_property(panel_wrap, "offset_right", PANEL_WIDTH - PANEL_MARGIN, 0.26)
	tween.chain().tween_callback(func() -> void: panel_wrap.visible = false)


func is_panel_open() -> bool:
	return panel_open


func show_fleet(model: MapModel, fleet: FleetState, is_player: bool) -> void:
	hide_province()
	hide_civilian()
	fleet_panel.refresh(model, fleet, is_player)
	fleet_wrap.visible = true
	fleet_open = true
	var tween := host.create_tween()
	tween.tween_property(fleet_wrap, "modulate:a", 1.0, 0.22).from(0.0)


func hide_fleet() -> void:
	if not fleet_open:
		return
	fleet_open = false
	var tween := host.create_tween()
	tween.tween_property(fleet_wrap, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func() -> void: fleet_wrap.visible = false)


func is_fleet_panel_open() -> bool:
	return fleet_open


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
	civilian_panel.refresh(model, unit, works, units, stockpile, visibility)
	civilian_wrap.visible = true
	civilian_open = true
	civilian_wrap.modulate.a = 0.0
	var tween := host.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(civilian_wrap, "offset_left", -(PANEL_WIDTH + PANEL_MARGIN), 0.34)
	tween.tween_property(civilian_wrap, "offset_right", -PANEL_MARGIN, 0.34)
	tween.tween_property(civilian_wrap, "modulate:a", 1.0, 0.22)


func hide_civilian() -> void:
	if not civilian_open:
		return
	civilian_open = false
	var tween := host.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(civilian_wrap, "offset_left", -PANEL_MARGIN, 0.26)
	tween.tween_property(civilian_wrap, "offset_right", PANEL_WIDTH - PANEL_MARGIN, 0.26)
	tween.tween_property(civilian_wrap, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(func() -> void: civilian_wrap.visible = false)


func is_civilian_panel_open() -> bool:
	return civilian_open


func set_civilian_training(visible: bool) -> void:
	panel.set_training_visible(visible)


func show_economy(economy: PlayerEconomy, market: WorldMarket, report: Dictionary) -> void:
	hide_province()
	hide_fleet()
	hide_civilian()
	economy_panel.refresh(economy, market, report)
	economy_wrap.visible = true
	economy_open = true
	var tween := host.create_tween()
	tween.tween_property(economy_wrap, "modulate:a", 1.0, 0.22).from(0.0)


func hide_economy() -> void:
	if not economy_open:
		return
	economy_open = false
	economy_wrap.visible = false


func is_economy_open() -> bool:
	return economy_open
