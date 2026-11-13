class_name AiPosture
extends RefCounted
## The court's footing as a per-mille modifier vector over goal domains
## (docs/ai-objectives.md; issue #491 T4, #499).
##
## T1 ranked every objective on its own utility alone. T4 adds two readings the
## parent analysis asked for — the war footing and the leader's domain weights —
## as **modifiers**, never as kill switches: a domain is scaled, the objective
## stays ranked, and a starved composite aim schedules instead of vanishing
## (wiki: phase-planner-architecture § Playable slice; ai-personalities § Domain
## weight vectors).
##
## Pure arithmetic: the footing, the config's weights and the registry are the
## only inputs, so a replay never drifts (REQ-P2-03, REQ-P3-03).

## Goal domains the ledger prices. `naval` follows the military weight and
## `expansion`/`civilian` the economic one, so a leader who prefers the army
## also prefers the fleet that carries it.
const DOMAINS: Array[String] = [
	"military", "naval", "expansion", "civilian", "diplomacy", "economy", "research",
]
## A domain is never zeroed: the floor keeps a peace-time-inverted aim alive.
const NEUTRAL: int = 1000


## The footing's own reading for one domain, in per-mille.
static func posture_mille(phase: String, domain: String, config: AiConfig) -> int:
	if config == null or not AiPhasePlanner.is_war_footing(phase):
		return NEUTRAL
	match domain:
		"military", "naval":
			return config.parameter("posture.war_boost")
		"expansion":
			var key: String = (
				"posture.fronts_expansion" if phase == AiPhasePlanner.PHASE_FRONTS
				else "posture.war_expansion"
			)
			return config.parameter(key)
	return NEUTRAL


## The leader's weight for one domain, in per-mille: weight 2 is neutral, each
## step away is `posture.weight_step`.
static func weight_mille(config: AiConfig, domain: String) -> int:
	if config == null:
		return NEUTRAL
	var weight: int = int(config.weights().get(_weight_domain(domain), 2))
	return NEUTRAL + (weight - 2) * config.parameter("posture.weight_step")


## One domain's combined modifier: footing × weight × victory pressure, never
## below the floor. `pressure_mille` is `AiVictoryPressure`'s boost — a court
## that can see the bar presses its military, naval and expansion aims
## (DR-20261114-04); every other domain reads it as neutral.
static func modifier(
	phase: String, domain: String, config: AiConfig, pressure_mille: int = NEUTRAL
) -> int:
	var combined: int = posture_mille(phase, domain, config) * weight_mille(config, domain)
	combined /= NEUTRAL
	if _presses(domain):
		combined = combined * maxi(pressure_mille, 0) / NEUTRAL
	return maxi(combined, config.parameter("posture.floor") if config != null else 0)


## The whole vector, keyed by domain: what the rank pass multiplies utilities by.
static func modifiers(
	phase: String, config: AiConfig, pressure_mille: int = NEUTRAL
) -> Dictionary:
	var vector: Dictionary = {}
	for domain: String in DOMAINS:
		vector[domain] = modifier(phase, domain, config, pressure_mille)
	return vector


## Domains the victory pressure scales: the war the court presses and the land
## it takes. Diplomacy, economy and research keep their own weights.
static func _presses(domain: String) -> bool:
	return domain == "military" or domain == "naval" or domain == "expansion"


## A domain that carries no weight of its own reads the weight of the domain it
## serves.
static func _weight_domain(domain: String) -> String:
	match domain:
		"naval":
			return "military"
		"expansion", "civilian":
			return "economy"
		_:
			return domain
