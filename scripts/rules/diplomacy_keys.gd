class_name DiplomacyKeys
extends RefCounted
## The one spelling of a diplomacy key. A **pair** key is order-free
## (`"low:high"`) because a relation belongs to both courts; a **directed** key
## keeps its direction (`"from>to"`) because an overture, subsidy or boycott
## does not (wiki: diplomacy). The same strings are written into saves, so the
## shape is defined here once and every rules module reads it back through these
## helpers instead of splitting literals of its own (REQ-P3-01/03).


## Order-free key for a relation, pact or trade pair.
static func pair(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## The two courts a pair key names, or (-1, -1) when the key is malformed.
static func pair_courts(key: String) -> Vector2i:
	return _courts(key, ":")


## Directional key for an overture, subsidy or boycott.
static func directed(from_id: int, to_id: int) -> String:
	return "%d>%d" % [from_id, to_id]


## The two courts a directed key names, or (-1, -1) when the key is malformed.
static func directed_courts(key: String) -> Vector2i:
	return _courts(key, ">")


## Key for one order already given this turn: kind plus direction.
static func claim(kind: String, from_id: int, to_id: int) -> String:
	return "%s:%s" % [kind, directed(from_id, to_id)]


## True when a pair or directed key names `faction` on either side. Malformed
## keys name nobody, so a junk entry never matches a court.
static func touches(key: String, faction: int) -> bool:
	var courts: Vector2i = pair_courts(key)
	if courts.x < 0:
		courts = directed_courts(key)
	return courts.x == faction or courts.y == faction


static func _courts(key: String, separator: String) -> Vector2i:
	var parts: PackedStringArray = key.split(separator)
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
