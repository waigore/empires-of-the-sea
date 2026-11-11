class_name AiAgenda
extends RefCounted
## Hidden agendas (wiki: hidden-agendas). One agenda per AI Great Power, fixed at
## game start and assigned deterministically from the game and AI seeds. The
## agenda biases war/peace/alliance scoring on top of personality; it never
## bypasses hard diplomacy legality.

const WARMONGER: String = "warmonger"
const ISOLATIONIST: String = "isolationist"
const BACKSTABBER: String = "backstabber"
const TECH_THIEF: String = "tech_thief"
const PEACEMAKER: String = "peacemaker"
const ENVY: String = "envy"

const IDS: Array[String] = [
	WARMONGER, ISOLATIONIST, BACKSTABBER, TECH_THIEF, PEACEMAKER, ENVY,
]

## Seed modifiers, one per documented agenda behaviour (wiki: hidden-agendas
## § Design intent, § Scoring hooks; DR-20261111-27):
## - `war_gate` shifts the declare-war relation ceiling, `war_bias` war desire
##   (warmonger 70 / peacemaker 30 ceilings are the seed defaults);
## - `peace_bias` shifts the desire a court needs before it keeps a war going —
##   the peace leg is raised by the same amount (peacemaker early peace,
##   warmonger keeps the war alive);
## - `alliance_bias` shifts the alliance candidate and `betray_bias` the desire
##   against a court this one is allied to (backstabber hits allies when weak);
## - `trade_bias` shifts the trade-pact and subsidy candidates (isolationist
##   keeps to itself);
## - `rival_bias` is war desire against a human crown that has pulled ahead
##   (envy);
## - `research_bias` is a funding step (tech_thief pays for its catch-up).
const AGENDAS: Dictionary = {
	WARMONGER: {
		"war_gate": 20,
		"war_bias": 15,
		"peace_bias": -10,
		"alliance_bias": -10,
		"betray_bias": 0,
		"trade_bias": 0,
		"rival_bias": 0,
		"research_bias": 0,
	},
	ISOLATIONIST: {
		"war_gate": 0,
		"war_bias": -5,
		"peace_bias": 5,
		"alliance_bias": -25,
		"betray_bias": 0,
		"trade_bias": -20,
		"rival_bias": 0,
		"research_bias": 0,
	},
	BACKSTABBER: {
		"war_gate": 10,
		"war_bias": 10,
		"peace_bias": 0,
		"alliance_bias": 10,
		"betray_bias": 25,
		"trade_bias": 0,
		"rival_bias": 0,
		"research_bias": 0,
	},
	TECH_THIEF: {
		"war_gate": 0,
		"war_bias": 0,
		"peace_bias": 0,
		"alliance_bias": 0,
		"betray_bias": 0,
		"trade_bias": 0,
		"rival_bias": 0,
		"research_bias": 1,
	},
	PEACEMAKER: {
		"war_gate": -20,
		"war_bias": -15,
		"peace_bias": 15,
		"alliance_bias": 20,
		"betray_bias": 0,
		"trade_bias": 0,
		"rival_bias": 0,
		"research_bias": 0,
	},
	ENVY: {
		"war_gate": 5,
		"war_bias": 5,
		"peace_bias": 0,
		"alliance_bias": 0,
		"betray_bias": 0,
		"trade_bias": 0,
		"rival_bias": 20,
		"research_bias": 0,
	},
}

const NEUTRAL: Dictionary = {
	"war_gate": 0,
	"war_bias": 0,
	"peace_bias": 0,
	"alliance_bias": 0,
	"betray_bias": 0,
	"trade_bias": 0,
	"rival_bias": 0,
	"research_bias": 0,
}


## Deterministic assignment: hash(game seed, faction) picks one of six ids.
## The same seeds always yield the same agenda for the same court.
static func assign(game_seed: int, faction: int) -> String:
	var digest: int = ("%d:%d" % [game_seed, faction]).hash()
	return IDS[posmod(digest, IDS.size())]


static func has(id: String) -> bool:
	return AGENDAS.has(id)


static func resolve(id: String) -> Dictionary:
	return AGENDAS.get(id, NEUTRAL)
