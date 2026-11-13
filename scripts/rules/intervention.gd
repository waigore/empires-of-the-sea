class_name Intervention
extends RefCounted
## Third-party intervention when a Great Power declares war on a Minor Nation or
## Tribe (wiki: diplomacy § GP–Minor Rules § Intervention). Pure rules: a court
## holding an embassy in the victim court **or purchased land in its provinces**
## may join the war, stand aside (losing the embassy) or protest. AI courts roll
## the documented relation bands, then protest instead of standing aside whenever
## the victim still matters to them; the human court's choice waits for consent,
## like a call to arms.
##
## Sampling: the Bernoulli trial is a stable hash of (turn, aggressor, victim,
## court), so a replay of the same state always decides the same way and no RNG
## stream needs saving (DR-20261108-06). The protest decision reads the same
## relation band, so it needs no second sample (DR-20261110-16).
##
## A deed is a stake the crown defends (DR-20261110-20). The relation band says
## how much a court likes the victim; the land it has bought there says how much
## it would lose, so the trial is never below the first band while one deed
## stands at risk, and a second deed lifts it to the second band. The bands
## themselves are unchanged for courts with only an embassy.

const KIND_INTERVENE: String = "intervention_intervene"
const KIND_NOTHING: String = "intervention_do_nothing"
const KIND_PROTEST: String = "intervention_protest"

## Stake floors: one deed keeps the court from walking away (25% trial), two
## make it a serious protector (50%). They never lower a warmed relation.
const DEED_CARE_ONE: float = 0.25
const DEED_CARE_SERIOUS: float = 0.5


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
	return DeedProtection.holds_deed(world, court, target)


## Queues or resolves one choice per eligible court. Returns player-facing lines.
## `aggressor_tech` is the declaring crown's own unlocked tech: Propaganda halves
## the protest penalty, and the victim's friends read it from the declarer, not
## from their own ledger (wiki: tech-tree-diplomacy-civilian § Propaganda).
static func on_war_declared(
	state: DiplomacyState, aggressor: int, target: int,
	world: WorldMap = null, aggressor_tech: Dictionary = {}
) -> Array[String]:
	var messages: Array[String] = []
	for court: int in candidates(state, aggressor, target, world):
		if court == state.human_faction:
			if queue_human(state, aggressor, target, court, world):
				var offer: Dictionary = pending_for(state, court)
				messages.append(ConsentCopy.intervention_body(offer))
			continue
		var choice: String = ai_choice(state, court, aggressor, target, world)
		var line: String = _resolve(
			state, court, aggressor, target, choice, aggressor_tech
		)
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


## The chance an AI court answers a declaration with war. The relation band is
## the floor for a court that has nothing but goodwill at stake; a court whose
## deeds sit in the victim's land defends what it paid for, so one deed keeps it
## in the first band and two make it a serious protector (DR-20261110-20).
static func protection_chance(
	state: DiplomacyState, court: int, aggressor: int, target: int,
	world: WorldMap = null
) -> float:
	var chance: float = chance_for(score_with(state, court, target))
	if DeedProtection.serious_stake(world, court, target):
		chance = maxf(chance, DEED_CARE_SERIOUS)
	elif DeedProtection.worth_protecting(world, court, target):
		chance = maxf(chance, DEED_CARE_ONE)
	return chance


static func ai_intervenes(
	state: DiplomacyState, court: int, aggressor: int, target: int,
	world: WorldMap = null
) -> bool:
	return (
		roll(state.turn, aggressor, target, court)
		< protection_chance(state, court, aggressor, target, world)
	)


## An AI court that does not intervene still protests while the victim sits in a
## band that could have moved it to war (score above 25): it keeps its embassy
## and puts a relation price on the aggression. Below that band the court does
## not care enough and stands aside as before (DR-20261110-16) — unless its
## deeds stand in the victim's land, which is a stake in its own right
## (DR-20261110-20).
static func ai_protests(
	state: DiplomacyState, court: int, target: int, world: WorldMap = null
) -> bool:
	if chance_for(score_with(state, court, target)) > 0.0:
		return true
	return DeedProtection.worth_protecting(world, court, target)


## The one answer an AI court gives at a declaration: join, protest or stand
## aside. Deterministic for a given state, so a saved campaign replays it.
static func ai_choice(
	state: DiplomacyState, court: int, aggressor: int, target: int,
	world: WorldMap = null
) -> String:
	if ai_intervenes(state, court, aggressor, target, world):
		return KIND_INTERVENE
	if ai_protests(state, court, target, world):
		return KIND_PROTEST
	return KIND_NOTHING


## What earns the court its seat at the table: "embassy", "deed" or "both".
## The answer the court is offered is the same; only the reason is told
## (REQ-P2-05, DR-20261110-20).
static func basis_for(
	state: DiplomacyState, court: int, target: int, world: WorldMap = null
) -> String:
	var embassy: bool = has_embassy(state, court, target)
	var deed: bool = DeedProtection.holds_deed(world, court, target)
	if embassy and deed:
		return "both"
	if deed:
		return "deed"
	if embassy:
		return "embassy"
	return ""


## The court's relation score with the victim; an unmet victim reads as the
## catalog's initial score, as the intervention chance already assumes.
static func score_with(state: DiplomacyState, court: int, target: int) -> float:
	var record: DiplomacyRelation = state.relation(court, target)
	return record.score if record != null else DiplomacyCatalog.INITIAL_SCORE


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


## Queues exactly one offer per aggressor–victim pair for the human court. The
## offer records what earns the court its seat (embassy, deed or both) and the
## holding behind it, so the prompt can name the stake (DR-20261110-20).
static func queue_human(
	state: DiplomacyState, aggressor: int, target: int, court: int,
	world: WorldMap = null
) -> bool:
	for offer: Dictionary in state.pending_interventions:
		if (
			int(offer.get("court", -1)) == court
			and int(offer.get("aggressor", -1)) == aggressor
			and int(offer.get("target", -1)) == target
		):
			return false
	state.pending_interventions.append(
		{
			"aggressor": aggressor,
			"target": target,
			"court": court,
			"basis": basis_for(state, court, target, world),
			"deeds": DeedProtection.deed_count(world, court, target),
			"stake": DeedProtection.stake_value(world, court, target),
		}
	)
	state.record_event("interventionOffered", court, target, {"aggressor": aggressor})
	return true


## The sentence that says what is at stake, shared by the court banner and the
## map toast so both always print the same reason (REQ-P2-05, REQ-P5-05). The
## words answer to a tongue in [ConsentCopy].
static func offer_text(offer: Dictionary) -> String:
	return ConsentCopy.intervention_stake(offer)


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
## (wiki: diplomacy § Intervention § Do Nothing). A court that was offered the
## choice only through a deed has no embassy to lose, and its purchased land
## stays recorded until province conquest rules apply (DR-20261110-20).
static func _do_nothing(
	state: DiplomacyState, court: int, target: int, aggressor: int
) -> String:
	var had_embassy: bool = has_embassy(state, court, target)
	state.set_overture(court, target, DiplomacyCatalog.STAGE_NONE)
	state.set_overture(target, court, DiplomacyCatalog.STAGE_NONE)
	state.cancel_subsidy(court, target)
	state.touch(court, target, "interventionDoNothing", {"aggressor": aggressor})
	if not had_embassy:
		return "%s stands aside; its deeds in %s stay in its hands." % [
			FactionCatalog.name_of(court),
			FactionCatalog.name_of(target),
		]
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
