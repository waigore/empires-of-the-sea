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
## province tiles, so [method war_border] is the same border the land and
## overseas planners stage a field army on — one copy, so the war gate and the
## army can never disagree about which war is a land war (REQ-P2-03).


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


## The court's war border read in one pass: `hostile` is every at-war province
## that touches the court's own land (the ground a field army storms), and
## `staging` is every own province that touches one (where it waits before the
## storm). Both are sorted by province id, so the same state always reads the
## same border. A caller with no model or no diplomacy state reads two empty
## lists. The planners share this scan instead of each carrying a copy, so the
## war gate and the army can never disagree about which war is a land war
## (REQ-P2-03, REQ-P3-03).
static func war_border(
	model: MapModel, owner: int, state: DiplomacyState
) -> Dictionary:
	var hostile: Array[int] = []
	var staging: Array[int] = []
	if model == null or state == null:
		return {"hostile": hostile, "staging": staging}
	for province: ProvinceState in model.provinces:
		if province == null or province.owner != owner:
			continue
		var contested: bool = false
		for neighbor: int in MapGeo.province_neighbors(model, province.id):
			var other: int = model.province_owner(neighbor)
			if other == MapModel.NO_ID or other == owner:
				continue
			var record: DiplomacyRelation = state.relation(owner, other)
			if record == null or not record.at_war:
				continue
			contested = true
			if not hostile.has(neighbor):
				hostile.append(neighbor)
		if contested:
			staging.append(province.id)
	hostile.sort()
	staging.sort()
	return {"hostile": hostile, "staging": staging}
