class_name AiPhasePlanner
extends RefCounted
## A rival court's war footing (wiki: phase-planner-architecture,
## phase-planner-dispatch § Playable slice; DR-20261113-15).
##
## The seed architecture chooses a phase plan before the domain planners run, so
## every planner reads the empire's war situation instead of dumping every domain
## every turn. This slice publishes the footing and the dispatch it opens, from
## state the court already holds:
##
## - `war` — the court is at war with another Great Power. Its hulls belong to
##   the fleet, so no new colonisation voyage opens.
## - `fronts` — the same, with `phase.overstretch_fronts` (2) or more Great
##   Power wars: the court also takes any white peace it is offered, because no
##   court can win two wars at once, and it opens no new Great Power war either —
##   a crown suing for peace does not go looking for another front.
## - `peace` — no Great Power war: the published behaviour, every domain runs.
##
## The footing is a pure function of the relations, so the same state always
## reads the same phase and a replay never drifts. A war on a Minor Nation or a
## Tribe is colonial business and leaves the court at peace.
##
## A footing also decides which **dispatch slots** a court leaves open (wiki:
## phase-planner-dispatch § Suppression matrix): a closed slot is the planner's
## own default outcome, never a legality gate, and every order the court does
## issue still passes the published rules (DR-20261113-15, DR-20261114-11).

const PHASE_WAR: String = "war"
const PHASE_FRONTS: String = "fronts"
const PHASE_PEACE: String = "peace"
## No relations to read: nothing is concluded, every dispatch stays as published.
const PHASE_UNKNOWN: String = ""

## Dispatch slots a footing decides (wiki: phase-planner-dispatch § Suppression
## matrix). Every slot reads its outcome from `opens`, so no caller invents its
## own reading and the next slot lands on this one hook.
const SLOT_VOYAGE: String = "expansion.voyage"
const SLOT_DECLARE_WAR: String = "diplomacy.declare_war"
## The Tribe a court is drawing into its empire: the next envoy step of a chain
## it has not opened yet (wiki: diplomacy § GP–Tribe Rules; DR-20261114-02).
const SLOT_TRIBE_CHAIN: String = "expansion.tribe_chain"
## Every slot the table names, in the order the trace prints them.
const SLOTS: Array[String] = [SLOT_VOYAGE, SLOT_DECLARE_WAR, SLOT_TRIBE_CHAIN]

const LABELS: Dictionary = {
	PHASE_WAR: "at war",
	PHASE_FRONTS: "overstretched",
	PHASE_PEACE: "at peace",
	PHASE_UNKNOWN: "—",
}


## The court's footing this turn plus the readings that made it.
static func plan(config: AiConfig, state: DiplomacyState) -> Dictionary:
	var factors: Dictionary = {}
	if config == null or state == null:
		return {"phase": PHASE_UNKNOWN, "factors": factors}
	var wars: int = great_power_wars(state, config.faction)
	var fronts: int = maxi(config.parameter("phase.overstretch_fronts"), 1)
	factors["great_power_wars"] = wars
	factors["overstretch_fronts"] = fronts
	if wars <= 0:
		return {"phase": PHASE_PEACE, "factors": factors}
	if wars >= fronts:
		return {"phase": PHASE_FRONTS, "factors": factors}
	return {"phase": PHASE_WAR, "factors": factors}


## Phase name only, for callers that do not keep the readings.
static func phase_for(config: AiConfig, state: DiplomacyState) -> String:
	return String(plan(config, state)["phase"])


## True while the court is fighting a Great Power: a voyage spends hulls the
## fleet needs.
static func is_war_footing(phase: String) -> bool:
	return phase == PHASE_WAR or phase == PHASE_FRONTS


## True when the court fights enough fronts that it takes any white peace it is
## offered rather than refuse it.
static func takes_any_peace(phase: String) -> bool:
	return phase == PHASE_FRONTS


## Whether the footing leaves a dispatch slot open. A closed slot is the planner's
## own default outcome — the aim is not offered — never a legality gate: an order
## the court does issue still passes the same published rules (DR-20261113-15,
## DR-20261114-11).
static func opens(phase: String, slot: String) -> bool:
	match slot:
		SLOT_VOYAGE:
			# A Great Power war spends the hulls a voyage needs. Only a **new**
			# voyage closes: an expedition already afloat keeps sailing, so the
			# footing never strands it.
			return not is_war_footing(phase)
		SLOT_DECLARE_WAR:
			# An overstretched court takes any white peace it is offered, so it
			# opens no third Great Power front either: it is the one court no
			# rival should be able to count on for another war.
			return phase != PHASE_FRONTS
		SLOT_TRIBE_CHAIN:
			# A Great Power war spends the coin and the envoy's one order a new
			# chain needs. Only a **new** chain closes: a chain already opened
			# keeps its next step, so the footing never strands a stake the
			# court has already paid for.
			return not is_war_footing(phase)
	# A slot no footing names stays open: the dispatch matrix's default outcome
	# keeps merges total (wiki: phase-planner-dispatch).
	return true


## The slots a footing holds shut, in the table's own order — the reading the
## turn trace prints so a closed aim is never silent (REQ-P5-05).
static func closed_slots(phase: String) -> Array[String]:
	var shut: Array[String] = []
	for slot: String in SLOTS:
		if not opens(phase, slot):
			shut.append(slot)
	return shut


## Reader-facing footing for the observer panel and the turn trace.
static func label(phase: String) -> String:
	return String(LABELS.get(phase, LABELS[PHASE_UNKNOWN]))


## Wars against another Great Power. A war on a Minor Nation or a Tribe is
## colonial business and does not put the court on a war footing — the Passage
## voyage is not a fleet action.
static func great_power_wars(state: DiplomacyState, faction: int) -> int:
	var total: int = 0
	if state == null or faction < 0:
		return total
	for record: DiplomacyRelation in state.relations_of(faction):
		if record == null or not record.at_war:
			continue
		var other: int = record.other(faction)
		if FactionCatalog.type_of(other) == FactionCatalog.Type.GREAT_POWER:
			total += 1
	return total
