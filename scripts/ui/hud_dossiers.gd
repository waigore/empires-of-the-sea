class_name HudDossiers
extends RefCounted
## Builds the HUD's side dossiers and ledgers on their shared slots: province,
## fleet, economy, research, civilian and the whole-empire roster. GameHud keeps
## the runtime API; HudPanels opens and closes what this assembles (REQ-P3-01).


static func build(hud: GameHud) -> void:
	_province(hud)
	_fleet(hud)
	_economy(hud)
	_research(hud)
	DiplomacyHud.build(hud)
	_civilian(hud)
	_roster(hud)
	ArmyHud.build(hud)


static func _province(hud: GameHud) -> void:
	hud._panel = ProvincePanel.new()
	hud._panel.action_pressed.connect(func(action: String) -> void: hud.panel_action.emit(action))
	hud._panel.close_pressed.connect(func() -> void: hud.panel_closed.emit())
	hud._panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud.panels.province = HudPanelSlot.build(hud, hud._panel, GameHud.PANEL_WIDTH, true)
	hud._panel_wrap = hud.panels.province.wrap


static func _fleet(hud: GameHud) -> void:
	hud._fleet_panel = FleetPanel.new()
	hud._fleet_panel.close_pressed.connect(func() -> void: hud.fleet_closed.emit())
	hud._fleet_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud._fleet_panel.action_pressed.connect(func(action: String) -> void:
		hud.fleet_action.emit(action)
	)
	hud.panels.fleet = HudPanelSlot.build(hud, hud._fleet_panel, GameHud.PANEL_WIDTH, true)
	hud._fleet_wrap = hud.panels.fleet.wrap


static func _economy(hud: GameHud) -> void:
	hud._economy_panel = EconomyPanel.new()
	hud._economy_panel.close_pressed.connect(func() -> void: hud.panels.hide_economy())
	hud.panels.economy = HudPanelSlot.build(
		hud, hud._economy_panel, HudPanelSlot.LEDGER_WIDTH, false
	)
	hud._economy_wrap = hud.panels.economy.wrap


static func _research(hud: GameHud) -> void:
	hud._research_panel = ResearchPanel.new()
	hud._research_panel.close_pressed.connect(func() -> void: hud.panels.hide_research())
	hud.panels.research = HudPanelSlot.build(
		hud, hud._research_panel, HudPanelSlot.LEDGER_WIDTH, false
	)
	hud._research_wrap = hud.panels.research.wrap


static func _civilian(hud: GameHud) -> void:
	hud._civilian_panel = CivilianPanel.new()
	hud._civilian_panel.action_pressed.connect(func(action: String) -> void:
		hud.civilian_action.emit(action)
	)
	hud._civilian_panel.cancel_pressed.connect(func() -> void: hud.civilian_cancel.emit())
	hud._civilian_panel.close_pressed.connect(func() -> void: hud.civilian_closed.emit())
	hud._civilian_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud.panels.civilian = HudPanelSlot.build(
		hud, hud._civilian_panel, GameHud.PANEL_WIDTH, true
	)
	hud._civilian_wrap = hud.panels.civilian.wrap


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
