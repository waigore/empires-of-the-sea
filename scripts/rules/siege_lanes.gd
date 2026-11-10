class_name SiegeLanes
extends RefCounted
## Wall lanes for a siege Quick Battle (wiki: siege-mechanics § Damage Reduction
## (Tactical Combat), quick-battle § Emplaced fort artillery).
##
## A garrison stands in two lanes. WALL is the infantry manning the parapet;
## BEHIND is the emplaced battery and the horse held under cover. Firearms
## (RNG >= 2) and artillery can reach the wall; only artillery can reach behind
## it; melee-only regiments (RNG 1) can touch neither and must sortie to fight.
## A sortie (the defender's Assault action while garrisoned) leaves the wall, so
## every defender may strike that round but none keeps the wall's protection.
## Pure data and maths: no nodes (REQ-P3-01, REQ-P3-03).

## RNG at which a regiment can shoot over or at a parapet.
const FIREARM_RNG: int = 2


## Infantry man the wall; cavalry and artillery shelter behind it.
static func is_wall_type(type_id: String) -> bool:
	return RegimentCatalog.is_infantry(type_id)


static func wall_ids(side: Array[ArmyState]) -> Array[String]:
	return _ids_where(side, true)


static func behind_ids(side: Array[ArmyState]) -> Array[String]:
	return _ids_where(side, false)


## At least one regiment can shoot at the wall (firearms or artillery).
static func can_reach_wall(side: Array[ArmyState]) -> bool:
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if RegimentCatalog.stat(army.type_of(regiment_id), "rng") >= FIREARM_RNG:
				return true
	return false


## Only artillery can drop shot behind the parapet.
static func can_reach_behind(side: Array[ArmyState]) -> bool:
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if RegimentCatalog.is_artillery(army.type_of(regiment_id)):
				return true
	return false


## Share of a garrison that can return fire from the wall. Melee-only
## regiments cannot; they must sortie to engage (wiki: siege-mechanics).
static func return_fire_share(side: Array[ArmyState]) -> float:
	var total: int = 0
	var firing: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			total += 1
			if RegimentCatalog.stat(army.type_of(regiment_id), "rng") >= FIREARM_RNG:
				firing += 1
	if total <= 0:
		return 0.0
	return float(firing) / float(total)


## One attacker blow spread over the lanes. The wall takes casualties first
## (reduced by the fort's damage reduction unless the defender has sortied);
## the artillery share of the besieging force can reach behind the wall.
## Returns {"wall": lost ids, "behind": lost ids, "turned": uncounted blow}.
static func strike(
	armies: Array[ArmyState],
	attacking: Array[ArmyState],
	defending: Array[ArmyState],
	wanted: int,
	def_limit: int,
	fort: int,
	exposed: bool
) -> Dictionary:
	var result: Dictionary = {
		"wall": [] as Array[String],
		"behind": [] as Array[String],
		"turned": 0,
	}
	if wanted <= 0 or defending.is_empty():
		return result
	# Melee-only besiegers cannot attack a wall or anything inside it.
	if not can_reach_wall(attacking):
		result["turned"] = wanted
		return result
	var blow: int = wanted
	if fort > 0 and not exposed:
		blow = ceili(float(wanted) * FortRules.loss_scale(fort))
	var behind_blow: int = 0
	var artillery: int = _artillery_count(attacking)
	if artillery > 0 and can_reach_behind(attacking):
		var besiegers: int = maxi(ArmyCombat.side_regiments(attacking), 1)
		behind_blow = roundi(float(blow) * float(artillery) / float(besiegers))
	var wall_blow: int = maxi(0, blow - behind_blow)
	var wall_lost: Array[String] = ArmyCombat.apply_losses(
		armies, defending, wall_blow, def_limit,
		func(type_id: String) -> bool: return is_wall_type(type_id)
	)
	var behind_lost: Array[String] = ArmyCombat.apply_losses(
		armies, defending, behind_blow, def_limit,
		func(type_id: String) -> bool: return not is_wall_type(type_id)
	)
	result["wall"] = wall_lost
	result["behind"] = behind_lost
	result["turned"] = maxi(0, blow - wall_lost.size() - behind_lost.size())
	return result


## Dossier / despatch wording for the two lanes, e.g. "4 on the wall · 2 behind".
static func describe(side: Array[ArmyState]) -> String:
	var on_wall: int = wall_ids(side).size()
	var behind: int = behind_ids(side).size()
	return "%d on the wall · %d behind" % [on_wall, behind]


static func _ids_where(side: Array[ArmyState], on_wall: bool) -> Array[String]:
	var ids: Array[String] = []
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if is_wall_type(army.type_of(regiment_id)) == on_wall:
				ids.append(regiment_id)
	return ids


static func _artillery_count(side: Array[ArmyState]) -> int:
	var count: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			if RegimentCatalog.is_artillery(army.type_of(regiment_id)):
				count += 1
	return count
