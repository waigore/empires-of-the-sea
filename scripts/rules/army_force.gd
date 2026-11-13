class_name ArmyForce
extends RefCounted
## A battle side's force accounting: which armies stand in a province, how many
## regiments they field, what weight they carry, and who takes the casualties.
## Split from [ArmyCombat] so the turn chain keeps orchestration only
## (REQ-P3-01). Auto-resolve, Quick Battle, the siege lanes and the AI's odds
## all read the same side numbers from here.


## Armies of one owner standing in one province.
static func armies_of(
	armies: Array[ArmyState], province: int, owner: int
) -> Array[ArmyState]:
	var result: Array[ArmyState] = []
	for army: ArmyState in armies:
		if army != null and army.province == province and army.owner == owner:
			result.append(army)
	return result


static func side_strength(side: Array[ArmyState]) -> float:
	var total: float = 0.0
	for army: ArmyState in side:
		if army != null:
			total += army.strength()
	return total


static func side_regiments(side: Array[ArmyState]) -> int:
	var total: int = 0
	for army: ArmyState in side:
		if army != null:
			total += army.count()
	return total


## Weakest-first casualties among the deployed slice; reserves take no losses.
## A colours' citations count in its rank, so a decorated regiment falls later
## (DR-20261113-04). `accept` filters the pool by type, so one siege lane can
## bleed alone.
static func apply_losses(
	armies: Array[ArmyState], side: Array[ArmyState], wanted: int,
	limit: int = 0, accept: Callable = Callable()
) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null or not armies.has(army):
			continue
		for regiment_id: String in army.regiments:
			var data: Dictionary = army.condition_of(regiment_id)
			if accept.is_valid() and not bool(accept.call(String(data["type"]))):
				continue
			candidates.append({
				"army": army,
				"id": regiment_id,
				"rank": ArmyModifiers.rank_of(
					String(data["type"]), int(data["medals"]), float(data["fraction"]),
					RegimentDecorations.strength_multiplier(army, regiment_id)
				),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["rank"]), float(b["rank"])):
			return float(a["rank"]) < float(b["rank"])
		return String(a["id"]) < String(b["id"])
	)
	var pool_start: int = 0
	if limit > 0 and candidates.size() > limit:
		pool_start = candidates.size() - limit
	var lost: Array[String] = []
	for offset in mini(maxi(wanted, 0), candidates.size() - pool_start):
		var entry: Dictionary = candidates[pool_start + offset]
		var army: ArmyState = entry["army"]
		var regiment_id: String = String(entry["id"])
		if army.remove_regiment(regiment_id):
			lost.append(regiment_id)
	return lost


## Any armed third faction blocks an unopposed capture (wiki: combat).
static func has_third_party(
	armies: Array[ArmyState], province: int, defender: int, attackers: Array[int]
) -> bool:
	for army: ArmyState in armies:
		if army == null or army.province != province or army.is_empty():
			continue
		if army.owner == defender or attackers.has(army.owner):
			continue
		return true
	return false
