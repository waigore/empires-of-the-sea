class_name AiBorderFronts
extends RefCounted
## The fronts a court's field army can actually march on (issue #995).
##
## A field army storms only a province its own frontier touches, so the wars a
## court can win are the wars on crowns whose land it borders. The bench probe
## on #995 read the shape exactly: every province the subject ever took came
## from a crown whose land touched its own at that moment, and once its wars
## were all on crowns it could not reach, its host stood still for a hundred
## turns while the footing kept those phantom fronts open.
##
## This module is the read the diplomacy pass prices that with: nothing is
## concluded here and no state is touched (REQ-P3-03). Adjacency is read off the
## province tiles, so it is the same border `AiMilitaryPlanner.frontier_hostile`
## stages a field army on — one copy, so the war gate and the army can never
## disagree about which war is a land war (REQ-P2-03).


## True when one of `attacker`'s provinces touches a province `target` owns —
## in any region, because a storm crosses a land border and nothing else. A
## caller with no world (a fixture), the same court on both sides, or an unknown
## court reads false: no border is not a border the court can march on.
static func marches_on(world: WorldMap, attacker: int, target: int) -> bool:
	if world == null or attacker < 0 or target < 0 or attacker == target:
		return false
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		if _touches(model, attacker, target):
			return true
	return false


## The pair's shared frontier: one of `attacker`'s provinces touches a province
## `target` owns.
static func _touches(model: MapModel, attacker: int, target: int) -> bool:
	for province: ProvinceState in model.provinces:
		if province.owner != attacker:
			continue
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			if model.province_owner(neighbor) == target:
				return true
	return false