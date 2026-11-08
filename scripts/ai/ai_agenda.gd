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

## Seed modifiers. `war_gate` shifts the declare-war relation ceiling and
## `war_bias` shifts war desire; `peace_bias` and `alliance_bias` feed the
## planners that use them. Warmonger 70 / peacemaker 30 relation ceilings come
## from the hidden-agendas seed defaults.
const AGENDAS: Dictionary = {
	WARMONGER: {
		"war_gate": 20,
		"war_bias": 15,
		"peace_bias": -10,
		"alliance_bias": -10,
	},
	ISOLATIONIST: {
		"war_gate": 0,
		"war_bias": -5,
		"peace_bias": 5,
		"alliance_bias": -25,
	},
	BACKSTABBER: {
		"war_gate": 10,
		"war_bias": 10,
		"peace_bias": 0,
		"alliance_bias": 10,
	},
	TECH_THIEF: {
		"war_gate": 0,
		"war_bias": 0,
		"peace_bias": 0,
		"alliance_bias": 0,
	},
	PEACEMAKER: {
		"war_gate": -20,
		"war_bias": -15,
		"peace_bias": 15,
		"alliance_bias": 20,
	},
	ENVY: {
		"war_gate": 5,
		"war_bias": 5,
		"peace_bias": 0,
		"alliance_bias": 0,
	},
}

const NEUTRAL: Dictionary = {
	"war_gate": 0,
	"war_bias": 0,
	"peace_bias": 0,
	"alliance_bias": 0,
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
