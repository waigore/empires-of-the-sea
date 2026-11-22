class_name HudPanels
extends RefCounted
## Side dossiers and ledger open/close for GameHud (REQ-P3-01).
## The builders hand each sheet to a HudPanelSlot; this class owns the dock and
## the one-at-a-time rule, so neither the builders nor GameHud repeat them.
##
## Every sheet here is a slot, a `show` line through [HudSheet] and the paint the
## sheet itself reads, so a new dossier or ledger costs a slot and a method, never
## another copy of the reveal law (REQ-P3-01).

var province: HudPanelSlot = null
var fleet: HudPanelSlot = null
var civilian: HudPanelSlot = null
var army: HudPanelSlot = null
var economy: HudPanelSlot = null
var research: HudPanelSlot = null
var diplomacy: HudPanelSlot = null

var host: Control = null
## Built when `bind` finds no dock on the node (a bare HUD in a test).
var dock: PanelDock = null

var panel: ProvincePanel = null
var fleet_panel: FleetPanel = null
var civilian_panel: CivilianPanel = null
var army_panel: ArmyPanel = null
var economy_panel: EconomyPanel = null
var research_panel: ResearchPanel = null
var diplomacy_panel: DiplomacyPanel = null


func bind(hud: GameHud) -> void:
	host = hud
	panel = hud._panel
	fleet_panel = hud._fleet_panel
	civilian_panel = hud._civilian_panel
	army_panel = hud._army_panel
	economy_panel = hud._economy_panel
	research_panel = hud._research_panel
	diplomacy_panel = hud._diplomacy_panel
	if dock == null:
		dock = PanelDock.new()
		dock.load_from()
	_sync_dock_buttons()
	for slot: HudPanelSlot in selections():
		dock.prepare_wrap(slot.wrap)
		# A selection dossier is movable by its own chrome, so the fleet or
		# province it covers can be read without closing it (REQ-P1-07). The
		# dock still owns where it opens; a drag moves it for this opening.
		if slot.panel != null:
			slot.panel.tooltip_text = "Drag to move this dossier"
			var grabs: Array[Control] = [slot.panel]
			ModalDrag.attach(host, slot.wrap, grabs, slot.panel)


func toggle_dock_side() -> void:
	dock.toggle()
	dock.save()
	_sync_dock_buttons()
	# Only the rail rides the dock: a ledger stands on its own door, which the
	# dock cannot slide.
	for slot: HudPanelSlot in selections():
		if slot.open:
			dock.slide_in(host, slot.wrap)
		else:
			dock.prepare_wrap(slot.wrap)


## Closes every sheet but `keep`. Selection callers use it before showing their
## own panel; DiplomacyHud reaches it for the court ledger (REQ-P3-02).
func close_sheets(keep: HudPanelSlot = null) -> void:
	for slot: HudPanelSlot in every():
		if slot != keep:
			slot.conceal(host, dock)


## Every sheet on the dock rail and on a door: the one-at-a-time rule and the
## dock side read this list. A sheet a builder has not mounted yet is left out,
## so a half-built HUD closes and re-docks without a null in the walk.
func every() -> Array[HudPanelSlot]:
	var slots: Array[HudPanelSlot] = []
	# The rail slides in from the chart's edge; the three ledgers take a door.
	for each: HudPanelSlot in selections():
		if each != null:
			slots.append(each)
	for each: HudPanelSlot in [economy, research, diplomacy]:
		if each != null:
			slots.append(each)
	return slots


# --- the province dossier ----------------------------------------------------


func show_province(model: MapModel, province_id: int, crown: Dictionary = {}) -> void:
	close_sheets(province)
	HudSheet.show(dock, host, province, func() -> void:
		panel.refresh(model, province_id, crown)
	)


func hide_province() -> void:
	HudSheet.hide(dock, host, province)


func is_panel_open() -> bool:
	return province.open


# --- the fleet dossier -------------------------------------------------------


## A null fleet with a slip province is the capital yard before any squadron is
## afloat: the first launch founds the home fleet.
func show_fleet(model: MapModel, opening: FleetDossierOpening) -> void:
	close_sheets(fleet)
	HudSheet.show(dock, host, fleet, func() -> void:
		if opening.fleet == null and opening.slip >= 0:
			fleet_panel.refresh_slip(
				model, opening.slip, opening.yard_rows, opening.is_player,
				opening.yard_pick
			)
			return
		fleet_panel.refresh(model, opening)
	)


func hide_fleet() -> void:
	HudSheet.hide(dock, host, fleet)


func is_fleet_panel_open() -> bool:
	return fleet.open


# --- the civilian dossier ----------------------------------------------------


func show_civilian(model: MapModel, opening: CivilianDossierOpening) -> void:
	close_sheets(civilian)
	HudSheet.show(dock, host, civilian, func() -> void:
		civilian_panel.refresh(model, opening)
	)


func hide_civilian() -> void:
	HudSheet.hide(dock, host, civilian)


func is_civilian_panel_open() -> bool:
	return civilian.open


# --- the army dossier --------------------------------------------------------


func show_army(model: MapModel, opening: ArmyDossierOpening) -> void:
	close_sheets(army)
	HudSheet.show(dock, host, army, func() -> void: army_panel.refresh(model, opening))


func hide_army() -> void:
	HudSheet.hide(dock, host, army)


func is_army_panel_open() -> bool:
	return army.open


# --- the economy ledger ------------------------------------------------------

## `pick` is the court's own production plan (`MapPlayProductionPick`), printed
## on the PRODUCTION tab above the rows it answers; `recruits` is the workers'
## plan (`MapPlayRecruitPick`), printed on the WORKERS tab; empty when the
## crown's seat runs no planner (DR-20261121-07, DR-20261122-01).
func show_economy(
	economy_state: PlayerEconomy,
	market: WorldMarket,
	report: Dictionary,
	cargo: Dictionary = {},
	offers: Array = [],
	crown: int = FactionCatalog.PLAYER_FACTION,
	pick: Dictionary = {},
	trade: Dictionary = {},
	recruits: Dictionary = {}
) -> void:
	# The ledger takes the whole edge: close the dossiers outright so their
	# slide-out tween cannot bleed text through the ledger's fade-in. The other
	# ledgers stand on their own doors, so only the rail and the two sibling
	# doors are swept here.
	for slot: HudPanelSlot in selections():
		slot.conceal_now()
	for slot: HudPanelSlot in [research, diplomacy]:
		slot.conceal(host, dock)
	HudSheet.show(dock, host, economy, func() -> void:
		economy_panel.refresh(
			economy_state, market, report, cargo, offers, crown, pick, trade, recruits
		)
	)


func hide_economy() -> void:
	HudSheet.hide(dock, host, economy)


func is_economy_open() -> bool:
	return economy.open


# --- the college ledger ------------------------------------------------------

## The college ledger takes the same edge as the economy ledger. `boost` maps
## tech id -> spy-network percent, so a shadowed rival's advances show why they
## move faster (wiki: civilian-units § Spy; DR-20261110-03). `leader` is the
## crown's leaderKey, whose published funding multiplier the RP figures include
## (wiki: leader-bonuses — Victoria). A ledger already on screen is repainted in
## place without sweeping the rail it already covers (REQ-P1-05). `pick` is the
## study the court would open in its first free slot (DR-20261121-01) and
## `pick_tech` the advance it names, so the AVAILABLE row wears the mark
## (DR-20261122-19).
func show_research(
	state: ResearchState,
	treasury: int,
	boost: Dictionary = {},
	leader: String = "",
	pick: String = "",
	pick_tech: String = ""
) -> void:
	if not research.open:
		close_sheets(research)
	HudSheet.show(dock, host, research, func() -> void:
		research_panel.refresh(state, treasury, boost, leader, pick, pick_tech)
	)


func hide_research() -> void:
	HudSheet.hide(dock, host, research)


func is_research_open() -> bool:
	return research.open


# --- the court ledger --------------------------------------------------------

func is_diplomacy_open() -> bool:
	return diplomacy.open


# --- the dock rail -----------------------------------------------------------


## The docked selection dossiers; ledgers are not on the dock rail.
func selections() -> Array[HudPanelSlot]:
	var slots: Array[HudPanelSlot] = []
	for each: HudPanelSlot in [province, fleet, civilian, army]:
		if each != null:
			slots.append(each)
	return slots


func _sync_dock_buttons() -> void:
	var tip: String = "Dock left" if dock.side == PanelDock.Side.RIGHT else "Dock right"
	var glyph: String = "◀" if dock.side == PanelDock.Side.RIGHT else "▶"
	fleet_panel.set_dock_affordance(glyph, tip)
	panel.set_dock_affordance(glyph, tip)
	civilian_panel.set_dock_affordance(glyph, tip)
	army_panel.set_dock_affordance(glyph, tip)