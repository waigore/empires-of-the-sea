class_name Intervention
extends RefCounted
## Third-party intervention when a Great Power declares war on a Minor Nation or
## Tribe (wiki: diplomacy § GP–Minor Rules § Intervention). Pure rules: a court
## holding an embassy in the victim court may join the war, stand aside (losing
## the embassy) or protest. AI courts roll the documented relation bands; the
## human court's choice waits for consent, like a call to arms.
##
## Sampling: the Bernoulli trial is a stable hash of (turn, aggressor, victim,
## court), so a replay of the same state always decides the same way and no RNG
## stream needs saving (DR-20261108-06).

const KIND_INTERVENE: String = "intervention_intervene"
const KIND_NOTHING: String = "intervention_do_nothing"
const KIND_PROTEST: String = "intervention_protest"

## Embassy-tier stages count as "has an Embassy with the victim".
const EMBASSY_TIERS: Array[String] = [
	DiplomacyCatalog.STAGE_EMBASSY,
	DiplomacyCatalog.STAGE_NAP,
	DiplomacyCatalog.STAGE_JOIN_EMPIRE,
]


## Courts offered a choice: other Great Powers holding an embassy in the victim
## court **or** purchased land in its provinces, not already at war with the
## aggressor (they have nothing to decide). Wiki: diplomacy § Intervention —
## "Embassy with that Minor/Tribe **or** purchased land recorded in its
## provinces"; a deed in a province the victim has since lost does not count.
static func candidates(
	state: DiplomacyState, aggressor: int, target: int, world: WorldMap = null
) -> Array[int]:
	var result: Array[int] = []
	if state == null:
		return result
	if FactionCatalog.type_of(target) == FactionCatalog.Type.GREAT_POWER:
		return result
	for court: int in FactionCatalog.great_power_ids():
		if court == aggressor:
			continue
		if not has_embassy(state, court, target) and not has_purchased_land(world, court, target):
			continue
		var record: DiplomacyRelation = state.relation(court, aggressor)
		if record != null and record.at_war:
			continue
		result.append(court)
	return result


static func has_embassy(state: DiplomacyState, court: int, target: int) -> bool:
	return state.overture(court, target) in EMBASSY_TIERS


## True when `court` holds a deed to a tile of a province the victim owns now.
static func has_purchased_land(world: WorldMap, court: int, target: int) -> bool:
	if world == null or court < 0 or target < 0:
		return false
	for model: MapModel in world.regions:
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != target:
				continue
			for tile: Vector2i in province.tiles:
				if model.ownership.purchaser(model.index_of(tile.x, tile.y)) == court:
					return true
	return false


## Queues or resolves one choice per eligible court. Returns player-facing lines.
static func on_war_declared(
	state: DiplomacyState, aggressor: int, target: int, world: WorldMap = null
) -> Array[String]:
	var messages: Array[String] = []
	for court: int in candidates(state, aggressor, target, world):
		if court == state.human_faction:
			if queue_human(state, aggressor, target, court):
				messages.append(
					(
						"%s declares war on %s. Our embassy stands: answer the"
						+ " intervention — join, stand aside, or protest."
					)
					% [FactionCatalog.name_of(aggressor), FactionCatalog.name_of(target)]
				)
			continue
		var choice: String = KIND_NOTHING
		if ai_intervenes(state, court, aggressor, target):
			choice = KIND_INTERVENE
		var line: String = _resolve(state, court, aggressor, target, choice, {})
		if not line.is_empty():
			messages.append(line)
	return messages


## AI intervention chance by the court's relation with the victim: 0–25 → 0%,
## 26–50 → 25%, 51–75 → 50%, 76–100 → 80% (wiki: diplomacy § Intervention).
static func chance_for(score: float) -> float:
	if score <= 25.0:
		return 0.0
	if score <= 50.0:
		return 0.25
	if score <= 75.0:
		return 0.5
	return 0.8


static func ai_intervenes(
	state: DiplomacyState, court: int, aggressor: int, target: int
) -> bool:
	var record: DiplomacyRelation = state.relation(court, target)
	var score: float = record.score if record != null else DiplomacyCatalog.INITIAL_SCORE
	return roll(state.turn, aggressor, target, court) < chance_for(score)


## Deterministic uniform [0, 1) sample; a pure integer hash of the four ids.
static func roll(turn: int, aggressor: int, target: int, court: int) -> float:
	var hash_value: int = 7
	for value: int in [turn, aggressor, target, court]:
		hash_value = (hash_value * 131 + value + 17) % 1000003
	return float(hash_value % 10000) / 10000.0


static func has_pending(state: DiplomacyState, court: int) -> bool:
	return not pending_for(state, court).is_empty()


static func pending_for(state: DiplomacyState, court: int) -> Dictionary:
	if state == null:
		return {}
	for offer: Dictionary in state.pending_interventions:
		if int(offer.get("court", -1)) == court:
			return offer
	return {}


## Queues exactly one offer per aggressor–victim pair for the human court.
static func queue_human(
	state: DiplomacyState, aggressor: int, target: int, court: int
) -> bool:
	for offer: Dictionary in state.pending_interventions:
		if (
			int(offer.get("court", -1)) == court
			and int(offer.get("aggressor", -1)) == aggressor
			and int(offer.get("target", -1)) == target
		):
			return false
	state.pending_interventions.append(
		{"aggressor": aggressor, "target": target, "court": court}
	)
	state.record_event("interventionOffered", court, target, {"aggressor": aggressor})
	return true


## Applies the human court's answer to the oldest waiting offer.
static func resolve_human(
	state: DiplomacyState, kind: String, tech: Dictionary = {}
) -> Dictionary:
	if state == null:
		return {"ok": false, "reason": "No court to answer for."}
	if kind not in [KIND_INTERVENE, KIND_NOTHING, KIND_PROTEST]:
		return {"ok": false, "reason": "Unknown intervention answer."}
	var offer: Dictionary = _take_pending(state, state.human_faction)
	if offer.is_empty():
		return {"ok": false, "reason": "No intervention awaits an answer."}
	var aggressor: int = int(offer["aggressor"])
	var target: int = int(offer["target"])
	var message: String = _resolve(
		state, state.human_faction, aggressor, target, kind, tech
	)
	return {
		"ok": true,
		"choice": kind,
		"message": message,
		"aggressor": aggressor,
		"target": target,
	}


## Protest penalty with the aggressor's Propaganda tech applied
## (wiki: tech-tree-diplomacy-civilian).
static func protest_penalty(tech: Dictionary = {}) -> float:
	return (
		DiplomacyCatalog.PROTEST_PENALTY_PROPAGANDA
		if bool(tech.get("propaganda", false))
		else DiplomacyCatalog.PROTEST_PENALTY
	)


static func _take_pending(state: DiplomacyState, court: int) -> Dictionary:
	for index in state.pending_interventions.size():
		var offer: Dictionary = state.pending_interventions[index]
		if int(offer.get("court", -1)) == court:
			state.pending_interventions.remove_at(index)
			return offer
	return {}


static func _resolve(
	state: DiplomacyState,
	court: int,
	aggressor: int,
	target: int,
	kind: String,
	tech: Dictionary
) -> String:
	match kind:
		KIND_INTERVENE:
			return _intervene(state, court, aggressor, target)
		KIND_PROTEST:
			return _protest(state, court, aggressor, target, tech)
	return _do_nothing(state, court, target, aggressor)


## Joining declares war on the aggressor; the embassy in the victim court stands.
static func _intervene(
	state: DiplomacyState, court: int, aggressor: int, target: int
) -> String:
	var war: Dictionary = DiplomacyRules.declare_war(state, court, aggressor, false)
	if not bool(war.get("ok", false)):
		return ""
	state.record_event("interventionIntervened", court, target, {"aggressor": aggressor})
	return "%s intervenes against %s for the sake of %s." % [
		FactionCatalog.name_of(court),
		FactionCatalog.name_of(aggressor),
		FactionCatalog.name_of(target),
	]


## Standing aside costs the embassy and every overture with the victim. Overtures
## are two-way (`establish_overture` writes both directions), so both records go;
## clearing one would leave `has_embassy` true and keep aid/subsidy open
## (wiki: diplomacy § Intervention § Do Nothing).
static func _do_nothing(
	state: DiplomacyState, court: int, target: int, aggressor: int
) -> String:
	state.set_overture(court, target, DiplomacyCatalog.STAGE_NONE)
	state.set_overture(target, court, DiplomacyCatalog.STAGE_NONE)
	state.cancel_subsidy(court, target)
	state.touch(court, target, "interventionDoNothing", {"aggressor": aggressor})
	return "%s stands aside; its embassy with %s is lost." % [
		FactionCatalog.name_of(court),
		FactionCatalog.name_of(target),
	]


## Protesting keeps the embassy and puts the cost on the court's relations.
static func _protest(
	state: DiplomacyState, court: int, aggressor: int, target: int, tech: Dictionary
) -> String:
	var penalty: float = protest_penalty(tech)
	state.apply_delta(
		court, aggressor, -penalty, "interventionProtest",
		{"target": target, "penalty": penalty}
	)
	return "%s protests %s's war on %s (−%d relation)." % [
		FactionCatalog.name_of(court),
		FactionCatalog.name_of(aggressor),
		FactionCatalog.name_of(target),
		int(penalty),
	]
