class_name AiDiplomacyTreaties
extends RefCounted
## The treaty rungs a rival court weighs: the next overture in the chain, the
## formal alliance, and the answer the rules give an absorption (wiki:
## diplomacy § Overtures, § Join Empire, § GP AI policy; issues #750, #752).
## Split from [AiDiplomacyOffers] so no AI module outgrows the size bar
## (REQ-P3-01). The deed nudge and the pact lock that once lived here moved
## (issues #724, #841): the seller is named once by `AiMerchantWork`, and the
## pact is priced as published by its own rules module. Pure rules: state in,
## candidate out (REQ-P3-03).

## Join Empire to a court that would say no only burns the one order: the
## candidate is worth taking when the target's answer is likely yes
## (wiki: diplomacy § Join Empire; issue #752).
const JOIN_EMPIRE_ACCEPT_BONUS: int = 30


## The best treaty candidate for one court: a formal alliance once the pair is
## Allied, else the next free overture — scored for the colony the chain serves
## and the target's plausible answer to absorption.
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
	# The colony ambition: a charted Tribe the court can still buy is worth the
	# next envoy step even when the court is in no mood to improve relations for
	# their own sake (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02). Read
	# BEFORE the bank's refusal (#1135): the `chain_matters` bypass written for
	# exactly this case sat below the banking check and never ran — a court
	# below the bar banks on every turn it cannot cover both, so the funded
	# chain the ledger prices was shut for the whole campaign while its one
	# order went elsewhere. A charted Tribe's funded chain outranks the bank:
	# the bank is there to arm a conquest, not to shut every other court craft.
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), config.faction, target, treasury, tech,
		AiPhasePlanner.phase_for(config, state)
	)
	var chain_matters: bool = bool(colony.get("wanted", false)) \
		or bool(colony.get("held", false))
	# The deed's chain matters too (issue #1135): the ledger funds a priced deed
	# whose seller the court has charted, and the rung that lands the embassy is
	# the link the Merchant's purchase waits for — a Minor seller's chain is the
	# same published purchase the bank was never meant to shut. `chain_openable`
	# reads the seller's own region through the court's chart, so a deed across
	# the water prices its chain like a home one.
	if not chain_matters and target >= 0 and (
		FactionCatalog.type_of(target) == FactionCatalog.Type.MINOR_NATION
		or FactionCatalog.type_of(target) == FactionCatalog.Type.TRIBE
	):
		var seller_region: int = FactionCatalog.region_of(target)
		var seller_model: MapModel = world.region(seller_region) if world != null else null
		if seller_model != null:
			var view: VisibilityModel = (
				(context.get("charts", null) as CourtCharts).model_for(
					config.faction, seller_region
				)
				if context.get("charts", null) != null else null
			)
			var deed_chain: Dictionary = AiMerchantWork.openable_deed(
				seller_model, config.faction,
				{"diplomacy": state, "visibility": view}, true
			)
			chain_matters = not deed_chain.is_empty()
	# The conquest bank (issue #995): a court short of the bar whose host is
	# still under strength, with its purse one line-cycle short of the
	# chest, is saving for its next line — and a paid envoy rung is a
	# deferrable purchase. The chain the deed serves walks again the turn
	# the host stands. The purse is still read for every court that is not
	# banking, and for the chain (#1135) — except while the shortfall at the
	# bar is what the bank is for: an aim that bought an envoy with the
	# muster's own chest kept the line unfunded for the whole campaign
	# (bench run 2026-11-22: a Maya embassy took the purse the turn the
	# chest closed, at one regiment and sixteen provinces).
	var income: Dictionary = context.get("income", {}) as Dictionary
	if (not chain_matters or bool(income.get("conquest_gap", false))) \
			and not income.is_empty():
		var banked: String = AiIncome.bank_refusal(config, ai_state, income)
		if not banked.is_empty():
			return _blocked(banked, AiDiplomacyOffers.KIND_OVERTURE)
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
		var absorb: Dictionary = _absorption(world, config.faction, target, next, context)
		if bool(absorb.get("read", false)) and not bool(absorb.get("accept", false)):
			return _blocked(absorb["reason"], AiDiplomacyOffers.KIND_OVERTURE)
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
		if bool(best_entry.get("tribe_colony", false)) and colony_raise > 0:
			best_entry["utility"] = clampi(
				int(best_entry["utility"]) + colony_raise, 0, 100
			)
	return best_entry


## The Join Empire rung a Great Power target would refuse only burns the court's
## one order, so the rung is read before it is priced (issue #752). The answer
## is the rule's own (`DiplomacyRules.answer_join_empire`), the same call the
## absorption takes on the court — the AI never prices a yes the rule refuses.
## A caller that supplies no world or no power map gets `read: false`, which
## keeps the rung offered at its plain worth.
static func _absorption(
	world: WorldMap, faction: int, target: int, next: String, context: Dictionary
) -> Dictionary:
	if next != DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		return {}
	if FactionCatalog.type_of(target) != FactionCatalog.Type.GREAT_POWER:
		return {}
	var power: Dictionary = (context.get("power", {}) as Dictionary)
	if world == null or power.is_empty():
		return {}
	if DiplomacyRules.answer_join_empire(world, faction, target, power):
		return {"read": true, "accept": true, "reason": ""}
	return {
		"read": true,
		"accept": false,
		"reason": "the crown would refuse absorption",
	}



## True when the pact break on the table is the order this court's conquest
## waits behind (issue #995): the court stands short of the bar with its host
## already built — not banking, for the break's own gate has already held it
## out of the offers while the bank filled (`AiDiplomacyPacts.break_nap`) and
## the war it opens has already passed `AiDiplomacyGates.pact_break_block` —
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
