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
## This module orchestrates the zone chain only: one exchange lives in
## [NavalExchange], and retreat settles through [NavalRetreat].

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
## ascending zone order. Fleets lose the hulls they lose in `battle`. `context`
## carries the campaign seed, turn and region model so interception and retreat
## resolve deterministically (DR-20261109-16).
static func resolve_turn(
	fleets: Array, hostile: Callable = Callable(), context: Dictionary = {}
) -> Array[Dictionary]:
	var engagements: Array[Dictionary] = []
	for zone_id: int in contested_zones(fleets, hostile):
		engagements.append_array(_resolve_zone(zone_id, fleets, hostile, context))
	return engagements


static func _resolve_zone(
	zone_id: int, fleets: Array, hostile: Callable, context: Dictionary
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
			if owner != other and Hostility.between(hostile, owner, other):
				belligerents.append(owner)
				break
	if belligerents.size() < 2:
		return records
	var fighting: Dictionary = {}
	for owner: int in belligerents:
		fighting[owner] = sides[owner]
	var initiative: Dictionary = NavalInterception.attacker_owner(
		zone_id, fighting, hostile, context
	)
	var attacker: int = int(initiative.get("owner", belligerents[0]))
	var defender_owners: Array[int] = []
	for owner: int in belligerents:
		if owner != attacker and Hostility.between(hostile, attacker, owner):
			defender_owners.append(owner)
	for defender: int in defender_owners:
		var attacking: Array = _surviving(sides.get(attacker, []), zone_id)
		var defending: Array = _surviving(sides.get(defender, []), zone_id)
		if attacking.is_empty():
			break
		if defending.is_empty():
			continue
		var record: Dictionary = NavalExchange.resolve(
			zone_id, attacker, attacking, defender, defending, fleets, hostile, context
		)
		record["intercepted"] = bool(initiative.get("intercepted", false))
		record["interception_chance"] = float(initiative.get("chance", 0.0))
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


static func _surviving(group: Variant, zone_id: int) -> Array:
	var alive: Array = []
	for fleet: FleetState in group as Array:
		if fleet.is_afloat() and fleet.is_at_sea() and fleet.sea_zone == zone_id:
			alive.append(fleet)
	return alive


static func _any_hostile(owners: Array[int], hostile: Callable) -> bool:
	for first in owners.size():
		for second in range(first + 1, owners.size()):
			if Hostility.between(hostile, owners[first], owners[second]):
				return true
	return false


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
