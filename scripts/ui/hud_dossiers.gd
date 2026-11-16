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
	# The army dossier's command door opens the crown's commanders: the dossier
	# is where a crown asks who leads, and the pool is the whole of it
	# (DR-20261115-11).
	hud._army_panel.command_pressed.connect(func() -> void: hud.command_pressed.emit())
	# The realm ledger's towns door opens the crown's towns: the realm prints
	# each province's level, and the towns sheet is the step that raises it
	# (DR-20261115-12).
	hud.province_ledger.towns_pressed.connect(func() -> void: hud.towns_pressed.emit())
	# Its walls door is the same reach for the province's fort (DR-20261116-01).
	hud.province_ledger.walls_pressed.connect(func() -> void: hud.walls_pressed.emit())
	# And its hospitals door for the province's ward (DR-20261116-02).
	hud.province_ledger.hospitals_pressed.connect(
		func() -> void: hud.hospitals_pressed.emit()
	)


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
			head.realm_pressed.connect(func() -> void: hud.provinces_pressed.emit())
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
## Each mounts on its own layer through HudLedgerDoors; its cartouche or sheet
## door opens it in place (REQ-P5-01, REQ-P5-03, REQ-P5-07).
static func _ledgers(hud: GameHud) -> void:
	hud.civilian_roster = CivilianRosterPanel.new()
	HudLedgerDoors.mount(hud, "CivilianRosterLayer", hud.civilian_roster)
	hud.civilian_roster_pressed.connect(hud.civilian_roster.toggle)
	hud.muster_roll = ForceLedgerPanel.new()
	HudLedgerDoors.mount(hud, "MusterRollLayer", hud.muster_roll)
	hud.muster_roll_pressed.connect(hud.muster_roll.toggle)
	hud.province_ledger = ProvinceLedgerPanel.new()
	HudLedgerDoors.mount(hud, "ProvinceLedgerLayer", hud.province_ledger)
	hud.provinces_pressed.connect(hud.province_ledger.toggle)
	hud.spy_ledger = SpyLedgerPanel.new()
	HudLedgerDoors.mount(hud, "SpyLedgerLayer", hud.spy_ledger)
	hud.spy_ledger_pressed.connect(hud.spy_ledger.toggle)
	# The court ledger carries the door: the crowns a spy shadows are the crowns
	# that ledger lists, so the reading is one press from them (REQ-P5-01).
	hud._diplomacy_panel.eyes_pressed.connect(
		func() -> void: hud.spy_ledger_pressed.emit()
	)
	hud.command_ledger = CommandLedgerPanel.new()
	HudLedgerDoors.mount(hud, "CommandLedgerLayer", hud.command_ledger)
	hud.command_pressed.connect(hud.command_ledger.toggle)
	hud.towns_ledger = TownLedgerPanel.new()
	HudLedgerDoors.mount(hud, "TownLedgerLayer", hud.towns_ledger)
	hud.towns_pressed.connect(hud.towns_ledger.toggle)
	hud.walls_ledger = WallLedgerPanel.new()
	HudLedgerDoors.mount(hud, "WallLedgerLayer", hud.walls_ledger)
	hud.walls_pressed.connect(hud.walls_ledger.toggle)
	hud.hospitals_ledger = HospitalLedgerPanel.new()
	HudLedgerDoors.mount(hud, "HospitalLedgerLayer", hud.hospitals_ledger)
	hud.hospitals_pressed.connect(hud.hospitals_ledger.toggle)
	hud.navy_ledger = NavalLedgerPanel.new()
	HudLedgerDoors.mount(hud, "NavalLedgerLayer", hud.navy_ledger)
	hud.navy_pressed.connect(hud.navy_ledger.toggle)
	hud.army_ledger = ArmyLedgerPanel.new()
	HudLedgerDoors.mount(hud, "ArmyLedgerLayer", hud.army_ledger)
	hud.army_pressed.connect(hud.army_ledger.toggle)
	# The muster roll's doors open the sheets behind it: the roll names each
	# standard by its kind and each squadron by her flagship, and the regiment
	# and hull sheets are the whole of what they fly (REQ-P5-01, REQ-P5-03;
	# DR-20261115-14, DR-20261116-07).
	hud.muster_roll.navy_pressed.connect(func() -> void: hud.navy_pressed.emit())
	hud.muster_roll.army_pressed.connect(func() -> void: hud.army_pressed.emit())
