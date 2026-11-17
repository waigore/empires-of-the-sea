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
## Pair key "low:high" -> turn the favoured-trading-partner pact was signed
## (wiki: world-market § FTP). Bilateral: one entry serves both directions.
var ftps: Dictionary = {}
## Directional boycott key "issuer>target" -> turn imposed
## (wiki: diplomacy § GP–Tribe — Boycott).
var boycotts: Dictionary = {}
## Tribe id -> suzerain Great Power id.
var colonies: Dictionary = {}
## Human court for consent decisions (call to arms); set by the session.
var human_faction: int = FactionCatalog.PLAYER_FACTION
## Pair key -> true for formal alliances at the close of the preceding turn.
## A treaty signed this turn never grants mutual defence for this turn.
var alliance_snapshot: Dictionary = {}
## Pair key -> true for pairs that cleared a world-market deal this turn: the
## next Diplomacy phase lifts them before decay (wiki: diplomacy § Relation
## Model — trade-deal boost, R10).
var trade_pairs: Dictionary = {}
## Calls to arms the human court has not answered: {aggressor, defender, ally}.
var pending_calls: Array[Dictionary] = []
## Intervention offers the human court has not answered:
## {aggressor, target, court} (wiki: diplomacy § Intervention).
var pending_interventions: Array[Dictionary] = []
## Rival proposals the human court has not answered:
## {from, kind, stage} (wiki: diplomacy § GP AI policy → court hand-off).
var pending_offers: Array[Dictionary] = []
## Append-only history for the court and tests. Unbounded within a campaign
## (wiki: diplomacy § Diplomatic History — retention); the panel narrows it to
## one pair and the rules never drop an entry.
var events: Array[Dictionary] = []

var _modified: Dictionary = {}
var _order_counts: Dictionary = {}


## Opens the ledger for a new campaign; the seeding itself lives in
## [DiplomacyLifetime] with the rest of a court's comings and goings.
func initialize(at_turn: int) -> void:
	DiplomacyLifetime.open(self, at_turn)


func reset(at_turn: int) -> void:
	turn = at_turn
	relations.clear()
	overtures.clear()
	subsidies.clear()
	ftps.clear()
	boycotts.clear()
	colonies.clear()
	events.clear()
	alliance_snapshot.clear()
	trade_pairs.clear()
	pending_calls.clear()
	pending_interventions.clear()
	pending_offers.clear()
	_modified.clear()
	_order_counts.clear()


## The state's accessor for a pair key; the format itself lives in
## [DiplomacyKeys], which every rules module writes and reads.
func pair_key(a: int, b: int) -> String:
	return DiplomacyKeys.pair(a, b)


func relation(a: int, b: int) -> DiplomacyRelation:
	return relations.get(DiplomacyKeys.pair(a, b), null)


func has_relation(a: int, b: int) -> bool:
	return relations.has(DiplomacyKeys.pair(a, b))


## Creates a relation on first contact. Existing records are returned untouched.
func ensure_relation(a: int, b: int, at_turn: int = -1) -> DiplomacyRelation:
	if a == b:
		return null
	var found: DiplomacyRelation = relation(a, b)
	if found != null:
		return found
	var created_turn: int = turn if at_turn < 0 else at_turn
	var record: DiplomacyRelation = DiplomacyRelation.create(a, b, created_turn)
	relations[DiplomacyKeys.pair(a, b)] = record
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
	var key: String = DiplomacyKeys.directed(from_id, to_id)
	return String(overtures.get(key, DiplomacyCatalog.STAGE_NONE))


func set_overture(from_id: int, to_id: int, stage: String) -> void:
	var key: String = DiplomacyKeys.directed(from_id, to_id)
	if stage == DiplomacyCatalog.STAGE_NONE:
		overtures.erase(key)
	else:
		overtures[key] = stage


func subsidy(payer: int, target: int) -> int:
	return int(subsidies.get(DiplomacyKeys.directed(payer, target), 0))


func set_subsidy(payer: int, target: int, percent: int) -> void:
	subsidies[DiplomacyKeys.directed(payer, target)] = percent
	# Setting a subsidy is score-neutral, so it must not swallow the pair's
	# per-turn drift (wiki: diplomacy § Relation Model, skip-on-event list).
	record_event("subsidySet", payer, target, {"percent": percent})


func cancel_subsidy(payer: int, target: int) -> bool:
	var key: String = DiplomacyKeys.directed(payer, target)
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
	return int(_order_counts.get(DiplomacyKeys.claim(kind, from_id, to_id), 0)) > 0


func claim(from_id: int, to_id: int, kind: String) -> void:
	var key: String = DiplomacyKeys.claim(kind, from_id, to_id)
	_order_counts[key] = int(_order_counts.get(key, 0)) + 1


func is_modified(a: int, b: int) -> bool:
	return _modified.has(DiplomacyKeys.pair(a, b))


## Records a score-neutral event (peace, war, overture) and suppresses decay.
func touch(a: int, b: int, kind: String, data: Dictionary = {}) -> void:
	_modified[DiplomacyKeys.pair(a, b)] = true
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


func apply_decay() -> int:
	var changed: int = 0
	for record: DiplomacyRelation in relations.values():
		if record.at_war or _modified.has(DiplomacyKeys.pair(record.a, record.b)):
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


## Removes every trace of a faction absorbed by Join Empire. The sweep itself
## lives in [DiplomacyLifetime] with the rest of a court's comings and goings.
func clear_relations_of(faction: int) -> void:
	DiplomacyLifetime.absorb(self, faction)


## Diplomacy phase close: drop broken subsidies, drift relations, clear claims.
func end_turn() -> Dictionary:
	var cancelled: Array[String] = []
	for key: String in subsidies.keys():
		var pair: Vector2i = DiplomacyKeys.directed_courts(key)
		var record: DiplomacyRelation = relation(pair.x, pair.y)
		var stage: String = overture(pair.x, pair.y)
		var embassy: bool = DiplomacyCatalog.is_embassy_stage(stage)
		if record == null or record.at_war or not embassy:
			cancelled.append(key)
	for key: String in cancelled:
		var pair: Vector2i = DiplomacyKeys.directed_courts(key)
		record_event(
			"subsidyCancelled", pair.x, pair.y, {"percent": int(subsidies[key])}
		)
		subsidies.erase(key)
	# The trade-deal lift lands before the drift, so a pair that just traded is
	# event-modified and skips this turn's decay (wiki: diplomacy § Relation
	# Model — trade-deal boost, R10).
	DiplomacyTradeTerms.pay_trade_boosts(self)
	var decayed: int = apply_decay()
	# The mutual-defence snapshot is the state at the close of this turn: a
	# treaty signed next turn cannot be pulled into today's war (wiki: diplomacy).
	CallToArms.freeze_alliances(self)
	_modified.clear()
	_order_counts.clear()
	turn += 1
	return {"decayed": decayed, "subsidies_cancelled": cancelled.size()}


