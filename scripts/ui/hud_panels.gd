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


## Re-anchors every dossier for the viewport: a phone gets a full-height side
## sheet (the end-turn seal waits behind it, as with any modal), the atlas
## layout keeps its gap above the seal; the ledger takes the whole edge.
func apply_compact(compact: bool, view: Vector2) -> void:
	var width: float = GameHud.PANEL_WIDTH
	if compact:
		width = clampf(view.x * 0.4, 280.0, GameHud.PANEL_WIDTH)
	dock.configure(
		width,
		64.0 if compact else PanelDock.TOP,
		-10.0 if compact else PanelDock.BOTTOM
	)
	dock.relayout(panel_wrap, panel_open)
	dock.relayout(fleet_wrap, fleet_open)
	dock.relayout(civilian_wrap, civilian_open)
	economy_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	economy_wrap.offset_left = -minf(view.x - 20.0, 560.0) if compact else -520.0
	economy_wrap.offset_right = -10.0 if compact else -GameHud.PANEL_MARGIN
	economy_wrap.offset_top = 64.0 if compact else 84.0
	economy_wrap.offset_bottom = -10.0 if compact else -104.0


func show_province(model: MapModel, province_id: int) -> void:
	hide_economy()
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
	# The ledger takes the whole edge; close the dossiers outright so their
	# slide-out tween cannot bleed text through the ledger's fade-in.
	hide_province()
	hide_fleet()
	hide_civilian()
	panel_wrap.visible = false
	panel_open = false
	fleet_wrap.visible = false
	fleet_open = false
	civilian_wrap.visible = false
	civilian_open = false
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
