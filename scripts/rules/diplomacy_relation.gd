class_name DiplomacyRelation
extends RefCounted
## One faction-pair relation (wiki: diplomacy § Relation Model).
## The score is a decimal in [0, 100]; the formal alliance flag is treaty state,
## distinct from the informal "Allied" relation band.

var a: int = -1
var b: int = -1
var at_war: bool = false
var score: float = DiplomacyCatalog.INITIAL_SCORE
var since_turn: int = 0
var last_interaction_turn: int = 0
var formal_alliance: bool = false


static func create(faction_a: int, faction_b: int, turn: int = 0) -> DiplomacyRelation:
	var relation := DiplomacyRelation.new()
	relation.a = mini(faction_a, faction_b)
	relation.b = maxi(faction_a, faction_b)
	relation.since_turn = turn
	relation.last_interaction_turn = turn
	return relation


func other(faction: int) -> int:
	if faction == a:
		return b
	if faction == b:
		return a
	return -1


func level() -> String:
	return DiplomacyCatalog.relation_level(score)


func meter_label() -> String:
	return DiplomacyCatalog.meter_label(score)


func set_score(value: float) -> float:
	score = clampf(value, 0.0, 100.0)
	return score


func add_score(delta: float) -> float:
	return set_score(score + delta)


## War freezes the score; the flag can never stand with war (war invariant).
func normalize() -> void:
	if at_war:
		formal_alliance = false
	score = clampf(score, 0.0, 100.0)


## Plain data for local saves (built-in types only, so str_to_var can read it).
func to_dict() -> Dictionary:
	return {
		"a": a,
		"b": b,
		"at_war": at_war,
		"score": score,
		"since_turn": since_turn,
		"last_interaction_turn": last_interaction_turn,
		"formal_alliance": formal_alliance,
	}


static func from_dict(data: Dictionary) -> DiplomacyRelation:
	var relation := DiplomacyRelation.new()
	relation.a = int(data.get("a", -1))
	relation.b = int(data.get("b", -1))
	relation.at_war = bool(data.get("at_war", false))
	relation.score = float(data.get("score", DiplomacyCatalog.INITIAL_SCORE))
	relation.since_turn = int(data.get("since_turn", 0))
	relation.last_interaction_turn = int(data.get("last_interaction_turn", 0))
	relation.formal_alliance = bool(data.get("formal_alliance", false))
	relation.normalize()
	return relation
