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


## The strength a battle would read for this side: every regiment's rank, the
## one `(FPN + FPM) x chevrons x health x colours` aggregation the resolver
## compares ([method ArmyModifiers.strength] over the whole side). A cited or
## laurelled colours holds its place at +5% / +10% (wiki: combat § Strength;
## DR-20261113-04), so a sheet that reads this cannot name a figure the battle
## would not pay (wiki: military-armies § The muster roll — "Both strengths are
## the resolver's own aggregation"). [method ArmyState.strength] stays the paper
## sum the published power score and the docket read (wiki: diplomacy § Great
## Power power score).
static func side_strength(side: Array[ArmyState]) -> float:
	return ArmyModifiers.strength(side, 0, 1.0)


static func side_regiments(side: Array[ArmyState]) -> int:
	var total: int = 0
	for army: ArmyState in side:
		if army != null:
			total += army.count()
	return total


## Weakest-first casualties among the deployed slice; reserves take no losses.
## A colours' citations count in its rank, so a decorated regiment falls later
## (DR-20261113-04). `accept` filters the pool by type, so one siege lane can
## bleed alone; `only` names the regiments a wing holds, so one wing can
## (wiki: quick-battle § Wings and collapse).
##
## The deployment slice is read over the whole side **before** either filter
## tells: the `limit` strongest regiments are the line, and `accept` / `only`
## choose among them. Filtering first would hand a lane the strongest men of its
## own type and let a regiment held in reserve fall while a weaker one in the
## line stands (wiki: combat § The line and the reserve — reserves take no
## casualties, and casualties are drawn weakest-first from the line).
static func apply_losses(
	armies: Array[ArmyState], side: Array[ArmyState], wanted: int,
	limit: int = 0, accept: Callable = Callable(), only: Array[String] = []
) -> Array[String]:
	var candidates: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null or not armies.has(army):
			continue
		for regiment_id: String in army.regiments:
			var data: Dictionary = army.condition_of(regiment_id)
			candidates.append({
				"army": army,
				"id": regiment_id,
				"type": String(data["type"]),
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
	## The line is the one [ArmyModifiers.deployed] names — the strongest `limit`
	## with its ascending-id tie-break — so a casualty list and the plate's line
	## can never disagree about which men stand in it.
	var line: Dictionary = {}
	if limit > 0:
		for entry: Dictionary in ArmyModifiers.deployed(side, limit):
			line[String(entry["id"])] = true
	var lost: Array[String] = []
	var draws: int = maxi(wanted, 0)
	for entry: Dictionary in candidates:
		if lost.size() >= draws:
			break
		var regiment_id: String = String(entry["id"])
		if limit > 0 and not line.has(regiment_id):
			continue
		if accept.is_valid() and not bool(accept.call(String(entry["type"]))):
			continue
		if not only.is_empty() and not only.has(regiment_id):
			continue
		var army: ArmyState = entry["army"]
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
