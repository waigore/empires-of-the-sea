class_name HudPanels
extends RefCounted
## Side dossiers and ledger open/close for GameHud (REQ-P3-01).
## Keeps panel animation out of GameHud so the chrome API stays under size bars.

var host: Control = null
var panel_wrap: Control = null
var panel: ProvincePanel = null
var fleet_wrap: Control = null
var fleet_panel: FleetPanel = null
var civilian_wrap: Control = null
var civilian_panel: CivilianPanel = null
var economy_wrap: Control = null
var economy_panel: EconomyPanel = null
var dock: PanelDock = null

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
	dock = PanelDock.new()
	dock.load_from()
	_sync_dock_buttons()
	for wrap: Control in _selection_wraps():
		dock.prepare_wrap(wrap)


func toggle_dock_side() -> void:
	dock.toggle()
	dock.save()
	_sync_dock_buttons()
	for wrap: Control in _selection_wraps():
		if wrap.visible:
			dock.slide_in(host, wrap)
		else:
			dock.prepare_wrap(wrap)


func show_province(model: MapModel, province_id: int) -> void:
	hide_fleet()
	hide_civilian()
	panel.refresh(model, province_id)
	panel_open = true
	dock.slide_in(host, panel_wrap)


func hide_province() -> void:
	if not panel_open:
		return
	panel_open = false
	dock.slide_out(host, panel_wrap, func() -> void: panel_wrap.visible = false)


func is_panel_open() -> bool:
	return panel_open


func show_fleet(model: MapModel, fleet: FleetState, is_player: bool) -> void:
	hide_province()
	hide_civilian()
	hide_economy()
	fleet_panel.refresh(model, fleet, is_player)
	fleet_open = true
	dock.slide_in(host, fleet_wrap)


func hide_fleet() -> void:
	if not fleet_open:
		return
	fleet_open = false
	dock.slide_out(host, fleet_wrap, func() -> void: fleet_wrap.visible = false)


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
	civilian_open = true
	dock.slide_in(host, civilian_wrap)


func hide_civilian() -> void:
	if not civilian_open:
		return
	civilian_open = false
	dock.slide_out(host, civilian_wrap, func() -> void: civilian_wrap.visible = false)


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


func _selection_wraps() -> Array[Control]:
	return [panel_wrap, fleet_wrap, civilian_wrap]


func _sync_dock_buttons() -> void:
	var tip: String = "Dock left" if dock.side == PanelDock.Side.RIGHT else "Dock right"
	var glyph: String = "◀" if dock.side == PanelDock.Side.RIGHT else "▶"
	fleet_panel.set_dock_affordance(glyph, tip)
	panel.set_dock_affordance(glyph, tip)
	civilian_panel.set_dock_affordance(glyph, tip)
