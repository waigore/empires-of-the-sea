class_name AiResearchPlanner
extends RefCounted
## Full-AI research policy (wiki: ai-architecture § Research planner,
## research-state, tech-tree). Each rival court fills its own ResearchState
## slots through the shared rules, so the player and every AI read the same
## catalog and the same funding presets (REQ-P2-03, REQ-P3-03).
##
## How a candidate scores and ranks lives in `AiResearchScores`, the
## ration-estate swap in `AiResearchRation`, the purse every slot is priced
## against in `AiResearchPurse`, and the walk a free slot takes in
## `AiResearchPlan`. A study already underway follows the purse; a free slot
## takes the best candidate the court can pay for, with the door's study first
## and the standing study kept alive at the cheapest preset. Pure rules: state
## in, assignments out; the map adapter applies them.

## The cheapest preset a court can pay; a court parked at its cash floor keeps
## one study alive at this rate rather than standing still (issue #490).
const STANDING_FUNDING: String = AiResearchPurse.STANDING_FUNDING
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
	var purse: Dictionary = AiResearchPurse.read(config, economy, context)
	candidates = AiResearchScores.candidates(
		config, economy, bool(purse["at_war"]), String(purse["door"])
	)
	_refund_underway(state, String(purse["preset"]), int(purse["standing"]))
	assignments = book(economy, purse, candidates)
	return {"assignments": assignments, "candidates": candidates}


## Books every empty slot from the priced purse: one walk per slot, so the row a
## slot could not take steps on to the next, and the first paid slot of a
## still-free book becomes the standing one. The plan and the crown's college
## reading both walk here, so neither can name a study the other refuses.
static func book(
	economy: PlayerEconomy, purse: Dictionary, candidates: Array[Dictionary]
) -> Array[Dictionary]:
	var assignments: Array[Dictionary] = []
	var state: ResearchState = economy.research
	var taken: Dictionary = {}
	var standing: int = int(purse["standing"])
	var can_stand: bool = bool(purse["can_stand"])
	for slot in state.slots.size():
		if not state.tech_at(slot).is_empty():
			continue
		if standing < 0 and can_stand and AiResearchPlan.book_slot(slot, standing, can_stand):
			purse["standing"] = slot
			standing = slot
		var pick: Dictionary = _walk_slot(economy, purse, slot, candidates, taken)
		if not pick.is_empty():
			assignments.append(pick)
	return assignments


## The walk one empty slot takes, retried past a row the rules refuse at the
## slot (the walk itself books it `taken`, so the next pass steps on).
static func _walk_slot(
	economy: PlayerEconomy,
	purse: Dictionary,
	slot: int,
	candidates: Array[Dictionary],
	taken: Dictionary
) -> Dictionary:
	var state: ResearchState = economy.research
	for _attempt in candidates.size() + 1:
		var pick: Dictionary = AiResearchPlan.walk(economy, purse, slot, candidates, taken)
		if pick.is_empty():
			return {}
		if bool(state.assign(String(pick["tech"]), String(pick["funding"]), slot).get("ok", false)):
			return pick
	return {}


## A study already underway follows the purse: a court that cannot fund its
## slots at the published preset pays a cheaper one rather than draining the
## war chest or stalling with unpaid rows.
static func _refund_underway(
	state: ResearchState, preset: String, standing: int
) -> void:
	for slot in state.slots.size():
		if state.tech_at(slot).is_empty():
			continue
		var funding: String = STANDING_FUNDING if slot == standing else preset
		if state.funding_at(slot) != funding:
			state.set_funding(slot, funding)


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
	var purse: Dictionary = AiResearchPurse.read(config, economy, context, false)
	var candidates: Array[Dictionary] = AiResearchScores.candidates(
		config, economy, bool(purse["at_war"]), String(purse["door"])
	)
	return AiResearchPlan.walk(economy, purse, slot, candidates, {})


## The preset a court pays each slot (wiki: research-state § Funding presets;
## the purse's own read, kept on this door so callers keep one name).
static func funding_for(
	config: AiConfig, economy: PlayerEconomy = null, floor: int = 0
) -> String:
	return AiResearchPurse.funding_for(config, economy, floor)


## The purse research must leave behind: the court's own cash floor, never the
## muster reserve (issue #490).
static func research_floor(config: AiConfig) -> int:
	return AiResearchPurse.research_floor(config)


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
	return STANDING_FUNDING if AiResearchPurse.can_pay_standing(economy, floor, reserve) else ""


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
