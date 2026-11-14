class_name MainlineAiPhasePlanner
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
##   court can win two wars at once.
## - `peace` — no Great Power war: the published behaviour, every domain runs.
##
## The footing is a pure function of the relations, so the same state always
## reads the same phase and a replay never drifts. A war on a Minor Nation or a
## Tribe is colonial business and leaves the court at peace.

const PHASE_WAR: String = "war"
const PHASE_FRONTS: String = "fronts"
const PHASE_PEACE: String = "peace"
## No relations to read: nothing is concluded, every dispatch stays as published.
const PHASE_UNKNOWN: String = ""

const LABELS: Dictionary = {
	PHASE_WAR: "at war",
	PHASE_FRONTS: "overstretched",
	PHASE_PEACE: "at peace",
	PHASE_UNKNOWN: "—",
}


## The court's footing this turn plus the readings that made it.
static func plan(config: MainlineAiConfig, state: DiplomacyState) -> Dictionary:
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
static func phase_for(config: MainlineAiConfig, state: DiplomacyState) -> String:
	return String(plan(config, state)["phase"])


## True while the court is fighting a Great Power: a voyage spends hulls the
## fleet needs.
static func is_war_footing(phase: String) -> bool:
	return phase == PHASE_WAR or phase == PHASE_FRONTS


## True when the court fights enough fronts that it takes any white peace it is
## offered rather than refuse it.
static func takes_any_peace(phase: String) -> bool:
	return phase == PHASE_FRONTS


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