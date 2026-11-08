class_name VictoryRules
extends RefCounted
## Campaign victory (wiki: victory § Current scope: military victory only).
## Pure rules over the world map — no nodes, so the check runs headless and the
## HUD only renders the record it returns (REQ-P2-03, REQ-P3-03).

## Fixed product threshold: 31 Old World provinces (not ruleset-configurable).
const MILITARY_THRESHOLD: int = 31


## Victory state at the end of `turn`. An already-set victory stays as it is,
## because the wiki makes end-of-turn evaluation idempotent.
static func resolve(current: VictoryState, world: WorldMap, turn: int) -> VictoryState:
	if current != null:
		return current
	return evaluate(world, turn)


## Military victory for the end of `turn`, or null while no Great Power holds
## enough of the Old World.
static func evaluate(world: WorldMap, turn: int) -> VictoryState:
	var winner: int = _winner(world)
	if winner == MapModel.NO_ID:
		return null
	return VictoryState.military(winner, turn)


## Old World provinces a faction owns (the only region that counts).
static func old_world_holdings(world: WorldMap, faction_id: int) -> int:
	if world == null:
		return 0
	return world.owned_provinces(WorldMap.OLD_WORLD, faction_id)


## Eligible crowns that meet the threshold, already ordered by the determinism
## rule: the lexicographically smallest player id wins a shared turn.
static func qualified(world: WorldMap) -> Array[int]:
	var ids: Array[int] = []
	if world == null:
		return ids
	for faction_id: int in world.great_powers_in(WorldMap.OLD_WORLD):
		if not FactionCatalog.can_win(faction_id):
			continue
		if old_world_holdings(world, faction_id) >= MILITARY_THRESHOLD:
			ids.append(faction_id)
	ids.sort_custom(func(a: int, b: int) -> bool: return str(a) < str(b))
	return ids


static func _winner(world: WorldMap) -> int:
	var ids: Array[int] = qualified(world)
	if ids.is_empty():
		return MapModel.NO_ID
	return ids[0]
