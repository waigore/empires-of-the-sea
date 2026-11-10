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
## "low:high" pair key -> turn the human court answered a peace offer.
var last_peace_turn: Dictionary = {}
## Faction id -> that rival court's ledger (stockpile, treasury, workers).
## Rival economies are seeded on first read and then persist like the player's
## (docs/ai.md, wiki: stockpiles-and-production).
var economies: Dictionary = {}


## Keeps the first agenda this court rolled; later configs read it back.
func agenda_for(config: AiConfig) -> String:
	if not agendas.has(config.faction):
		agendas[config.faction] = config.agenda
	return String(agendas[config.faction])


## The rival's ledger, created from the shared starting row on first read. The
## same instance is returned every turn, so assignments and stockpiles persist.
func economy_for(faction: int) -> PlayerEconomy:
	if not economies.has(faction):
		economies[faction] = PlayerEconomy.starting()
	return economies[faction] as PlayerEconomy


## Rival stockpile by faction, for the diplomacy planner's resource-need score
## (wiki: diplomacy-planner § Resource need). `exclude` keeps the human court's
## own fake ledger out of the read model.
func stockpiles(exclude: int = -1) -> Dictionary:
	var result: Dictionary = {}
	for faction: int in FactionCatalog.great_power_ids():
		if faction == exclude:
			continue
		result[faction] = economy_for(faction).stockpile
	return result


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


## A refused peace offer is not repeated immediately: the peace cooldown runs
## from the turn the human court answered (DR-20261109-07).
func note_peace(a: int, b: int, turn: int) -> void:
	last_peace_turn[pair_key(a, b)] = turn


func peace_on_cooldown(a: int, b: int, turn: int, cooldown: int) -> bool:
	var key: String = pair_key(a, b)
	if not last_peace_turn.has(key):
		return false
	return turn - int(last_peace_turn[key]) < cooldown


## Same unordered-pair key as DiplomacyState, so cooldowns cannot drift.
static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Plain data for local saves. Agendas are rolled once per court and cooldowns
## span turns, so a load must not re-roll a hidden agenda or restart a war
## cooldown (wiki: hidden-agendas, diplomacy § Cooldowns).
func to_dict() -> Dictionary:
	return {
		"agendas": agendas.duplicate(),
		"last_war_turn": last_war_turn.duplicate(),
		"last_overture_turn": last_overture_turn.duplicate(),
		"last_peace_turn": last_peace_turn.duplicate(),
		"economies": _economy_snapshots(),
	}


static func from_dict(data: Dictionary) -> AiState:
	var state := AiState.new()
	var stored_agendas: Dictionary = _dictionary(data.get("agendas", {}))
	for key: Variant in stored_agendas.keys():
		state.agendas[int(key)] = String(stored_agendas[key])
	state.last_war_turn = _turn_dictionary(data.get("last_war_turn", {}))
	state.last_overture_turn = _turn_dictionary(data.get("last_overture_turn", {}))
	state.last_peace_turn = _turn_dictionary(data.get("last_peace_turn", {}))
	state.economies = _economies_from(data.get("economies", {}))
	return state


## One snapshot per rival ledger, keyed by faction id. Missing factions are
## simply seeded from the starting row on first read, so old saves still load.
func _economy_snapshots() -> Dictionary:
	var result: Dictionary = {}
	for raw: Variant in economies.keys():
		var faction: int = int(raw)
		var economy: PlayerEconomy = economies[raw] as PlayerEconomy
		if economy != null:
			result[faction] = economy.snapshot()
	return result


static func _economies_from(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	var stored: Dictionary = _dictionary(raw)
	for key: Variant in stored.keys():
		var data: Dictionary = _dictionary(stored[key])
		if data.is_empty():
			continue
		var economy := PlayerEconomy.starting()
		economy.apply_snapshot(data)
		result[int(key)] = economy
	return result


static func _turn_dictionary(raw: Variant) -> Dictionary:
	var turns: Dictionary = {}
	var stored: Dictionary = _dictionary(raw)
	for key: Variant in stored.keys():
		turns[String(key)] = int(stored[key])
	return turns


static func _dictionary(raw: Variant) -> Dictionary:
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	return {}
