class_name AiResearchPurse
extends RefCounted
## What a rival court can pay for its studies this turn (wiki: ai-architecture
## § Research planner, research-state § Funding presets).
##
## [AiResearchPlanner] opens and assigns the slots; this home prices the purse
## those slots are read against — the surplus preset above the reserve, the cash
## floor guarding the standing study, the yard's row when its chest is already
## in hand, and which study is the door's own. The planner, the ledger's blocked
## reading and the crown's college all read this one purse, so a study the plan
## opens and a study the panel prints cannot be priced two ways
## (REQ-P2-03, REQ-P3-01, REQ-P3-03).

## The cheapest preset a court can pay; a court parked at its cash floor keeps
## one study alive at this rate rather than standing still (issue #490).
const STANDING_FUNDING: String = "low"


## The purse every slot is priced against this turn: the published preset at
## the court's floor, the cash floor guarding the standing study, and the
## standing slot that keeps it. `at_war`, `door` and `preset` feed the ranking.
## `writes` is false for a reading (the crown's college): the ration-estate step
## below moves a study, and a reading never touches the crown's college
## (DR-20261121-01).
static func read(
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
		preset = row_preset(preset, economy, save_floor)
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
		and can_pay_standing(economy, cash_floor, save_floor)
	)
	var standing: int = standing_slot(state) if can_stand else -1
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


## The preset a court pays each slot: `research.funding_index` shifted by the
## personality's research weight (3 pays one step up, 1 one step down) and by the
## agenda's own catch-up step (wiki: research-state § Funding presets;
## ai-personalities § Domain weight vectors; hidden-agendas — tech_thief pays for
## its catch-up, DR-20261111-27), clamped to the catalogue and then to what the
## purse can carry after `floor` — the reserve the court must not spend (its own
## cash floor; the muster reserve is the army planner's, not research's). A court
## that cannot pay the cheapest preset funds nothing that turn and keeps saving;
## one that can still keeps its standing study alive at that preset
## ([method AiResearchPlanner.plan]).
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
static func door_funding(economy: PlayerEconomy, cash_floor: int) -> String:
	var spare: int = economy.treasury - maxi(cash_floor, 0)
	# Prefer richer presets first; Low is the last that still teaches.
	for index in range(ResearchFunding.ORDER.size() - 1, 0, -1):
		var name: String = ResearchFunding.ORDER[index]
		if ResearchFunding.gold(name) <= spare:
			return name
	if can_pay_standing(economy, cash_floor):
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


## The ladder preset the whole slot row can pay: a preset is charged per slot,
## so one slot's price over the spare is not the purse's answer when three slots
## are underway — the row drops a step until every slot fits (issue #1126). A
## ladder that paid the single-slot preset spent 150 ducats against the 66 the
## hull's chest had left, and the yard never laid the hull it had saved for.
static func row_preset(preset: String, economy: PlayerEconomy, floor: int) -> String:
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
static func standing_slot(state: ResearchState) -> int:
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
static func can_pay_standing(
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
