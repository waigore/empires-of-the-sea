class_name AiDiplomacyGates
extends RefCounted
## The readings a rival court shares when it weighs war, peace and its peaceful
## orders (wiki: diplomacy § GP AI policy for war vs. relations,
## diplomacy-planner). One copy, so the planner's war and peace gates and the
## offers' pact break can never drift apart (REQ-P2-03, REQ-P3-01, REQ-P3-03).
## Pure rules: state in, read out.

## War-goal objective: one province per 25 desire (wiki: diplomacy § War goals).
const DESIRE_PER_PROVINCE: float = 25.0


## War-goal objective: clamp(round(warDesire / 25), 1, targetProvinceCount).
static func desired_territory(war_desire_score: int, province_count: int) -> int:
	var target: int = int(roundf(float(war_desire_score) / DESIRE_PER_PROVINCE))
	return clampi(target, 1, maxi(1, province_count))


## True when this court is the stronger of the pair on the published power score
## — the cheap province next door, which an overstretched court may still take
## (DR-20261114-11). A caller that reads no power for the pair keeps the published
## planner: an unknown order of battle is not a war it cannot win.
static func outmatches(faction: int, target: int, context: Dictionary) -> bool:
	var powers: Dictionary = context.get("power", {})
	if not powers.has(faction) or not powers.has(target):
		return true
	return int(powers[faction]) > int(powers[target])


## True while the court's purse stands under the price of the line its next
## muster would buy — `army.min_treasury` plus the cheapest line its techs open
## (`AiArmyReinforce.cheapest_line_price`, the published "what it has to save
## for") — while the court stands under its war-target regiments: the purse
## that cannot re-arm the court is the purse that buys out of its crown wars
## (issue #975). A court at target strength, with no line to save for, or with
## no ledger to read keeps the published behaviour.
static func purse_under_muster(
	config: AiConfig, ai_state: AiState, context: Dictionary
) -> bool:
	if config == null or ai_state == null:
		return false
	var economy: PlayerEconomy = ai_state.economy_for(config.faction)
	if economy == null:
		return false
	var regiments: int = int(
		(context.get("regiments", {}) as Dictionary).get(config.faction, 0)
	)
	if regiments >= AiArmyReinforce.desired_regiments(config, true):
		return false
	var price: int = AiArmyReinforce.cheapest_line_price(economy)
	if price <= 0:
		return false
	return economy.treasury < maxi(config.parameter("army.min_treasury"), 0) + price


## The buy-out doctrine (issue #975): true when the standing war on `target` is
## a crown war — a fellow Great Power, one of the fronts the footing counts —
## and the court cannot re-arm for it, on an overstretched footing (`fronts`)
## or with a purse under the price of the line it is saving for. A war on a
## Minor Nation or a Tribe is colonial business and is never bought out; a court
## with no ledger to read keeps the published planner.
##
## The crown next door is the exception (issue #1082): the war whose front the
## field army can actually reach is the court's one road to conquest, so it
## outlives both buy-out legs. Only a court stamped with its frontier reads the
## exception (`AiFrontier.holds`); a court with no stamp keeps the buy-out.
static func buys_out(
	config: AiConfig,
	ai_state: AiState,
	target: int,
	context: Dictionary,
	posture: String
) -> bool:
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return false
	if AiFrontier.holds(config.faction, target, context):
		return false
	if AiPhasePlanner.takes_any_peace(posture):
		return true
	return purse_under_muster(config, ai_state, context)


## The pair's peace-offer cooldown. Either answer starts the base wait, so a
## court does not ask again every turn (wiki: diplomacy § Planner selection;
## DR-20261109-07). Every refusal then doubles the next wait up to the
## registry's cap: a court told no three times does not spend its one diplomacy
## order per cooldown turn asking the same question again (wiki: diplomacy
## § Cooldowns; DR-20261115-01).
static func peace_cooldown(
	config: AiConfig, ai_state: AiState, turn: int, target: int
) -> String:
	var base: int = config.parameter("diplomacy.peace_cooldown_turns")
	var refusals: int = ai_state.peace_refusals_for(config.faction, target)
	# The cap never shortens the published base wait, and the shift is bounded
	# so a long war cannot overflow the doubling.
	var cap: int = maxi(config.parameter("diplomacy.peace_refusal_cap"), base)
	var cooldown: int = mini(base * (1 << mini(refusals, 4)), cap)
	if ai_state.peace_on_cooldown(config.faction, target, turn, cooldown):
		if refusals <= 0:
			return "peace cooldown"
		return "peace cooldown, refused %d× (%d turns)" % [refusals, cooldown]
	return ""


## Why this court cannot put a white peace to the human court right now ("" when
## it may). A queued proposal waits for the answer, so a second one would only
## be refused by the court queue (DR-20261109-07).
static func peace_block(
	config: AiConfig, state: DiplomacyState, ai_state: AiState, turn: int, target: int
) -> String:
	if DiplomacyProposals.has_pending(state, target):
		return "the court is already considering a proposal"
	var cooling: String = peace_cooldown(config, ai_state, turn, target)
	if not cooling.is_empty():
		return cooling
	var check: Dictionary = DiplomacyRules.can_make_peace(state, config.faction, target)
	if not bool(check.get("ok", false)):
		return String(check.get("reason", "illegal"))
	return ""


## Why this court will not declare war right now ("" when it may). A Tribe the
## court is drawing into its empire is not a war target: the declaration would
## clear the envoy chain, and its provinces never count toward victory
## (wiki: factions § Tribe; diplomacy § GP–Tribe Rules; DR-20261114-02).
##
## An overstretched court opens no third Great Power front against a crown it does
## not outmatch: the same footing that takes any white peace it is offered does
## not reach for a war it would need another army for (DR-20261113-15,
## DR-20261114-11). The cheap province next door stays on — a court recovering
## from two fronts takes the war it can already win — and so does colonial
## business, because a war on a Minor Nation or a Tribe is not a front.
static func war_block(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	turn: int,
	target: int,
	record: DiplomacyRelation,
	desire: int,
	world: WorldMap = null,
	context: Dictionary = {},
	posture: String = AiPhasePlanner.PHASE_UNKNOWN
) -> String:
	var check: Dictionary = DiplomacyRules.can_declare_war(state, config.faction, target)
	if not bool(check.get("ok", false)):
		return String(check.get("reason", "illegal"))
	var crown: bool = FactionCatalog.type_of(target) == FactionCatalog.Type.GREAT_POWER
	if crown and not AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_DECLARE_WAR) \
			and not outmatches(config.faction, target, context):
		return "overstretched: no third front"
	# The re-declaration brake (issue #975): a court honors the truce its own
	# bought peace left — no new crown war on a pair still inside it, so the
	# peace lasts long enough to matter and the press cannot spend the 4-turn
	# war cooldown re-fighting the war it just signed away. Minor and Tribe
	# wars are colonial business and stay legal.
	if crown and AiWarMemory.truce(config, ai_state, turn, config.faction, target) > 0:
		return "the pair's truce holds: no new crown war yet"
	var cooldown: int = config.parameter("diplomacy.war_cooldown_turns")
	if ai_state.war_on_cooldown(config.faction, target, turn, cooldown):
		return "war cooldown"
	var treasury: int = int((context.get("treasury", {}) as Dictionary).get(config.faction, 0))
	var tech: Dictionary = (context.get("tech", {}) as Dictionary).get(config.faction, {})
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), config.faction, target,
		treasury, tech, AiTribeColony.CLAIM_POSTURE
	)
	if bool(colony.get("wanted", false)) or bool(colony.get("held", false)):
		return "an envoy chain has a claim on that court"
	if record.score > float(config.war_relation_ceiling()):
		return "relations too warm"
	if desire < config.parameter("diplomacy.war_declare_min_desire"):
		return "war desire too low"
	return ""


## Why a pact break is not worth the order it costs ("" when it is): the pair off
## its war cooldown, no envoy chain with a claim on the target (a declaration
## would clear what the court has paid for), and a footing that opens the front
## (issues #724, #752, #995).
static func pact_break_block(
	config: AiConfig,
	state: DiplomacyState,
	world: WorldMap,
	ai_state: AiState,
	turn: int,
	target: int,
	context: Dictionary
) -> String:
	var faction: int = faction_of(config)
	if ai_state.war_on_cooldown(
		faction, target, turn, config.parameter("diplomacy.war_cooldown_turns")
	):
		return "the pair is on its war cooldown"
	# A pact break to open a new front while the court is already fighting is
	# how crowns drown: the ban stands until this court is at peace elsewhere
	# (wiki: diplomacy § Breaking a pact; issue #752).
	if state != null:
		for other: DiplomacyRelation in state.relations_of(faction):
			if other.at_war:
				return "the court is at war on another front"
	var posture: String = AiPhasePlanner.phase_for(config, state)
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), faction, target,
		int((context.get("treasury", {}) as Dictionary).get(faction, 0)),
		(context.get("tech", {}) as Dictionary).get(faction, {}),
		# The claim, not this turn's slot: a footing never frees the court to
		# clear a chain it means to buy (DR-20261116-11).
		AiTribeColony.CLAIM_POSTURE
	)
	if bool(colony.get("wanted", false)) or bool(colony.get("held", false)):
		return "an envoy chain has a claim on that court"
	if (
		FactionCatalog.type_of(target) == FactionCatalog.Type.GREAT_POWER
		and not AiPhasePlanner.opens(posture, AiPhasePlanner.SLOT_DECLARE_WAR)
		and not outmatches(faction, target, context)
	):
		return "overstretched: no third front"
	return ""


## The court the gates read for; NO_ID when no court is named.
static func faction_of(config: AiConfig) -> int:
	return config.faction if config != null else MapModel.NO_ID
