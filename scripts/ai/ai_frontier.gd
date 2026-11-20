class_name AiFrontier
extends RefCounted
## The crowns whose Old World land touches the court's own (issue #1082): a
## field army storms only a province its own frontier borders, so the war a
## conquest still needs is the war on a bordering crown — the front the army
## can walk to. The shared diplomacy pass stamps each conquest-gap court's
## frontier crowns once per turn; the buy-out and the white-peace answer read
## the stamp, so the border war outlives the `fronts` footing that settles
## every other crown war the turn after it opens. A court with no stamp — a
## frozen baseline, a fixture — keeps the published planner. Pure rules
## (REQ-P2-03, REQ-P3-03).

## The context stamp key: a per-court map of bordering Great Power ids.
const KEY: String = "frontier"


## Great Power crowns whose Old World provinces touch the court's own, sorted.
## The land the victory bar counts and a field army can march on; a caller
## with no world or no holding reads no frontier.
static func crowns(world: WorldMap, faction: int) -> Array[int]:
	var crowns: Array[int] = []
	if world == null or faction < 0:
		return crowns
	var model: MapModel = world.region(WorldMap.OLD_WORLD)
	if model == null:
		return crowns
	var borders: Dictionary = {}
	for province: ProvinceState in model.provinces:
		if province == null or province.owner != faction:
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			var other: int = model.province_owner(neighbor)
			if other < 0 or other == faction:
				continue
			if FactionCatalog.type_of(other) != FactionCatalog.Type.GREAT_POWER:
				continue
			borders[other] = true
	crowns.assign(borders.keys())
	crowns.sort()
	return crowns


## True when `target`'s land touches `faction`'s — the stamped read the shared
## planners answer from. A court with no stamp keeps the published behaviour.
static func holds(faction: int, target: int, context: Dictionary) -> bool:
	var stamped: Dictionary = context.get(KEY, {})
	if stamped.is_empty():
		return false
	var mine: Variant = stamped.get(faction, [])
	if typeof(mine) != TYPE_ARRAY:
		return false
	return (mine as Array).has(target)
