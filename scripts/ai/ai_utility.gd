class_name AiUtility
extends RefCounted
## The ledger's shared 0–100 currency (T1, trace-only).
##
## Each planner scores in its own scale — war desire 0–100, production runs,
## research points, cargo holds. `normalize` maps a raw score into the shared
## currency; `adjust` then applies the court's posture and agenda as a
## **modifier, not a kill switch**: at war defence rises and colonisation
## falls, but the objective stays alive and schedules (DR-20261113-15).

const POSTURE_WAR: String = "war"
const POSTURE_FRONTS: String = "fronts"
const POSTURE_PEACE: String = "peace"

## Domain posture modifiers. Above 1 raises the objective's rank, below 1
## lowers it; nothing is zeroed, so a deferred objective still explains itself
## in the trace.
const POSTURE_MODIFIERS: Dictionary = {
	POSTURE_WAR: {
		"military": 1.5, "defence": 1.5, "naval": 1.2, "invasion": 1.2,
		"muster": 1.3, "spy": 1.1, "diplomacy": 1.0, "colonisation": 0.6,
		"economy": 0.9, "research": 0.9, "civilian": 0.9, "cargo": 0.9,
		"market": 0.9,
	},
	POSTURE_FRONTS: {
		"military": 1.3, "defence": 1.3, "muster": 1.2, "naval": 1.1,
		"diplomacy": 1.1, "invasion": 1.0, "spy": 1.0, "colonisation": 0.8,
		"economy": 0.95, "research": 0.95, "civilian": 0.95, "cargo": 0.95,
		"market": 0.95,
	},
	POSTURE_PEACE: {
		"economy": 1.1, "research": 1.1, "civilian": 1.1, "cargo": 1.1,
		"market": 1.1, "colonisation": 1.0, "diplomacy": 1.0, "naval": 0.9,
		"spy": 0.9, "muster": 0.9, "military": 0.8, "defence": 0.8,
		"invasion": 0.7,
	},
}

## Agenda biases: the court's own book of grudges reweights a domain on top of
## its posture (wiki: hidden-agendas; DR-20261111-27).
const AGENDA_BIAS: Dictionary = {
	"warmonger": {"military": 1.2, "naval": 1.1, "muster": 1.1},
	"peacemaker": {"diplomacy": 1.2, "military": 0.85},
	"isolationist": {"diplomacy": 0.85, "colonisation": 0.9},
	"backstabber": {"diplomacy": 1.1, "spy": 1.1},
	"tech_thief": {"research": 1.2},
	"envy": {"military": 1.1, "diplomacy": 1.1},
}

## The published bench weight per domain, used when a planner's turn output
## carries no score of its own (the parent issue's bench: colonisation 50 per
## province, and so on). One table so the trace's numbers stay auditable.
const DOMAIN_BASE: Dictionary = {
	"diplomacy": 50, "military": 60, "defence": 60, "naval": 55,
	"invasion": 55, "colonisation": 50, "economy": 45, "research": 45,
	"civilian": 40, "cargo": 40, "market": 35, "muster": 55, "spy": 30,
}

## Each planner's own score ceiling, so `normalize` maps its scale onto 0–100
## without a per-call guess. A domain missing here falls back to DOMAIN_BASE.
const SCORE_CEILING: Dictionary = {
	"diplomacy": 100, "economy": 84, "research": 120, "civilian": 100,
	"cargo": 20, "market": 20,
}


## Map a raw planner score into 0–100. `high` is the scale's ceiling; a
## non-positive ceiling falls back to the domain's published ceiling so a trace
## never divides by zero.
static func normalize(raw: int, high: int = 0, domain: String = "") -> int:
	var ceiling: int = high
	if ceiling <= 0:
		ceiling = int(SCORE_CEILING.get(domain, DOMAIN_BASE.get(domain, 100)))
	if ceiling <= 0:
		return 0
	return clampi(int(roundf(float(raw) * 100.0 / float(ceiling))), 0, 100)


static func posture_modifier(domain: String, phase: String) -> float:
	var table: Dictionary = POSTURE_MODIFIERS.get(phase, {})
	return float(table.get(domain, 1.0))


static func agenda_bias(domain: String, agenda: String) -> float:
	var table: Dictionary = AGENDA_BIAS.get(agenda, {})
	return float(table.get(domain, 1.0))


## The objective's ranked utility: normalized score × posture × agenda, clamped
## to 0–100. A blocked objective keeps its utility so the trace can still show
## what it was worth.
static func adjust(utility: int, domain: String, phase: String, agenda: String) -> int:
	var scaled: float = (
		float(utility) * posture_modifier(domain, phase) * agenda_bias(domain, agenda)
	)
	return clampi(int(roundf(scaled)), 0, 100)
