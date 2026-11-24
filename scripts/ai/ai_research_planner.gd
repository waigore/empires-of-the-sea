class_name AiResearchPlanner
extends RefCounted
## Full-AI research policy (wiki: ai-architecture § Research planner,
## research-state, tech-tree). Each rival court fills its own ResearchState
## slots through the shared rules, so the player and every AI read the same
## catalog and the same funding presets (REQ-P2-03, REQ-P3-03).
##
## This home prices and assigns slots; how a candidate scores and ranks lives in
## `AiResearchScores`, and the ration-estate swap in `AiResearchRation`. A study
## already underway follows the purse; a free slot takes the best candidate the
## court can pay for, with the door's study first and the standing study kept
## alive at the cheapest preset. Pure rules: state in, assignments out; the map
## adapter applies them.

## The cheapest preset a court can pay; a court parked at its cash floor keeps
## one study alive at this rate rather than standing still (issue #490).
const STANDING_FUNDING: String = "low"
## The army's mouths' commodities: the ration-estate caps (issue #1059). Kept
## here under the planner's public name; `AiResearchRation` reads it.
const RATION_COMMODITIES: Array[String] = AiResearchRation.RATION_COMMODITIES


## Assignments for the court's empty slots plus every scored candidate, for the
## turn trace (wiki: turn-trace-interpretation).
##
## `context["treasury_floor"]` is the money-goal reserve the surplus ladder must
## leave behind (muster at war, cash floor at peace). `context["cash_floor"]` is
## the court's own `economy.min_treasury` for the standing study: one slot still
## pays the cheapest preset if the purse clears half that floor, so a war-time
## court parked at 500 while saving 2,400 never stops learning (issue #490).
static func plan(
	config: AiConfig, economy: PlayerEconomy, context: Dictionary = {}
) -> Dictionary:
	var assignments: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or economy == null or economy.research == null:
		return {"assignments": assignments, "candidates": candidates}
	var state: ResearchState = economy.research
	state.ensure_slots()
	# The caller's chart tells a court which commodities it has actually seen;
	# discovery techs stay shut until then (wiki: tech-tree § Discovery).
	var revealed: Variant = context.get("revealed", null)
	if typeof(revealed) == TYPE_DICTIONARY:
		state.set_revealed(revealed)
	var purse: Dictionary = _purse(config, economy, context)
	candidates = AiResearchScores.candidates(
		config, economy, bool(purse["at_war"]), String(purse["door"])
	)
	_refund_underway(state, String(purse["preset"]), int(purse["standing"]))
	var taken: Dictionary = {}
	for slot in state.slots.size():
		if not state.tech_at(slot).is_empty():
			continue
		var pick: Dictionary = _pick_for_slot(economy, purse, slot, candidates, taken)
		if not pick.is_empty():
			assignments.append(pick)
	return {"assignments": assignments, "candidates": candidates}


## The purse every slot is priced against this turn: the published preset at
## the court's floor, the cash floor guarding the standing study, and the
## standing slot that keeps it. `at_war`, `door` and `preset` feed the ranking.
## `writes` is false for a reading (the crown's college): the ration-estate step
## below moves a study, and a reading never touches the crown's college
## (DR-20261121-01).
static func _purse(
	config: AiConfig,
	economy: PlayerEconomy,
	context: Dictionary,
	writes: bool = true
) -> Dictionary:
	var state: ResearchState = economy.research
	var save_floor: int = maxi(int(context.get("treasury_floor", 0)), 0)
	# Standing study affordability is always the cash floor, never the muster.
	var cash_floor: int = maxi(int(context.get("cash_floor", research_floor(config))), 0)
	var preset: String = funding_for(config, economy, save_floor)
	# A hull chest that is already in hand is the yard's before the college's
	# (issue #1126): the row is priced whole, so the ladder cannot spend the
	# last payment the slip needs. A court still filling its chest keeps the
	# published single-slot ladder, so the door that opens the hull is never
	# held back by the chest it is saving for.
	var navy_reserve: int = maxi(int(context.get("navy_reserve", 0)), 0)
	if navy_reserve > 0 and economy.treasury >= navy_reserve:
		preset = _row_preset(preset, economy, save_floor)
	# A court that cannot clear the money-goal reserve still keeps one study
	# alive at the cheapest preset when the purse clears half its cash floor:
	# the standing study is the first slot that already holds a tech, or the
	# first slot filled this turn (issue #490). It never spends the last payment
	# of a war chest that is already within reach of its muster (issue #474).
	# A hull chest must actually fill: the standing study's cheapest preset
	# otherwise eats the income that should reach the yard (issue #484). Muster
	# reserves still allow the #490 standing study — only a caller that names
	# the navy chest sets `defer_standing`.
	var can_stand: bool = (
		not bool(context.get("defer_standing", false))
		and preset == ResearchFunding.ORDER[0]
		and _can_pay_standing(economy, cash_floor, save_floor)
	)
	var standing: int = _standing_slot(state) if can_stand else -1
	var door_floor: int = maxi(cash_floor, int(context.get("conquest_reserve", 0)))
	# The standing slot carries the ration ladder (issue #1059): a banked
	# court keeps the ration-estate cap study at the standing preset.
	if writes and standing >= 0 and bool(context.get("conquest_bank", false)):
		AiResearchRation.keep(state, economy, standing)
	return {
		"at_war": bool(context.get("at_war", false)),
		"cash_floor": cash_floor,
		"can_stand": can_stand,
		"door": String(context.get("door", "")),
		"door_floor": door_floor,
		"preset": preset,
		"standing": standing,
	}


## A study already underway follows the purse: a court that cannot fund its
## slots at the published preset pays a cheaper one rather than draining the
## war chest or stalling with unpaid rows.
static func _refund_underway(state: ResearchState, preset: String, standing: int) -> void:
	for slot in state.slots.size():
		if state.tech_at(slot).is_empty():
			continue
		var funding: String = STANDING_FUNDING if slot == standing else preset
		if state.funding_at(slot) != funding:
			state.set_funding(slot, funding)


## The assignment a free slot takes, or an empty row when nothing can be paid.
## `taken` records every candidate walked past this turn.
static func _pick_for_slot(
	economy: PlayerEconomy,
	purse: Dictionary,
	slot: int,
	candidates: Array[Dictionary],
	taken: Dictionary
) -> Dictionary:
	var state: ResearchState = economy.research
	var wants_standing: bool = int(purse["standing"]) < 0 and bool(purse["can_stand"])
	# The walk is one reading ([method _walk_free_slot]); a row the rules refuse
	# at the slot is booked `taken` by the walk itself, so the next pass steps on.
	for _attempt in candidates.size() + 1:
		var pick: Dictionary = _walk_free_slot(economy, purse, slot, candidates, taken)
		if pick.is_empty():
			return {}
		var result: Dictionary = state.assign(
			String(pick["tech"]), String(pick["funding"]), slot
		)
		if not bool(result.get("ok", false)):
			continue
		if wants_standing:
			purse["standing"] = slot
		return pick
	return {}


## The row the walk takes for one empty slot, its funding included, or `{}` when
## every row is spent or barred. One home for the walk's order, its skip of a
## study already in a slot, and the door's own funding gate (issue #484), so the
## crown's college prints what `plan` would open and cannot name a study the
## policy refuses (DR-20261121-01). `taken` is booked here, never assigned.
static func _walk_free_slot(
	economy: PlayerEconomy,
	purse: Dictionary,
	slot: int,
	candidates: Array[Dictionary],
	taken: Dictionary
) -> Dictionary:
	var state: ResearchState = economy.research
	for entry: Dictionary in candidates:
		var tech: String = String(entry.get("tech", ""))
		if taken.has(tech) or state.is_active(tech):
			taken[tech] = true
			continue
		taken[tech] = true
		var funding: String = _funding_of(economy, purse, slot, tech)
		if funding.is_empty():
			continue
		return {
			"tech": tech,
			"slot": slot,
			"funding": funding,
			"score": int(entry.get("score", 0)),
		}
	return {}


## The preset the walk opens one candidate at, or "" when the rules refuse it.
## The door's study is the one row a court may not open unpayable: it pays the
## richest preset above the court's floor, and when even the cheapest would dip
## the court does not open it at all while it saves for its chest (issue #484).
## Every other row opens at the slot's preset, `none` included — an unpaid study
## is still a study the court has taken (wiki: tech-tree § Research model).
static func _funding_of(
	economy: PlayerEconomy, purse: Dictionary, slot: int, tech: String
) -> String:
	var standing: int = int(purse["standing"])
	var can_stand: bool = bool(purse["can_stand"])
	var door: String = String(purse["door"])
	if not door.is_empty() and tech == door:
		var funding: String = _door_funding(economy, int(purse["door_floor"]))
		if funding == ResearchFunding.ORDER[0]:
			if not can_stand:
				return ""
			funding = STANDING_FUNDING
		return funding
	if slot == standing or (standing < 0 and can_stand):
		return STANDING_FUNDING
	return String(purse["preset"])


## The study the published policy would open in the crown's first free slot, on
## this purse, as a reading: `{tech, slot, funding, score}` or `{}`. Nothing is
## assigned, no preset moves and nothing is spent, so the college can print the
## walk's own answer (DR-20261121-01; `MapPlayResearchPick`). `context` is
## `plan`'s own — `at_war`, `door`, `treasury_floor`, `cash_floor` and the rest.
static func read_free_slot(
	config: AiConfig, economy: PlayerEconomy, context: Dictionary = {}
) -> Dictionary:
	if config == null or economy == null or economy.research == null:
		return {}
	var slot: int = economy.research.free_slot()
	if slot < 0:
		return {}
	var purse: Dictionary = _purse(config, economy, context, false)
	var candidates: Array[Dictionary] = AiResearchScores.candidates(
		config, economy, bool(purse["at_war"]), String(purse["door"])
	)
	return _walk_free_slot(economy, purse, slot, candidates, {})


## The preset a court pays each slot: `research.funding_index` shifted by the
## personality's research weight (3 pays one step up, 1 one step down) and by the
## agenda's own catch-up step (wiki: research-state § Funding presets;
## ai-personalities § Domain weight vectors; hidden-agendas — tech_thief pays for
## its catch-up, DR-20261111-27), clamped to the catalogue and then to what the
## purse can carry after `floor` — the reserve the court must not spend (its own
## cash floor; the muster reserve is the army planner's, not research's). A court
## that cannot pay the cheapest preset funds nothing that turn and keeps saving;
## one that can still keeps its standing study alive at that preset (`plan`).
static func funding_for(
	config: AiConfig, economy: PlayerEconomy = null, floor: int = 0
) -> String:
	var shift: int = int(config.weights().get("research", 2)) - 2
	var index: int = clampi(
		config.parameter("research.funding_index") + shift + config.research_bias(),
		0, ResearchFunding.ORDER.size() - 1
	)
	if economy != null:
		var spare: int = economy.treasury - maxi(floor, 0)
		while index > 0 and ResearchFunding.gold(ResearchFunding.ORDER[index]) > spare:
			index -= 1
	return ResearchFunding.ORDER[index]


## Richest preset the purse can spare for a door study after `cash_floor`, or
## `none` when even Low would dip below it; Low itself may dip to half the
## floor (issue #484, same gate as #490).
static func _door_funding(economy: PlayerEconomy, cash_floor: int) -> String:
	var spare: int = economy.treasury - maxi(cash_floor, 0)
	# Prefer richer presets first; Low is the last that still teaches.
	for index in range(ResearchFunding.ORDER.size() - 1, 0, -1):
		var name: String = ResearchFunding.ORDER[index]
		if ResearchFunding.gold(name) <= spare:
			return name
	if _can_pay_standing(economy, cash_floor):
		return STANDING_FUNDING
	return ResearchFunding.ORDER[0]


## The purse research must leave behind: the court's own cash floor, never the
## muster reserve. The reserve is a saving target the army planner enforces at
## muster time; gating studies on it froze every court at war for the whole
## campaign (issue #490).
static func research_floor(config: AiConfig) -> int:
	if config == null:
		return 0
	return maxi(int(config.parameter("economy.min_treasury")), 0)


## The standing study's preset this turn, or "" when the court pays its surplus
## preset instead. Public so the objective ledger prices the same study the
## planner funds (issue #491 T1 reads this planner, it does not spend).
## `save_floor` is the money-goal reserve the court is saving for (the muster at
## war); a negative value keeps the cash floor alone, as at peace.
##
## The helper reads the same purse as `plan`: the standing study exists only
## when the surplus ladder — priced against that same reserve — cannot fund the
## cheapest preset, else the ladder preset pays and no standing slot is priced
## (issue #590: a ledger that priced the study against the cash floor alone
## read a study the planner funds at Low as a 0-gold `funded` row).
static func standing_funding(
	config: AiConfig, economy: PlayerEconomy, save_floor: int = -1
) -> String:
	var floor: int = research_floor(config)
	var reserve: int = save_floor if save_floor >= 0 else floor
	if funding_for(config, economy, reserve) != ResearchFunding.ORDER[0]:
		return ""
	return STANDING_FUNDING if _can_pay_standing(economy, floor, reserve) else ""


## Why the court's slots go unfunded this turn, for the ledger's blocked
## reading (issue #590): "" when a study will actually be paid — the surplus
## ladder above the reserve, or the standing study above half the cash floor —
## otherwise the refusal the trace names, instead of a 0-gold `funded` row.
## Same purse as `plan` and `standing_funding`.
static func standing_refusal(
	config: AiConfig, economy: PlayerEconomy, save_floor: int = -1
) -> String:
	if config == null or economy == null:
		return ""
	var floor: int = research_floor(config)
	var reserve: int = save_floor if save_floor >= 0 else floor
	if funding_for(config, economy, reserve) != ResearchFunding.ORDER[0]:
		return ""
	var price: int = ResearchFunding.gold(STANDING_FUNDING)
	var keep: int = maxi(floor / 2, 0)
	if economy.treasury < keep + price:
		return "purse under half the cash floor"
	# The banked split (issue #1384): the banked college leads from the invest
	# floor — the reserve it hands in is the cash floor's own — so a purse
	# above the floor is the bank's own income investments at work, not a
	# study burning a fill the bank is holding for.
	if reserve > floor and economy.treasury >= reserve - price:
		return "saving for its reserve"
	return ""


## The ladder preset the whole slot row can pay: a preset is charged per slot,
## so one slot's price over the spare is not the purse's answer when three slots
## are underway — the row drops a step until every slot fits (issue #1126). A
## ladder that paid the single-slot preset spent 150 ducats against the 66 the
## hull's chest had left, and the yard never laid the hull it had saved for.
static func _row_preset(
	preset: String, economy: PlayerEconomy, floor: int
) -> String:
	if economy == null:
		return preset
	var slots: int = maxi(
		economy.research.slots.size() if economy.research != null else 1, 1
	)
	var index: int = ResearchFunding.ORDER.find(preset)
	if index < 0:
		return preset
	var spare: int = economy.treasury - maxi(floor, 0)
	while index > 0 and ResearchFunding.gold(ResearchFunding.ORDER[index]) * slots > spare:
		index -= 1
	return ResearchFunding.ORDER[index]


## The slot that keeps the standing study: the first slot already holding a
## tech, or -1 when every slot is free (the first assignment takes it).
static func _standing_slot(state: ResearchState) -> int:
	for slot in state.slots.size():
		if not state.tech_at(slot).is_empty():
			return slot
	return -1


## True when the purse can pay the cheapest preset while still keeping half the
## court's cash floor: the standing study may dip below that floor (the research
## phase's own floor is 0; the cash floor is a saving policy, not a legality
## gate) but never below half of it, so a broke court keeps a reserve. It also
## never spends the last payment of a reserve the court is saving for: a court
## within one study of its muster keeps that payment, because the study would
## otherwise hold the war chest one regiment short of the muster forever
## (wiki: ai-architecture § Land reinforcement; issue #474).
static func _can_pay_standing(
	economy: PlayerEconomy, floor: int, save_floor: int = -1
) -> bool:
	if economy == null:
		return false
	var price: int = ResearchFunding.gold(STANDING_FUNDING)
	var keep: int = maxi(floor / 2, 0)
	if economy.treasury < keep + price:
		return false
	var reserve: int = save_floor if save_floor >= 0 else floor
	if reserve > floor and economy.treasury >= reserve - price:
		return false
	return true
