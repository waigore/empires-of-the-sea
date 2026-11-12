class_name HudPanels
extends RefCounted
## Side dossiers and ledger open/close for GameHud (REQ-P3-01).
## The builders hand each sheet to a HudPanelSlot; this class owns the dock and
## the one-at-a-time rule, so neither the builders nor GameHud repeat them.

var host: Control = null
var dock: PanelDock = null

var province: HudPanelSlot = null
var fleet: HudPanelSlot = null
var civilian: HudPanelSlot = null
var army: HudPanelSlot = null
var economy: HudPanelSlot = null
var research: HudPanelSlot = null
var diplomacy: HudPanelSlot = null

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
	dock = PanelDock.new()
	dock.load_from()
	_sync_dock_buttons()
	for slot: HudPanelSlot in selections():
		dock.prepare_wrap(slot.wrap)


func toggle_dock_side() -> void:
	dock.toggle()
	dock.save()
	_sync_dock_buttons()
	for slot: HudPanelSlot in selections():
		if slot.open:
			dock.slide_in(host, slot.wrap)
		else:
			dock.prepare_wrap(slot.wrap)


## Closes every sheet but `keep`. Selection callers use it before showing their
## own panel; DiplomacyHud reaches it for the court ledger (REQ-P3-02).
func close_sheets(keep: HudPanelSlot = null) -> void:
	var slots: Array = selections()
	slots.append(economy)
	slots.append(research)
	slots.append(diplomacy)
	for slot: HudPanelSlot in slots:
		if slot != keep:
			slot.conceal(host, dock)


func show_province(model: MapModel, province_id: int, crown: Dictionary = {}) -> void:
	close_sheets(province)
	panel.refresh(model, province_id, crown)
	province.reveal(host, dock)


func hide_province() -> void:
	province.conceal(host, dock)


func is_panel_open() -> bool:
	return province.open


func show_fleet(
	model: MapModel,
	fleet: FleetState,
	is_player: bool,
	passage: String = "",
	yard_rows: Array[Dictionary] = [],
	slip: int = -1,
	land_rows: Array[Dictionary] = [],
	carried: int = 0,
	beach_rows: Array[Dictionary] = [],
	beach_note: String = "",
	crew: Dictionary = {},
	strength: Dictionary = {},
	merge: Dictionary = {},
	beach_hint: String = ""
) -> void:
	close_sheets(self.fleet)
	# A null fleet with a slip province is the capital yard before any squadron
	# is afloat: the first launch founds the home fleet.
	if fleet == null and slip >= 0:
		fleet_panel.refresh_slip(model, slip, yard_rows, is_player)
	else:
		fleet_panel.refresh(
			model, fleet, is_player, passage, yard_rows, land_rows, carried,
			beach_rows, beach_note, crew, strength, merge, beach_hint
		)
	self.fleet.reveal(host, dock)


func hide_fleet() -> void:
	fleet.conceal(host, dock)


func is_fleet_panel_open() -> bool:
	return fleet.open


func show_civilian(
	model: MapModel,
	unit: CivilianState,
	works: LandWorks,
	units: Array[CivilianState],
	stockpile: Dictionary,
	visibility: VisibilityModel = null,
	tech_caps: Dictionary = {},
	tech_unlocked: Dictionary = {},
	context: Dictionary = {},
	viewer: int = FactionCatalog.PLAYER_FACTION
) -> void:
	close_sheets(civilian)
	civilian_panel.refresh(
		model, unit, works, units, stockpile, visibility, tech_caps, tech_unlocked,
		context, viewer
	)
	civilian.reveal(host, dock)


func hide_civilian() -> void:
	civilian.conceal(host, dock)


func is_civilian_panel_open() -> bool:
	return civilian.open


func set_civilian_training(visible: bool) -> void:
	panel.set_training_visible(visible)


func show_army(
	model: MapModel,
	army: ArmyState,
	is_player: bool,
	can_merge: bool,
	command: String = "",
	muster: Array[Dictionary] = [],
	embark: String = "",
	plan: String = "balanced",
	hospital: Dictionary = {}
) -> void:
	close_sheets(self.army)
	army_panel.refresh(
		model, army, is_player, can_merge, command, muster, embark, plan, hospital
	)
	self.army.reveal(host, dock)


func hide_army() -> void:
	army.conceal(host, dock)


func is_army_panel_open() -> bool:
	return army.open


func show_economy(
	economy_state: PlayerEconomy,
	market: WorldMarket,
	report: Dictionary,
	cargo: Dictionary = {},
	offers: Array = []
) -> void:
	# The ledger takes the whole edge; close the dossiers outright so their
	# slide-out tween cannot bleed text through the ledger's fade-in.
	for slot: HudPanelSlot in selections():
		slot.conceal_now()
	research.conceal(host, dock)
	diplomacy.conceal(host, dock)
	economy_panel.refresh(economy_state, market, report, cargo, offers)
	economy.reveal(host, dock)


func hide_economy() -> void:
	economy.conceal(host, dock)


func is_economy_open() -> bool:
	return economy.open


## The college ledger takes the same edge as the economy ledger. `boost` maps
## tech id -> spy-network percent, so a shadowed rival's advances show why they
## move faster (wiki: civilian-units § Spy; DR-20261110-03). A ledger already on
## screen is repainted in place — re-revealing it would fade the sheet back in
## and lose the player's place (REQ-P1-05).
func show_research(
	state: ResearchState, treasury: int, boost: Dictionary = {}
) -> void:
	if research.open:
		research_panel.refresh(state, treasury, boost)
		return
	close_sheets(research)
	research_panel.refresh(state, treasury, boost)
	research.reveal(host, dock)


func hide_research() -> void:
	research.conceal(host, dock)


func is_research_open() -> bool:
	return research.open


func is_diplomacy_open() -> bool:
	return diplomacy.open


## The docked selection dossiers; ledgers are not on the dock rail.
func selections() -> Array[HudPanelSlot]:
	return [province, fleet, civilian, army]


func _sync_dock_buttons() -> void:
	var tip: String = "Dock left" if dock.side == PanelDock.Side.RIGHT else "Dock right"
	var glyph: String = "◀" if dock.side == PanelDock.Side.RIGHT else "▶"
	fleet_panel.set_dock_affordance(glyph, tip)
	panel.set_dock_affordance(glyph, tip)
	civilian_panel.set_dock_affordance(glyph, tip)
	army_panel.set_dock_affordance(glyph, tip)
