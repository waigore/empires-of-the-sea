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
	_tech_tree(hud)
	DiplomacyHud.build(hud)
	_civilian(hud)
	_ledgers(hud)
	ArmyHud.build(hud)
	# The two dossiers that carry a door of their own: the army's `Commanders`
	# line (DR-20261115-11) and the court's EYES/COLONIES header
	# (DR-20261115-10, DR-20261117-02). Both name their sheet by door key, so the
	# HUD hears one press. The sheets' own doors bind in HudLedgerDoors.
	hud._army_panel.door_pressed.connect(hud.ledger_door_pressed.emit)
	hud._diplomacy_panel.door_pressed.connect(hud.ledger_door_pressed.emit)


static func _province(hud: GameHud) -> void:
	hud._panel = ProvincePanel.new()
	hud._panel.action_pressed.connect(func(action: String) -> void: hud.panel_action.emit(action))
	hud._panel.close_pressed.connect(func() -> void: hud.panel_closed.emit())
	hud._panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud.panels.province = HudPanelSlot.build(hud, hud._panel, GameHud.PANEL_WIDTH, true)
	hud._panel_wrap = hud.panels.province.wrap
	# The dossier's head owns the realm door (DR-20261115-09); the panel builds
	# the head in its own first frame, so the HUD wires the door after the slot
	# has mounted it.
	for node: Node in hud._panel.find_children("*", "ProvinceSheetHead", true, false):
		var head := node as ProvinceSheetHead
		if head != null:
			head.realm_pressed.connect(
				func() -> void: hud.ledger_door_pressed.emit(HudLedgerDoors.PROVINCES)
			)
			break


static func _fleet(hud: GameHud) -> void:
	hud._fleet_panel = FleetPanel.new()
	hud._fleet_panel.close_pressed.connect(func() -> void: hud.fleet_closed.emit())
	hud._fleet_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud._fleet_panel.action_pressed.connect(func(action: String) -> void:
		hud.fleet_action.emit(action)
	)
	hud.panels.fleet = HudPanelSlot.build(hud, hud._fleet_panel, GameHud.PANEL_WIDTH, true)
	hud._fleet_wrap = hud.panels.fleet.wrap


## The three readings the bar's doors carry — the ledger, the college and the
## court — stand on a ModalDoor: the panel keeps its own masthead and tabs, and
## the door gives it the whole screen, the wash and the pause-door park every
## cartouche door has (REQ-P1-05, REQ-P1-07, REQ-P5-07).
static func _economy(hud: GameHud) -> void:
	hud._economy_panel = EconomyPanel.new()
	hud._economy_panel.close_pressed.connect(func() -> void: hud.panels.hide_economy())
	hud.panels.economy = HudPanelSlot.build_modal(
		ModalDoor.mount(hud, "LedgerDoor"), hud._economy_panel
	)
	hud._economy_wrap = hud.panels.economy.wrap


static func _research(hud: GameHud) -> void:
	hud._research_panel = ResearchPanel.new()
	hud._research_panel.close_pressed.connect(func() -> void: hud.panels.hide_research())
	hud.panels.research = HudPanelSlot.build_modal(
		ModalDoor.mount(hud, "CollegeDoor"), hud._research_panel
	)
	hud._research_wrap = hud.panels.research.wrap


## The college's whole tree, full screen over the ledger: every advance as a
## node on a pannable chart, its prerequisite edges drawn, the aimed advance's
## ancestor road lit, and the goal door on the reading (DR-20261115-15).
static func _tech_tree(hud: GameHud) -> void:
	hud.tech_tree = TechTreePanel.new()
	ModalShell.mount_layer(hud, "TechTreeLayer").add_child(hud.tech_tree)
	hud._research_panel.tree_requested.connect(
		func() -> void: hud.tech_tree.present(hud._research_panel.research_state())
	)
	# The chart's one intent is the college's own goal: steering it writes the
	# state the ledger already keeps, and the chart repaints on the new goal.
	hud.tech_tree.goal_requested.connect(func(tech_id: String) -> void:
		var current: String = hud._research_panel.goal_tech()
		hud._research_panel.set_goal("" if tech_id == current else tech_id)
		hud.tech_tree.refresh()
	)


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


## The crown's whole-empire sheets: the people, the muster roll, the realm's
## provinces, the eyes, the commanders, the towns, walls, hospitals and navy.
## HudLedgerDoors' table mounts every one on its layer and gives each a door key;
## the HUD's one keyed signal opens and closes them in that same order
## (REQ-P3-01, REQ-P5-01, REQ-P5-07).
static func _ledgers(hud: GameHud) -> void:
	HudLedgerDoors.build_all(hud)
