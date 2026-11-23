class_name NavalExchange
extends RefCounted
## One attacker-versus-defender sea exchange (wiki: ships-and-naval § Naval
## Combat). Split from [NavalCombat] so the zone chain keeps orchestration only
## (REQ-P3-01). Strength, retreat and sink settle here; the map only animates
## the record (REQ-P3-03).


## The fleet that moved into the zone attacks; otherwise the lowest owner id
## takes the initiative (wiki: § Naval Combat attacker/defender). Patrol and
## blockade initiative lives in NavalInterception.
static func resolve(
	zone_id: int,
	attacker_id: int,
	attacking: Array,
	defender_id: int,
	defending: Array,
	fleets: Array,
	hostile: Callable,
	context: Dictionary
) -> Dictionary:
	# A hungry squadron fights at the same morale bands as a hungry army
	# (wiki: workers-and-population § Consumption — fullyFedShips / totalShips),
	# and a rival of the chosen difficulty fights its own strength
	# (wiki: ruleset-config § Difficulty).
	var attacker_strength: float = NavalCombat.side_strength(attacking) \
		* _feeding(context, attacker_id) * _difficulty(context, attacker_id) \
		* _leader(context, attacker_id)
	var defender_strength: float = NavalCombat.side_strength(defending) \
		* _feeding(context, defender_id) * _difficulty(context, defender_id) \
		* _leader(context, defender_id)
	var record: Dictionary = {
		"zone": zone_id,
		"attacker": attacker_id,
		"defender": defender_id,
		"attacker_strength": attacker_strength,
		"defender_strength": defender_strength,
		"attacker_before": NavalCombat.side_hull_count(attacking),
		"defender_before": NavalCombat.side_hull_count(defending),
		# The hulls themselves, by type, in the order they stood in the water:
		# the despatch plate stands one medallion per type (REQ-P1-08) and reads
		# them from this record rather than recomputing a side (REQ-P2-03).
		"attacker_hulls": hull_types(attacking),
		"defender_hulls": hull_types(defending),
		"attacker_lost": [],
		"defender_lost": [],
		"outcome": NavalCombat.Outcome.NONE,
		"retreat": {},
	}
	var total: float = attacker_strength + defender_strength
	if total <= 0.0:
		record["outcome"] = NavalCombat.Outcome.STALEMATE
		return record
	var share: float = attacker_strength / total
	# Wiki: share > 0.53 wins for the attacker and share < 0.47 wins for the
	# defender; the boundary itself is still a stalemate (ships-and-naval
	# § Naval Combat Resolution).
	if (
		share >= 0.5 - NavalCombat.WIN_EDGE
		and share <= 0.5 + NavalCombat.WIN_EDGE
	):
		record["outcome"] = NavalCombat.Outcome.STALEMATE
		return record
	var beaten: Array = defending
	var victor: Array = attacking
	var beaten_strength: float = defender_strength
	var outcome: int = NavalCombat.Outcome.SIDE1_VICTORY
	if share < 0.5:
		beaten = attacking
		victor = defending
		beaten_strength = attacker_strength
		outcome = NavalCombat.Outcome.SIDE2_VICTORY
	var retreat: Dictionary = _try_retreat(
		zone_id, beaten, victor, fleets, hostile, context
	)
	if not retreat.is_empty():
		retreat["beaten"] = attacker_id if share < 0.5 else defender_id
	record["retreat"] = retreat
	# A hull's name dies with it in the roster, so read every name in the water
	# first: the despatch names the hulls the court actually lost (DR-20261111-07,
	# wiki: ships-and-naval § Naval Combat Resolution — the report carries the
	# hull ids lost per side).
	var names: Dictionary = _hull_names(attacking)
	names.merge(_hull_names(defending), true)
	var beaten_lost: Array[String] = []
	if not bool(retreat.get("success", false)):
		beaten_lost = sink(beaten, INF, false)
	var victor_lost: Array[String] = sink(
		victor, beaten_strength * NavalCombat.CASUALTY_FRACTION, true
	)
	if share < 0.5:
		record["attacker_lost"] = beaten_lost
		record["defender_lost"] = victor_lost
	else:
		record["attacker_lost"] = victor_lost
		record["defender_lost"] = beaten_lost
	record["attacker_lost_names"] = _names_of(record["attacker_lost"], names)
	record["defender_lost_names"] = _names_of(record["defender_lost"], names)
	record["outcome"] = outcome
	return record


## Every hull id a side had in the water, by type id, in roster order. Read
## before any shot so a despatch can name what each colour flew.
static func hull_types(side: Array) -> Array[String]:
	var types: Array[String] = []
	for fleet: FleetState in side:
		for hull_id: String in fleet.hulls:
			types.append(fleet.type_of(hull_id))
	return types


## Spends a damage pool on whole hulls, weakest first; a hull only sinks when the
## remaining damage covers its own durability, so light damage cannot erase a
## heavy ship. With `keep_one`, the side always keeps its last hull afloat.
static func sink(side: Array, damage: float, keep_one: bool) -> Array[String]:
	var entries: Array[Dictionary] = []
	for fleet: FleetState in side:
		for hull_id: String in fleet.hulls:
			var type_id: String = fleet.type_of(hull_id)
			entries.append(
				{
					"fleet": fleet,
					"id": hull_id,
					"durability": ShipStats.durability(type_id),
				}
			)
	entries.sort_custom(_weaker_first)
	var lost: Array[String] = []
	var remaining: float = damage
	for entry: Dictionary in entries:
		if keep_one and lost.size() >= entries.size() - 1:
			break
		var durability: float = float(entry["durability"])
		if remaining < durability:
			break
		remaining -= durability
		var fleet: FleetState = entry["fleet"]
		fleet.remove_hull(String(entry["id"]))
		lost.append(String(entry["id"]))
	return lost


## The morale multiplier a crown's last rations buy; an unrecorded side (tests,
## a hand-built context) fights at full strength.
static func _feeding(context: Dictionary, owner: int) -> float:
	var feeding: Dictionary = context.get("navy_feeding", {}) as Dictionary
	return ArmyModifiers.feeding_multiplier(float(feeding.get(owner, 1.0)))


## The difficulty layer's factor for a side (wiki: ruleset-config § Difficulty):
## a rival fights the human crown at the level's percentage, folded in after the
## rations and before the share is struck. An unrecorded side fights as published.
static func _difficulty(context: Dictionary, owner: int) -> float:
	var factors: Dictionary = context.get("difficulty", {}) as Dictionary
	return float(factors.get(owner, 1.0))


## The leader's published naval row: only de Ruyter's +15% modifies a side's
## strength at sea (wiki: leader-bonuses § When Bonuses Apply). An unrecorded
## court (a hand-built fixture) reads no leader and fights as published.
static func _leader(context: Dictionary, owner: int) -> float:
	var leaders: Dictionary = context.get("leaders", {}) as Dictionary
	return LeaderCatalog.naval_multiplier(String(leaders.get(owner, "")))


## Instance id -> the name the hull flies, read before any hull leaves the roster.
static func _hull_names(side: Array) -> Dictionary:
	var names: Dictionary = {}
	for fleet: FleetState in side:
		for hull_id: String in fleet.hulls:
			names[hull_id] = ShipNames.of(fleet, hull_id)
	return names


## The names behind a loss list, in the order the resolver sank them.
static func _names_of(lost: Array, names: Dictionary) -> Array:
	var out: Array = []
	for raw_id: Variant in lost:
		var hull_id: String = String(raw_id)
		if names.has(hull_id):
			out.append(String(names[hull_id]))
	return out


## A beaten side may slip into adjacent friendly or neutral water instead of
## being routed (wiki: ships-and-naval § Naval Retreat Formula).
static func _try_retreat(
	zone_id: int,
	beaten: Array,
	victor: Array,
	fleets: Array,
	hostile: Callable,
	context: Dictionary
) -> Dictionary:
	var model: MapModel = context.get("model") as MapModel
	if model == null:
		return {}
	return NavalRetreat.attempt(
		model,
		zone_id,
		beaten,
		victor,
		fleets,
		hostile,
		int(context.get("seed", 0)),
		int(context.get("turn", 0)),
		float(context.get("retreat_roll", -1.0))
	)


static func _weaker_first(a: Dictionary, b: Dictionary) -> bool:
	var left: float = float(a["durability"])
	var right: float = float(b["durability"])
	if left == right:
		return String(a["id"]) < String(b["id"])
	return left < right
