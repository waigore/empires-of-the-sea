class_name DiplomacyState
extends RefCounted
## All diplomatic state for one game: relations, overtures, subsidies and
## colonies (wiki: diplomacy). Pure RefCounted data with no node or autoload
## dependencies, so rules and tests drive it without a map screen (REQ-P3-03).

var turn: int = 0
## Pair key "low:high" -> DiplomacyRelation.
var relations: Dictionary = {}
## Directional overture key "from>to" -> stage string.
var overtures: Dictionary = {}
## Directional subsidy key "payer>target" -> percent (5–20).
var subsidies: Dictionary = {}
## Tribe id -> suzerain Great Power id.
var colonies: Dictionary = {}
## Human court for consent decisions (call to arms); set by the session.
var human_faction: int = FactionCatalog.PLAYER_FACTION
## Pair key -> true for formal alliances at the close of the preceding turn.
## A treaty signed this turn never grants mutual defence for this turn.
var alliance_snapshot: Dictionary = {}
## Calls to arms the human court has not answered: {aggressor, defender, ally}.
var pending_calls: Array[Dictionary] = []
## Append-only recent history for the court and tests.
var events: Array[Dictionary] = []

var _modified: Dictionary = {}
var _order_counts: Dictionary = {}


func initialize(at_turn: int) -> void:
	reset(at_turn)
	_seed_group(_region_peers(FactionCatalog.OLD_WORLD))
	_seed_group(_region_peers(FactionCatalog.NEW_WORLD))
	for gp_a: int in FactionCatalog.great_power_ids():
		for gp_b: int in FactionCatalog.great_power_ids():
			if gp_a == gp_b:
				continue
			set_overture(gp_a, gp_b, DiplomacyCatalog.STAGE_EMBASSY)


func reset(at_turn: int) -> void:
	turn = at_turn
	relations.clear()
	overtures.clear()
	subsidies.clear()
	colonies.clear()
	events.clear()
	alliance_snapshot.clear()
	pending_calls.clear()
	_modified.clear()
	_order_counts.clear()


func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func relation(a: int, b: int) -> DiplomacyRelation:
	return relations.get(pair_key(a, b), null)


func has_relation(a: int, b: int) -> bool:
	return relations.has(pair_key(a, b))


## Creates a relation on first contact. Existing records are returned untouched.
func ensure_relation(a: int, b: int, at_turn: int = -1) -> DiplomacyRelation:
	if a == b:
		return null
	var found: DiplomacyRelation = relation(a, b)
	if found != null:
		return found
	var created_turn: int = turn if at_turn < 0 else at_turn
	var record: DiplomacyRelation = DiplomacyRelation.create(a, b, created_turn)
	relations[pair_key(a, b)] = record
	return record


func relations_of(faction: int) -> Array[DiplomacyRelation]:
	var result: Array[DiplomacyRelation] = []
	for record: DiplomacyRelation in relations.values():
		if record.a == faction or record.b == faction:
			result.append(record)
	result.sort_custom(
		func(left: DiplomacyRelation, right: DiplomacyRelation) -> bool:
			return left.other(faction) < right.other(faction)
	)
	return result


func overture(from_id: int, to_id: int) -> String:
	return String(overtures.get("%d>%d" % [from_id, to_id], DiplomacyCatalog.STAGE_NONE))


func set_overture(from_id: int, to_id: int, stage: String) -> void:
	var key: String = "%d>%d" % [from_id, to_id]
	if stage == DiplomacyCatalog.STAGE_NONE:
		overtures.erase(key)
	else:
		overtures[key] = stage


func subsidy(payer: int, target: int) -> int:
	return int(subsidies.get("%d>%d" % [payer, target], 0))


func set_subsidy(payer: int, target: int, percent: int) -> void:
	subsidies["%d>%d" % [payer, target]] = percent
	# Setting a subsidy is score-neutral, so it must not swallow the pair's
	# per-turn drift (wiki: diplomacy § Relation Model, skip-on-event list).
	record_event("subsidySet", payer, target, {"percent": percent})


func cancel_subsidy(payer: int, target: int) -> bool:
	var key: String = "%d>%d" % [payer, target]
	if not subsidies.has(key):
		return false
	var percent: int = int(subsidies[key])
	subsidies.erase(key)
	record_event("subsidyCancelled", payer, target, {"percent": percent})
	return true


func colony_of(tribe: int) -> int:
	return int(colonies.get(tribe, -1))


func set_colony(tribe: int, gp: int) -> void:
	if gp < 0:
		colonies.erase(tribe)
	else:
		colonies[tribe] = gp
	record_event("colonySet", tribe, gp if gp >= 0 else -1, {"tribe": tribe, "gp": gp})


func claimed(from_id: int, to_id: int, kind: String) -> bool:
	return int(_order_counts.get("%s:%d>%d" % [kind, from_id, to_id], 0)) > 0


func claim(from_id: int, to_id: int, kind: String) -> void:
	var key: String = "%s:%d>%d" % [kind, from_id, to_id]
	_order_counts[key] = int(_order_counts.get(key, 0)) + 1


func is_modified(a: int, b: int) -> bool:
	return _modified.has(pair_key(a, b))


## Records a score-neutral event (peace, war, overture) and suppresses decay.
func touch(a: int, b: int, kind: String, data: Dictionary = {}) -> void:
	_modified[pair_key(a, b)] = true
	var record: DiplomacyRelation = relation(a, b)
	if record != null:
		record.last_interaction_turn = turn
	record_event(kind, a, b, data)


func apply_delta(a: int, b: int, delta: float, kind: String, data: Dictionary = {}) -> float:
	var record: DiplomacyRelation = relation(a, b)
	if record == null:
		record = ensure_relation(a, b)
	var before: float = record.score
	record.add_score(delta)
	var payload: Dictionary = data.duplicate()
	payload["delta"] = delta
	payload["before"] = before
	payload["after"] = record.score
	touch(a, b, kind, payload)
	return record.score


func record_event(kind: String, a: int, b: int, data: Dictionary = {}) -> void:
	events.append({"kind": kind, "a": a, "b": b, "turn": turn, "data": data})
	if events.size() > 240:
		events.pop_front()


func apply_decay() -> int:
	var changed: int = 0
	for record: DiplomacyRelation in relations.values():
		if record.at_war or _modified.has(pair_key(record.a, record.b)):
			continue
		if is_equal_approx(record.score, DiplomacyCatalog.EQUILIBRIUM):
			continue
		var target: float = minf(
			DiplomacyCatalog.EQUILIBRIUM, record.score + DiplomacyCatalog.RELATION_DECAY
		)
		if record.score > DiplomacyCatalog.EQUILIBRIUM:
			target = maxf(
				DiplomacyCatalog.EQUILIBRIUM,
				record.score - DiplomacyCatalog.RELATION_DECAY
			)
		if not is_equal_approx(target, record.score):
			record.score = target
			changed += 1
	return changed


## Diplomacy phase close: drop broken subsidies, drift relations, clear claims.
func end_turn() -> Dictionary:
	var cancelled: Array[String] = []
	for key: String in subsidies.keys():
		var parts: PackedStringArray = key.split(">")
		var payer: int = int(parts[0])
		var target: int = int(parts[1])
		var record: DiplomacyRelation = relation(payer, target)
		var stage: String = overture(payer, target)
		var embassy: bool = stage in [
			DiplomacyCatalog.STAGE_EMBASSY,
			DiplomacyCatalog.STAGE_NAP,
			DiplomacyCatalog.STAGE_JOIN_EMPIRE,
		]
		if record == null or record.at_war or not embassy:
			cancelled.append(key)
	for key: String in cancelled:
		var parts: PackedStringArray = key.split(">")
		record_event(
			"subsidyCancelled",
			int(parts[0]),
			int(parts[1]),
			{"percent": int(subsidies[key])}
		)
		subsidies.erase(key)
	var decayed: int = apply_decay()
	# The mutual-defence snapshot is the state at the close of this turn: a
	# treaty signed next turn cannot be pulled into today's war (wiki: diplomacy).
	CallToArms.freeze_alliances(self)
	_modified.clear()
	_order_counts.clear()
	turn += 1
	return {"decayed": decayed, "subsidies_cancelled": cancelled.size()}


## Removes every trace of a faction absorbed by Join Empire or removed when its
## crown falls (wiki: capital-and-connectivity § Fall).
func clear_relations_of(faction: int) -> void:
	for key: String in relations.keys():
		var record: DiplomacyRelation = relations[key]
		if record.a == faction or record.b == faction:
			relations.erase(key)
	for key: String in alliance_snapshot.keys():
		var parts: PackedStringArray = key.split(":")
		if int(parts[0]) == faction or int(parts[1]) == faction:
			alliance_snapshot.erase(key)
	var kept_calls: Array[Dictionary] = []
	for entry: Dictionary in pending_calls:
		if int(entry.get("aggressor", -1)) == faction:
			continue
		if int(entry.get("defender", -1)) == faction:
			continue
		if int(entry.get("ally", -1)) == faction:
			continue
		kept_calls.append(entry)
	pending_calls.assign(kept_calls)
	for key: String in overtures.keys():
		var parts: PackedStringArray = key.split(">")
		if int(parts[0]) == faction or int(parts[1]) == faction:
			overtures.erase(key)
	for key: String in subsidies.keys():
		var parts: PackedStringArray = key.split(">")
		if int(parts[0]) == faction or int(parts[1]) == faction:
			subsidies.erase(key)
	for tribe: int in colonies.keys():
		if tribe == faction or int(colonies[tribe]) == faction:
			colonies.erase(tribe)


func _seed_group(ids: Array[int]) -> void:
	for first in ids.size():
		for second in range(first + 1, ids.size()):
			ensure_relation(ids[first], ids[second], turn)


func _region_peers(region: int) -> Array[int]:
	var result: Array[int] = []
	for faction: Dictionary in FactionCatalog.all():
		var type: int = int(faction["type"])
		if int(faction["region"]) != region:
			continue
		if region == FactionCatalog.OLD_WORLD:
			if type == FactionCatalog.Type.GREAT_POWER or type == FactionCatalog.Type.MINOR_NATION:
				result.append(int(faction["id"]))
		elif type == FactionCatalog.Type.TRIBE:
			result.append(int(faction["id"]))
	return result
