class_name AiState
extends RefCounted
## Per-game AI bookkeeping that outlives one turn: the fixed agenda assignment
## and the per-pair cooldowns (wiki: hidden-agendas, diplomacy § Cooldowns).
## Pure RefCounted data so tests drive it without a map screen (REQ-P3-03).

## Faction id -> agenda id. Assigned once, then never re-rolled.
var agendas: Dictionary = {}
## "low:high" pair key -> turn the AI last declared war.
var last_war_turn: Dictionary = {}
## "low:high" pair key -> turn the AI last saw an overture accept/reject.
var last_overture_turn: Dictionary = {}


## Keeps the first agenda this court rolled; later configs read it back.
func agenda_for(config: AiConfig) -> String:
	if not agendas.has(config.faction):
		agendas[config.faction] = config.agenda
	return String(agendas[config.faction])


func note_war(a: int, b: int, turn: int) -> void:
	last_war_turn[pair_key(a, b)] = turn


func war_on_cooldown(a: int, b: int, turn: int, cooldown: int) -> bool:
	var key: String = pair_key(a, b)
	if not last_war_turn.has(key):
		return false
	return turn - int(last_war_turn[key]) < cooldown


func note_overture(a: int, b: int, turn: int) -> void:
	last_overture_turn[pair_key(a, b)] = turn


func overture_on_cooldown(a: int, b: int, turn: int, cooldown: int) -> bool:
	var key: String = pair_key(a, b)
	if not last_overture_turn.has(key):
		return false
	return turn - int(last_overture_turn[key]) < cooldown


## Same unordered-pair key as DiplomacyState, so cooldowns cannot drift.
static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]
