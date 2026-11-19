class_name AiDiplomacyTreaties
extends RefCounted
## The treaty rungs a rival court weighs: the next overture in the chain, the
## formal alliance, and what the binding pact changes about both (wiki:
## diplomacy § Overtures, § GP AI policy; issues #750, #752). Split from
## [AiDiplomacyOffers] so no AI module outgrows the size bar (REQ-P3-01).
## Pure rules: state in, candidate out (REQ-P3-03).

## A court that has Merchant Companies and could sign a deed with this Minor or
## Tribe wants its envoy chain opened, so the Consulate/Embassy outranks the small
## peaceful orders it competes with — and is offered even when the court is in no
## mood to improve relations for their own sake (wiki: civilian-units § Merchant).
const LAND_ENVOY_BONUS: int = 12

## A pact signed to lock a peace: below this war desire a court values the
## binding pact for the war ban it carries (issue #752).
const NAP_LOCK_MAX_DESIRE: int = 40
const NAP_LOCK_BONUS: int = 8
## Join Empire to a court that would say no only burns the one order: the
## candidate is worth taking when the target's answer is likely yes
## (wiki: diplomacy § Join Empire; issue #752).
const JOIN_EMPIRE_ACCEPT_BONUS: int = 30


## The best treaty candidate for one court: a formal alliance once the pair is
## Allied, else the next free overture — scored for the peace lock, the land the
## chain would open, and the target's plausible answer to absorption.
static func best(
	config: AiConfig,
	state: DiplomacyState,
	ai_state: AiState,
	world: WorldMap,
	turn: int,
	target: int,
	improve: int,
	min_improve: int,
	treasury: int,
	tech: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var bonus: int = _land_envoy_bonus(
		state, world, config.faction, target, tech,
		context.get("charts", null), _deed_seller(state, world, config.faction, context)
	)
	# The conquest bank (issue #995): a court short of the bar whose host is
	# still under strength, with its purse one line-cycle short of the
	# chest, is saving for its next line — and a paid envoy rung is a
	# deferrable purchase. The chain the deed serves walks again the turn
	# the host stands. The purse is still read for every court that is not
	# banking.
	var income: Dictionary = context.get("income", {}) as Dictionary
	if AiIncome.banking(config, ai_state, income):
		return _blocked(
			"the court is banking for its army", AiDiplomacyOffers.KIND_OVERTURE
		)
	# The colony ambition: a charted Tribe the court can still buy is worth the
	# next envoy step even when the court is in no mood to improve relations for
	# their own sake (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), config.faction, target, treasury, tech,
		AiPhasePlanner.phase_for(config, state)
	)
	var chain_matters: bool = bonus > 0 or bool(colony.get("wanted", false)) \
		or bool(colony.get("held", false))
	if improve < min_improve and not chain_matters:
		return _blocked("improve-relations desire too low", AiDiplomacyOffers.KIND_OVERTURE)
	var cooldown: int = config.parameter("diplomacy.overture_cooldown_turns")
	if ai_state.overture_on_cooldown(config.faction, target, turn, cooldown):
		return _blocked("overture cooldown", AiDiplomacyOffers.KIND_OVERTURE)
	var best_entry: Dictionary = {}
	var record: DiplomacyRelation = state.relation(config.faction, target)
	if record != null and record.score >= DiplomacyCatalog.ALLIANCE_CLAMP:
		var alliance: Dictionary = DiplomacyRules.can_form_alliance(
			state, config.faction, target
		)
		if bool(alliance.get("ok", false)):
			best_entry = _offer(
				AiDiplomacyOffers.KIND_ALLIANCE,
				target,
				improve + int(config.agenda_traits.get("alliance_bias", 0)),
			)
	var next: String = DiplomacyCatalog.next_stage(state.overture(config.faction, target))
	var colony_raise: int = (
		int(colony.get("bonus", 0))
		if String(colony.get("stage", "")) == next
		else 0
	)
	if not next.is_empty():
		var absorb: Dictionary = _absorption(
			config, world, target, next, context
		)
		if bool(absorb.get("read", false)) and not bool(absorb.get("accept", false)):
			return _blocked(
				"the crown would refuse absorption", AiDiplomacyOffers.KIND_OVERTURE
			)
		var check: Dictionary = DiplomacyRules.can_establish_overture(
			state, world, config.faction, target, next, treasury, tech
		)
		if bool(check.get("ok", false)) and (
			best_entry.is_empty() or improve + colony_raise > int(best_entry["utility"])
		):
			best_entry = _offer(AiDiplomacyOffers.KIND_OVERTURE, target, improve)
			best_entry["stage"] = next
			if colony_raise > 0:
				best_entry["tribe_colony"] = true
			if bool(absorb.get("accept", false)):
				best_entry["utility"] = (
					int(best_entry["utility"]) + JOIN_EMPIRE_ACCEPT_BONUS
				)
	if best_entry.is_empty():
		return _blocked("no legal treaty", AiDiplomacyOffers.KIND_OVERTURE)
	if String(best_entry["kind"]) == AiDiplomacyOffers.KIND_OVERTURE:
		var raise: int = bonus
		if bool(best_entry.get("tribe_colony", false)):
			raise += colony_raise
		raise += _nap_lock_bonus(
			target, String(best_entry.get("stage", "")), 100 - improve
		)
		best_entry["utility"] = clampi(int(best_entry["utility"]) + raise, 0, 100)
	return best_entry


## The single seller this court warms for a deed: the reading the planner hands
## in (one scan per court per turn) or, for a caller that named none, the same
## cheapest-offer scan the merchant module runs. -1 when no charted seller
## offers one (issue #841).
static func _deed_seller(
	state: DiplomacyState, world: WorldMap, faction: int, context: Dictionary
) -> int:
	if context.has("deed_seller"):
		return int(context["deed_seller"])
	return AiMerchantWork.deed_seller(
		world, faction, context.get("charts", null), state
	)


## The land-deed nudge for this target: a Minor or Tribe this court could buy
## from once an envoy reaches it, while no embassy stands yet and the court holds
## the merchant tech. The tech is the buyer the chain serves — a court with no
## Merchant to walk the last rung has nothing to open a chain for, and a chain
## opened on credit warms the relation past the war ceiling and bars the conquest
## for nothing (issue #724, measured 2026-11-15). The purse is not read: the
## chain takes turns to walk and the purse refills while it does, so a priced
## deed opens it even on this turn's floor (issue #724 task 2). Only charted land
## counts: a province never reached offers nothing it can price, while any
## charted region's offer counts, so a court that has not yet met the seller can
## still want the door opened (wiki: civilian-units § Merchant;
## fog-and-exploration § Visibility Levels).
##
## **One seller, by name** (issue #841): the nudge goes to the court's cheapest
## deed partner alone, never to every charted Minor with a priced offer. Warmth
## is the same scale that bars a declaration, so warming every seller closed the
## conquest path outright (issue #724 round 3); a court now buys from the one
## minor it means to trade with and keeps its war-path minors cold.
static func _land_envoy_bonus(
	state: DiplomacyState,
	world: WorldMap,
	faction: int,
	target: int,
	tech: Dictionary,
	charts: CourtCharts = null,
	deed_seller: int = -1
) -> int:
	if world == null or state == null:
		return 0
	var kind: int = FactionCatalog.type_of(target)
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return 0
	if DiplomacyRules.has_embassy(state, faction, target):
		return 0
	if not CivilianCatalog.is_unlocked("merchant", tech):
		return 0
	if target != deed_seller:
		return 0
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var view: VisibilityModel = charts.model_for(faction, index) if charts != null else null
		if AiMerchantWork.priced_offer(model, faction, target, view) > 0:
			return LAND_ENVOY_BONUS
	return 0


## The Join Empire rung a Great Power target would refuse only burns the court's
## one order: it is offered when the target's answer is plausibly yes, and the
## accept-likely rung carries the absorption bonus (issue #752). A caller that
## supplies no world or no power map gets `read: false`, which keeps the rung
## offered at its plain worth.
static func _absorption(
	config: AiConfig,
	world: WorldMap,
	target: int,
	next: String,
	context: Dictionary
) -> Dictionary:
	if next != DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		return {}
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return {}
	var power: Dictionary = (context.get("power", {}) as Dictionary)
	if world == null or power.is_empty():
		return {}
	return {
		"read": true,
		"accept": DiplomacyRules.accepts_join_empire(world, config.faction, target, power),
	}



## True when the pact break on the table is the order this court's conquest
## waits behind (issue #995): the court stands short of the bar with its host
## already built — not banking, for the break's own gate has already held it
## out of the offers while the bank filled (`AiDiplomacyOffers._break_nap`) —
## the best offer is the pact break on a Great Power, and the best war, if one
## stands, is not itself the front the bar counts (a war on a Minor Nation or a
## Tribe is colonial business, never the big holder's land). A Great Power war
## still leads — it needs no break — and a minor's pact is not the wall the
## conquest waits on: only the big holder's pact leads. A frozen baseline's
## income row carries no gap, so the shared planner never leads it to a break
## (issue #995's subject-scoped surface).
static func pact_break_leads(
	best_offer: Dictionary, best_war: Dictionary, context: Dictionary
) -> bool:
	if best_offer.is_empty():
		return false
	if String(best_offer.get("kind", "")) != AiDiplomacyOffers.KIND_BREAK_NAP:
		return false
	var income: Dictionary = context.get("income", {}) as Dictionary
	if not bool(income.get("conquest_gap", false)):
		return false
	if FactionCatalog.type_of(int(best_offer.get("target", -1))) != (
		FactionCatalog.Type.GREAT_POWER
	):
		return false
	if not best_war.is_empty() and FactionCatalog.type_of(
		int(best_war["target"])
	) == FactionCatalog.Type.GREAT_POWER:
		return false
	return true


## The pact rung's worth as a peace lock against a peer the court does not mean
## to fight (issue #752).
static func _nap_lock_bonus(target: int, next: String, desire: int) -> int:
	if next != DiplomacyCatalog.STAGE_NAP:
		return 0
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return 0
	if desire > NAP_LOCK_MAX_DESIRE:
		return 0
	return NAP_LOCK_BONUS


static func _offer(kind: String, target: int, utility: int) -> Dictionary:
	return {
		"ok": true,
		"kind": kind,
		"target": target,
		"utility": clampi(utility, 0, 100),
		"stage": "",
		"amount": 0,
	}


## A refused candidate keeps its kind, so the turn trace names what the court
## would not offer and why (wiki: turn-trace-interpretation).
static func _blocked(reason: String, kind: String = "") -> Dictionary:
	return {"ok": false, "kind": kind, "blocked": reason}
