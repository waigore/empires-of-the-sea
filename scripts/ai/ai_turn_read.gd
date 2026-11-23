class_name AiTurnRead
extends RefCounted
## The read model one rival court decides with (wiki: ai-architecture,
## phase-planner-dispatch). Built once per turn by `AiTurn.run` and handed to the
## diplomacy planner, so the turn pass only dispatches while this module reads:
## no rules state is touched here (REQ-P3-03).
##
## `context` is the shared published docket; `reading` is one court's own view of
## it, narrowed to what that court has charted (DR-20261112-09). A caller that
## supplies no readings keeps every court on the published order of battle, which
## is what a headless trace reads.

## Shared read model for the planners: absolute power per faction plus the unit
## counts and player id they need to explain their scores. When the caller
## supplies per-court "readings", each court also gets its own view of the terms
## (see `reading`), so no rival plans against an order of battle it has never
## charted (DR-20261112-09).
##
## `strengths` is the order of battle the published power score reads (FPN + FPM
## × chevrons × health, wiki: diplomacy § Great Power power score); `regiments`
## stays the head count the invasion-capacity rule reads. A caller that supplies
## no strengths keeps the legacy count of the old call sites.
static func context(world: WorldMap, supplied: Dictionary, player: int) -> Dictionary:
	var regiments: Dictionary = supplied.get("regiments", {})
	var ships: Dictionary = supplied.get("ships", {})
	var strengths: Dictionary = supplied.get("strengths", {})
	var shared: Dictionary = {
		"power": powers(world, regiments, ships, strengths),
		"regiments": regiments,
		"ships": ships,
		"player": player,
	}
	if not strengths.is_empty():
		shared["strengths"] = strengths
	var views: Dictionary = court_views(world, supplied.get("readings", {}))
	if not views.is_empty():
		shared["views"] = views
	if supplied.has("charts"):
		shared["charts"] = supplied["charts"]
	if supplied.has("stockpiles"):
		shared["stockpiles"] = supplied["stockpiles"]
	for key: String in [
		"hull_chests", "warships", "victory_press", "conquest_gaps",
		"storm_banks", AiFrontier.KEY
	]:
		if supplied.has(key):
			shared[key] = supplied[key]
	return shared


## The read model one court decides with: its own charted docket when the caller
## supplied readings, else the shared published one, plus the court's own money
## goal so a spender that can wait stands down (issue #580).
static func reading(shared: Dictionary, faction: int, income: Dictionary = {}) -> Dictionary:
	var reading: Dictionary = shared.duplicate()
	reading["income"] = income
	var views: Variant = shared.get("views", null)
	if typeof(views) != TYPE_DICTIONARY:
		return reading
	var view: Variant = (views as Dictionary).get(faction, null)
	if typeof(view) == TYPE_DICTIONARY:
		reading.merge(view, true)
	return reading


## One court's whole decision read: its footing, the money goal its next raise is
## priced against, and its own charted view of the shared docket. `AiTurn` builds
## it for every rival it plans; a surface that reads the crown's own seat builds
## the same read for the crown, so the advice and the pass cannot drift
## (DR-20261121-05). The caller resolves the config — the seed and the bound
## temperament are the caller's, so a reading never plans on the neutral profile.
## The storm chest rides the goal (issue #1381): the caller's `storm_banks` docket
## names the purse the court's thinnest wall prices, and a court with none banks
## its published chest. Pure: the state is read, never written.
static func court(
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	faction: int,
	shared: Dictionary,
	config: AiConfig
) -> Dictionary:
	if config == null:
		return {}
	var phase: Dictionary = AiPhasePlanner.plan(config, state)
	var regiments: int = int(
		(shared.get("regiments", {}) as Dictionary).get(faction, 0)
	)
	var income: Dictionary = AiIncome.plan(
		config, ledger(ai_state, faction), AiIncome.at_war(state, faction),
		regiments,
		int((shared.get("hull_chests", {}) as Dictionary).get(faction, 0)),
		int((shared.get("warships", {}) as Dictionary).get(faction, -1)),
		0,
		bool((shared.get("conquest_gaps", {}) as Dictionary).get(faction, false)),
		# The storm chest the court's thinnest wall prices (issue #1381): the
		# goal the planners stand down against is the host the war must fund.
		int((shared.get("storm_banks", {}) as Dictionary).get(faction, 0))
	)
	var read: Dictionary = reading(shared, faction, income)
	var tech: Dictionary = (shared.get("tech", {}) as Dictionary).get(faction, {})
	if CivilianCatalog.is_unlocked("merchant", tech):
		read["deed_seller"] = AiMerchantWork.deed_seller(
			world, faction, read.get("charts", null), state
		)
	return {"phase": phase, "income": income, "read": read}


## Absolute power per faction from one order of battle, read the published way
## (wiki: diplomacy § Great Power power score). The strength term is the order of
## battle — rounded as the panel and the calendar round it — and a caller that
## supplies none falls back to the head count its context already carries.
static func powers(
	world: WorldMap, regiments: Dictionary, ships: Dictionary, strengths: Dictionary = {}
) -> Dictionary:
	var power: Dictionary = {}
	var by_strength: bool = not strengths.is_empty()
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		var troops: int = (
			int(roundf(float(strengths.get(faction, 0.0))))
			if by_strength
			else int(regiments.get(faction, 0))
		)
		power[faction] = AiPower.score(
			world, faction, troops, int(ships.get(faction, 0))
		)
	return power


## One view per court that supplied a reading. Empty when the caller supplied
## none, which keeps a headless trace on the published order of battle.
static func court_views(world: WorldMap, readings: Variant) -> Dictionary:
	var views: Dictionary = {}
	if typeof(readings) != TYPE_DICTIONARY:
		return views
	var by_court: Dictionary = readings
	for raw: Variant in by_court.keys():
		var entry: Variant = by_court[raw]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var docket: Dictionary = entry
		var regiments: Dictionary = docket.get("regiments", {})
		var ships: Dictionary = docket.get("ships", {})
		var strengths: Dictionary = docket.get("strength", {})
		var view: Dictionary = {
			"power": powers(world, regiments, ships, strengths),
			"regiments": regiments,
			"ships": ships,
		}
		if not strengths.is_empty():
			view["strengths"] = strengths
		views[int(raw)] = view
	return views


## The court's own ledger, or null when the caller kept none: a court with no
## ledger reads no reserve and keeps the published behaviour.
static func ledger(ai_state: AiState, faction: int) -> PlayerEconomy:
	if ai_state == null:
		return null
	return ai_state.economy_for(faction)


## Rival ledgers supply the treasury and tech a peaceful order must satisfy, so
## a court never offers a stage it cannot pay for (wiki: diplomacy
## § Diplomatic Order Types). The human court's fake ledger stays out of the
## read model, matching the stockpile map.
static func stamp_ledgers(shared: Dictionary, ai_state: AiState, player: int) -> void:
	var treasury: Dictionary = {}
	var tech: Dictionary = {}
	if ai_state != null:
		for faction: int in FactionCatalog.great_power_ids():
			if faction == player:
				continue
			var economy: PlayerEconomy = ai_state.economy_for(faction)
			treasury[faction] = economy.treasury
			tech[faction] = economy.tech_unlocked
	shared["treasury"] = treasury
	shared["tech"] = tech
