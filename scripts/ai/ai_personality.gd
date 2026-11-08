class_name AiPersonality
extends RefCounted
## Leader personalities for AI Great Powers (wiki: ai-personalities).
##
## A personality is read-only config: domain weight vector plus war-gate and
## war-bias offsets that shift the diplomacy planner's thresholds. It never
## bypasses legality — it only moves scores (REQ-P2-03).

## Canonical archetypes. `war_gate` shifts the declare-war relation ceiling;
## `war_bias` shifts war desire. `weights` order domain planners.
const ARCHETYPES: Dictionary = {
	"victoria": {
		"title": "industrial_trader",
		"war": "low",
		"war_gate": -10,
		"war_bias": -10,
		"weights": {"economy": 3, "military": 2, "diplomacy": 3, "research": 2},
	},
	"napoleon": {
		"title": "fortifier",
		"war": "high",
		"war_gate": 20,
		"war_bias": 15,
		"weights": {"economy": 2, "military": 3, "diplomacy": 2, "research": 2},
	},
	"isabella": {
		"title": "explorer",
		"war": "medium",
		"war_gate": 0,
		"war_bias": 0,
		"weights": {"economy": 2, "military": 2, "diplomacy": 2, "research": 2},
	},
	"henry": {
		"title": "navigator",
		"war": "very_low",
		"war_gate": -20,
		"war_bias": -15,
		"weights": {"economy": 3, "military": 1, "diplomacy": 3, "research": 2},
	},
	"de_ruyter": {
		"title": "merchant",
		"war": "low",
		"war_gate": -10,
		"war_bias": -10,
		"weights": {"economy": 3, "military": 1, "diplomacy": 3, "research": 1},
	},
	"frederick": {
		"title": "defender",
		"war": "medium",
		"war_gate": 5,
		"war_bias": 0,
		"weights": {"economy": 2, "military": 3, "diplomacy": 2, "research": 2},
	},
	"gustavus": {
		"title": "tactician",
		"war": "medium",
		"war_gate": 0,
		"war_bias": 5,
		"weights": {"economy": 2, "military": 3, "diplomacy": 2, "research": 3},
	},
}

## Default leader per Great Power id (wiki: leader-bonuses § Leader Selection:
## AI GPs take their leader from config; this table is that config).
const GP_LEADERS: Dictionary = {
	0: "isabella",
	1: "victoria",
	2: "napoleon",
	3: "henry",
	4: "de_ruyter",
	5: "gustavus",
}

## Neutral fallback when a leader key names no known archetype.
const NEUTRAL: Dictionary = {
	"title": "reserve",
	"war": "medium",
	"war_gate": 0,
	"war_bias": 0,
	"weights": {"economy": 2, "military": 2, "diplomacy": 2, "research": 2},
}


static func keys() -> Array[String]:
	var result: Array[String] = []
	for key: String in ARCHETYPES.keys():
		result.append(key)
	result.sort()
	return result


static func leader_for(faction: int) -> String:
	return String(GP_LEADERS.get(faction, ""))


## Active personality: an exact archetype key, else neutral defaults.
static func resolve(leader_key: String) -> Dictionary:
	var key: String = leader_key.to_lower()
	if ARCHETYPES.has(key):
		return ARCHETYPES[key]
	return NEUTRAL


static func for_faction(faction: int) -> Dictionary:
	return resolve(leader_for(faction))


## Domain weight vector for phase planning (economy/military/diplomacy/research).
static func weights_for(faction: int) -> Dictionary:
	return for_faction(faction).get("weights", NEUTRAL["weights"])
