class_name DialogueHome
extends RefCounted
## The beats a crown's own turn raises (wiki: dialogue-and-mood § Design intent —
## `event`: tech discovered, capital threatened, colony founded;
## DR-20261111-08). Pure rules: the map gathers what happened, this module
## records the pair act and reads it back — no node, no rule outcome touched
## (REQ-P2-03, REQ-P3-03).
##
## The reader never speaks its own line: a study is answered by the court that
## watches the crown most closely, the seat by the host that stands before it,
## and a colony by the Tribe that lost its flag. Bookkeeping stays silent, so a
## beat is recorded only for an act that actually happened.

const TECH_STUDIED: String = "techStudied"
const CAPITAL_THREATENED: String = "capitalThreatened"
## Recorded by the diplomacy pass itself when a Tribe becomes a colony.
const COLONY_FOUNDED: String = "colonyFormed"

const PLAN: Dictionary = {
	TECH_STUDIED: "event/tech_studied",
	CAPITAL_THREATENED: "event/capital_threatened",
	COLONY_FOUNDED: "event/colony_founded",
}


static func knows(kind: String) -> bool:
	return PLAN.has(kind)


## Which point a home-front act speaks, and who speaks it. The speaker is always
## the other court in the pair, never the reader, and a beat is only read by the
## court that recorded it: these lines are written from the rival's side of the
## reader's own turn, so they would be wrong words in the rival's mouth.
static func plan(event: Dictionary, viewer: int, other: int) -> Dictionary:
	var point: String = String(PLAN.get(String(event.get("kind", "")), ""))
	if point.is_empty() or int(event.get("a", -1)) != viewer:
		return {}
	return {"point": point, "speaker": other}


## The rival that watches the crown most closely: the lowest relation score
## among rival Great Powers, ties by ascending faction id, or -1 when no rival
## holds a relation with the crown. The court that likes the crown least is the
## one that reads its studies first.
static func watching_court(state: DiplomacyState, viewer: int) -> int:
	if state == null:
		return -1
	var best: int = -1
	var lowest: float = INF
	for faction: int in FactionCatalog.great_power_ids():
		if faction == viewer:
			continue
		var record: DiplomacyRelation = state.relation(viewer, faction)
		if record == null:
			continue
		if best < 0 or record.score < lowest or (
			is_equal_approx(record.score, lowest) and faction < best
		):
			best = faction
			lowest = record.score
	return best


## A study the reader finished this turn, answered by the watching court.
## Returns true when a beat was recorded.
static func record_tech_studied(
	state: DiplomacyState, viewer: int, tech_id: String
) -> bool:
	if state == null or tech_id.is_empty():
		return false
	var speaker: int = watching_court(state, viewer)
	if speaker < 0:
		return false
	state.record_event(TECH_STUDIED, viewer, speaker, {"tech": tech_id})
	return true


## A hostile host standing in the reader's capital province, answered by its
## owner. `hosts` is `[{owner, strength}]` gathered at the seat by the map layer;
## only a court at war with the reader threatens, and the strongest such host
## speaks (ties by ascending faction id). Returns true when a beat was recorded.
static func record_capital_threat(
	state: DiplomacyState, viewer: int, capital_province: int, hosts: Array
) -> bool:
	if state == null or capital_province < 0:
		return false
	var speaker: int = -1
	var strongest: float = -1.0
	for raw: Variant in hosts:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var host: Dictionary = raw
		var owner: int = int(host.get("owner", -1))
		if owner < 0 or owner == viewer:
			continue
		var record: DiplomacyRelation = state.relation(viewer, owner)
		if record == null or not record.at_war:
			continue
		var strength: float = float(host.get("strength", 0.0))
		var louder: bool = speaker < 0 or strength > strongest
		var ties: bool = (
			speaker >= 0
			and owner < speaker
			and is_equal_approx(strength, strongest)
		)
		if not (louder or ties):
			continue
		speaker = owner
		strongest = strength
	if speaker < 0:
		return false
	state.record_event(
		CAPITAL_THREATENED, viewer, speaker, {"province": capital_province}
	)
	return true
