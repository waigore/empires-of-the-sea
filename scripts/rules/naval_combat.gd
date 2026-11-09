class_name NavalCombat
extends RefCounted
## Sea-zone combat between fleets that end movement in the same zone
## (wiki: ships-and-naval § Naval Combat). Pure rules: deterministic, node-free,
## so a battle resolves headless and the map only animates the result
## (REQ-P3-03).
##
## Sides aggregate every fleet a faction keeps at sea in the contested zone.
## Strength and durability come from the ShipStats catalog; a side with no
## meaningful strength edge fights to a draw rather than throwing away hulls.

enum Outcome { NONE, SIDE1_VICTORY, SIDE2_VICTORY, STALEMATE }

## Strength share a side needs before the other side is considered beaten.
const WIN_EDGE: float = 0.03
## Fraction of the beaten side's strength that the victor's hulls must absorb.
const CASUALTY_FRACTION: float = 0.5


## Weighted strength of every hull across the side's fleets.
static func side_strength(fleets: Array) -> float:
	var total: float = 0.0
	for fleet: FleetState in fleets:
		for hull_id: String in fleet.hulls:
			total += ShipStats.strength(fleet.type_of(hull_id))
	return total


## Combined durability pool of the side, per hull.
static func side_durability(fleets: Array) -> float:
	var total: float = 0.0
	for fleet: FleetState in fleets:
		for hull_id: String in fleet.hulls:
			total += ShipStats.durability(fleet.type_of(hull_id))
	return total


static func side_hull_count(fleets: Array) -> int:
	var total: int = 0
	for fleet: FleetState in fleets:
		total += fleet.ship_count()
	return total


## Zones where two or more factions at war keep fleets at sea this turn.
static func contested_zones(
	fleets: Array, hostile: Callable = Callable()
) -> Array[int]:
	var zones: Array[int] = []
	for fleet: FleetState in fleets:
		if not fleet.is_at_sea() or not fleet.is_afloat():
			continue
		if zones.has(fleet.sea_zone):
			continue
		var owners: Array[int] = []
		for other: FleetState in fleets:
			if not other.is_at_sea() or not other.is_afloat():
				continue
			if other.sea_zone != fleet.sea_zone:
				continue
			if not owners.has(other.owner):
				owners.append(other.owner)
		if owners.size() >= 2 and _any_hostile(owners, hostile):
			zones.append(fleet.sea_zone)
	zones.sort()
	return zones


## Resolves every contested zone and returns one record per engagement, in
## ascending zone order. Fleets lose the hulls they lose in `battle`.
static func resolve_turn(
	fleets: Array, hostile: Callable = Callable()
) -> Array[Dictionary]:
	var engagements: Array[Dictionary] = []
	for zone_id: int in contested_zones(fleets, hostile):
		engagements.append_array(_resolve_zone(zone_id, fleets, hostile))
	return engagements


static func _resolve_zone(
	zone_id: int, fleets: Array, hostile: Callable
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var sides: Dictionary = _sides_in_zone(zone_id, fleets)
	var owners: Array[int] = []
	for raw: Variant in sides.keys():
		owners.append(int(raw))
	owners.sort()
	if owners.size() < 2:
		return records
	var belligerents: Array[int] = []
	for owner: int in owners:
		for other: int in owners:
			if owner != other and _hostile(hostile, owner, other):
				belligerents.append(owner)
				break
	if belligerents.size() < 2:
		return records
	var attacker: int = _attacker_owner(belligerents, sides)
	var defender_owners: Array[int] = []
	for owner: int in belligerents:
		if owner != attacker and _hostile(hostile, attacker, owner):
			defender_owners.append(owner)
	for defender: int in defender_owners:
		var attacking: Array = _surviving(sides.get(attacker, []))
		var defending: Array = _surviving(sides.get(defender, []))
		if attacking.is_empty():
			break
		if defending.is_empty():
			continue
		var record: Dictionary = _battle(zone_id, attacker, attacking, defender, defending)
		records.append(record)
		if int(record["outcome"]) == Outcome.STALEMATE:
			continue
	return records


## Fleets at sea in the zone grouped by owner.
static func _sides_in_zone(zone_id: int, fleets: Array) -> Dictionary:
	var sides: Dictionary = {}
	for fleet: FleetState in fleets:
		if not fleet.is_at_sea() or not fleet.is_afloat() or fleet.sea_zone != zone_id:
			continue
		if not sides.has(fleet.owner):
			sides[fleet.owner] = []
		var group: Array = sides[fleet.owner]
		group.append(fleet)
	return sides


static func _surviving(group: Variant) -> Array:
	var alive: Array = []
	for fleet: FleetState in group as Array:
		if fleet.is_afloat():
			alive.append(fleet)
	return alive


## No callback means the legacy default: every pair is hostile.
static func _hostile(hostile: Callable, a: int, b: int) -> bool:
	if a == b:
		return false
	if not hostile.is_valid():
		return true
	return bool(hostile.call(a, b))


static func _any_hostile(owners: Array[int], hostile: Callable) -> bool:
	for first in owners.size():
		for second in range(first + 1, owners.size()):
			if _hostile(hostile, owners[first], owners[second]):
				return true
	return false


## The fleet that moved into the zone attacks; otherwise the lowest owner id
## takes the initiative (wiki: § Naval Combat attacker/defender).
static func _attacker_owner(owners: Array[int], sides: Dictionary) -> int:
	var movers: Array[int] = []
	for owner: int in owners:
		for fleet: FleetState in sides[owner] as Array:
			if fleet.moved:
				movers.append(owner)
				break
	if movers.is_empty():
		return owners[0]
	movers.sort()
	return movers[0]


static func _battle(
	zone_id: int, attacker_id: int, attacking: Array, defender_id: int, defending: Array
) -> Dictionary:
	var attacker_strength: float = side_strength(attacking)
	var defender_strength: float = side_strength(defending)
	var record: Dictionary = {
		"zone": zone_id,
		"attacker": attacker_id,
		"defender": defender_id,
		"attacker_strength": attacker_strength,
		"defender_strength": defender_strength,
		"attacker_before": side_hull_count(attacking),
		"defender_before": side_hull_count(defending),
		"attacker_lost": [],
		"defender_lost": [],
		"outcome": Outcome.NONE,
	}
	var total: float = attacker_strength + defender_strength
	if total <= 0.0:
		record["outcome"] = Outcome.STALEMATE
		return record
	var share: float = attacker_strength / total
	# Wiki: share > 0.53 wins for the attacker and share < 0.47 wins for the
	# defender; the boundary itself is still a stalemate (ships-and-naval
	# § Naval Combat Resolution).
	if share >= 0.5 - WIN_EDGE and share <= 0.5 + WIN_EDGE:
		record["outcome"] = Outcome.STALEMATE
		return record
	var beaten: Array = defending
	var victor: Array = attacking
	var beaten_strength: float = defender_strength
	var outcome: int = Outcome.SIDE1_VICTORY
	if share < 0.5:
		beaten = attacking
		victor = defending
		beaten_strength = attacker_strength
		outcome = Outcome.SIDE2_VICTORY
	var beaten_lost: Array[String] = _sink(beaten, INF, false)
	var victor_lost: Array[String] = _sink(victor, beaten_strength * CASUALTY_FRACTION, true)
	if share < 0.5:
		record["attacker_lost"] = beaten_lost
		record["defender_lost"] = victor_lost
	else:
		record["attacker_lost"] = victor_lost
		record["defender_lost"] = beaten_lost
	record["outcome"] = outcome
	return record


## Spends a damage pool on whole hulls, weakest first; a hull only sinks when the
## remaining damage covers its own durability, so light damage cannot erase a
## heavy ship. With `keep_one`, the side always keeps its last hull afloat.
static func _sink(side: Array, damage: float, keep_one: bool) -> Array[String]:
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


static func _weaker_first(a: Dictionary, b: Dictionary) -> bool:
	var left: float = float(a["durability"])
	var right: float = float(b["durability"])
	if left == right:
		return String(a["id"]) < String(b["id"])
	return left < right


## Display helper shared by the HUD and tests.
static func outcome_label(outcome: int) -> String:
	match outcome:
		Outcome.SIDE1_VICTORY:
			return "attacker victory"
		Outcome.SIDE2_VICTORY:
			return "defender victory"
		Outcome.STALEMATE:
			return "stalemate"
	return "no engagement"
