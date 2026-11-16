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
		context.get("charts", null)
	)
	# The colony ambition: a charted Tribe the court can still buy is worth the
	# next envoy step even when the court is in no mood to improve relations for
	# their own sake (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
	var colony: Dictionary = AiTribeColony.ambition(
		state, world, context.get("charts", null), config.faction, target, treasury, tech
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
static func _land_envoy_bonus(
	state: DiplomacyState,
	world: WorldMap,
	faction: int,
	target: int,
	tech: Dictionary,
	charts: CourtCharts = null
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
