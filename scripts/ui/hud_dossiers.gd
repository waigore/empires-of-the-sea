class_name HudDossiers
extends RefCounted
## The HUD's side dossiers: a hidden, right-docked wrapper and the panel that
## slides into it, wired to the HUD's own signals (REQ-P3-01).
##
## Every dossier has one shape — wrap, panel, signal bridge — so the wrapper
## geometry and the ordering live here once. The army and diplomacy dossiers
## join the same family through their own builders, in their original cover
## order; HudPanels still owns opening, closing and docking them.


static func build(hud: GameHud) -> void:
	_province(hud)
	_fleet(hud)
	_economy(hud)
	_research(hud)
	DiplomacyHud.build(hud)
	_civilian(hud)
	_roster(hud)
	ArmyHud.build(hud)


## An inert, invisible wrapper anchored to the map's right edge; HudPanels
## slides the dossier in and HudLayout re-anchors it for the viewport.
static func _wrap(
	hud: GameHud,
	left: float,
	right: float,
	filter: Control.MouseFilter = Control.MOUSE_FILTER_IGNORE
) -> Control:
	var wrap := Control.new()
	wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	wrap.offset_left = left
	wrap.offset_right = right
	wrap.offset_top = 84.0
	wrap.offset_bottom = -104.0
	wrap.mouse_filter = filter
	wrap.visible = false
	hud.add_child(wrap)
	return wrap


static func _selection_wrap(hud: GameHud) -> Control:
	return _wrap(hud, -GameHud.PANEL_MARGIN, GameHud.PANEL_WIDTH - GameHud.PANEL_MARGIN)


## The ledger takes the wider field and stops mouse events over it.
static func _ledger_wrap(hud: GameHud) -> Control:
	return _wrap(hud, -520.0, -GameHud.PANEL_MARGIN, Control.MOUSE_FILTER_STOP)


static func _province(hud: GameHud) -> void:
	hud._panel_wrap = _selection_wrap(hud)
	hud._panel = ProvincePanel.new()
	hud._panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._panel.action_pressed.connect(func(action: String) -> void: hud.panel_action.emit(action))
	hud._panel.close_pressed.connect(func() -> void: hud.panel_closed.emit())
	hud._panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud._panel_wrap.add_child(hud._panel)


static func _fleet(hud: GameHud) -> void:
	hud._fleet_wrap = _selection_wrap(hud)
	hud._fleet_panel = FleetPanel.new()
	hud._fleet_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._fleet_panel.close_pressed.connect(func() -> void: hud.fleet_closed.emit())
	hud._fleet_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud._fleet_panel.action_pressed.connect(func(action: String) -> void:
		hud.fleet_action.emit(action)
	)
	hud._fleet_wrap.add_child(hud._fleet_panel)


static func _economy(hud: GameHud) -> void:
	hud._economy_wrap = _ledger_wrap(hud)
	hud._economy_panel = EconomyPanel.new()
	hud._economy_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._economy_panel.close_pressed.connect(func() -> void: hud.panels.hide_economy())
	hud._economy_wrap.add_child(hud._economy_panel)


static func _research(hud: GameHud) -> void:
	hud._research_wrap = _ledger_wrap(hud)
	hud._research_panel = ResearchPanel.new()
	hud._research_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._research_panel.close_pressed.connect(func() -> void: hud.panels.hide_research())
	hud._research_wrap.add_child(hud._research_panel)


static func _civilian(hud: GameHud) -> void:
	hud._civilian_wrap = _selection_wrap(hud)
	hud._civilian_panel = CivilianPanel.new()
	hud._civilian_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._civilian_panel.action_pressed.connect(func(action: String) -> void:
		hud.civilian_action.emit(action)
	)
	hud._civilian_panel.cancel_pressed.connect(func() -> void: hud.civilian_cancel.emit())
	hud._civilian_panel.close_pressed.connect(func() -> void: hud.civilian_closed.emit())
	hud._civilian_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud._civilian_wrap.add_child(hud._civilian_panel)


## Whole-empire civilian roster: its own canvas layer above the pause menu, so
## the ledger is truly modal (the menu trigger cannot bleed through the panel).
static func _roster(hud: GameHud) -> void:
	var layer := CanvasLayer.new()
	layer.name = "CivilianRosterLayer"
	layer.layer = 6
	hud.add_child(layer)
	hud.civilian_roster = CivilianRosterPanel.new()
	layer.add_child(hud.civilian_roster)
	hud.civilian_roster_pressed.connect(hud.civilian_roster.toggle)
