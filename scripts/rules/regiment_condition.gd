class_name RegimentCondition
extends RefCounted
## A regiment's condition in battle: health points and experience chevrons
## (wiki: combat § Strength, military-units § Stats). Health scales firepower,
## DEF is endurance, and chevrons multiply both. Health comes back at turn
## start (field depots); chevrons never fade. Pure rules, no nodes
## (REQ-P3-03).

## Durability divisor: DEF/9 is how much more a formed regiment endures.
const DEF_DIVISOR: float = 9.0
## Health a single casualty slot costs the survivors it grazes.
const HP_PER_SLOT: float = 60.0
## Field depots restore a quarter of a regiment's strength each turn.
const REST_SHARE: float = 0.25
## Auto-resolve's exchange mauls each survivor by this share of its losses.
const WOUND_SHARE: float = 0.5


static func max_health(type_id: String) -> int:
	return RegimentCatalog.max_health(type_id)


static func medal_multiplier(medals: int) -> float:
	return RegimentCatalog.medal_multiplier(medals)


static func fraction(army: ArmyState, regiment_id: String) -> float:
	if army == null or not army.regiments.has(regiment_id):
		return 1.0
	return float(army.condition_of(regiment_id)["fraction"])


## Applies up to `damage` health points; a wound never destroys a regiment on
## its own (deaths come from the casualty list), so it floors at one point.
static func wound(army: ArmyState, regiment_id: String, damage: float) -> int:
	if army == null or damage <= 0.0 or not army.regiments.has(regiment_id):
		return 0
	var data: Dictionary = army.condition_of(regiment_id)
	var before: int = int(data["hp"])
	if before <= 1:
		return 0
	var after: int = maxi(1, before - maxi(1, ceili(damage)))
	army.regiment_health[regiment_id] = after
	return before - after


## Spreads one blow's health pool over a side's deployed regiments, softened by
## each regiment's DEF. Returns the hits the plate can show (id, type, damage,
## hp, max, medals). Answer is deterministic: strongest first, ties by id.
static func damage_side(
	side: Array[ArmyState], pool: float, limit: int = 0
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if pool <= 0.0:
		return hits
	var slice: Array[Dictionary] = ArmyModifiers.deployed(side, limit)
	if slice.is_empty():
		return hits
	var share: float = pool / float(slice.size())
	for entry: Dictionary in slice:
		var army: ArmyState = entry["army"]
		var regiment_id: String = String(entry["id"])
		var type_id: String = army.type_of(regiment_id)
		var defence: float = float(RegimentCatalog.stat(type_id, "def"))
		var dealt: int = wound(
			army, regiment_id, share * DEF_DIVISOR / (DEF_DIVISOR + defence)
		)
		if dealt <= 0:
			continue
		var data: Dictionary = army.condition_of(regiment_id)
		hits.append({
			"id": regiment_id,
			"type": type_id,
			"damage": dealt,
			"hp": int(data["hp"]),
			"max": int(data["max"]),
			"medals": int(data["medals"]),
		})
	return hits


## Whole-side wear for auto-resolve: each regiment in the deployed slice loses
## `share` of its pool (reserves behind the line take none).
static func wear(side: Array[ArmyState], share: float, limit: int = 0) -> int:
	var worn: int = 0
	if share <= 0.0:
		return worn
	for entry: Dictionary in ArmyModifiers.deployed(side, limit):
		var army: ArmyState = entry["army"]
		var regiment_id: String = String(entry["id"])
		var scale: float = float(army.condition_of(regiment_id)["max"]) * share
		if wound(army, regiment_id, scale) > 0:
			worn += 1
	return worn


## Turn-start depots: `share` of each regiment's pool (a quarter in the field,
## more where a hospital stands), never past full.
static func rest(army: ArmyState, share: float = REST_SHARE) -> int:
	var healed: int = 0
	if army == null:
		return healed
	var rate: float = maxf(share, 0.0)
	for regiment_id: String in army.regiments:
		var data: Dictionary = army.condition_of(regiment_id)
		var top: int = int(data["max"])
		var hp: int = int(data["hp"])
		if hp >= top:
			continue
		army.regiment_health[regiment_id] = mini(
			top, hp + ceili(float(top) * rate)
		)
		healed += 1
	return healed


## A winning side's survivors each rise one chevron (capped at four). Returns
## how many promotions the despatch should announce.
static func award_side(side: Array[ArmyState]) -> int:
	var gained: int = 0
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			var medals: int = int(army.condition_of(regiment_id)["medals"])
			if medals >= RegimentCatalog.MAX_MEDALS:
				continue
			army.regiment_medals[regiment_id] = medals + 1
			gained += 1
	return gained


static func entries(side: Array[ArmyState]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			result.append(army.condition_of(regiment_id))
	return result


## Mean health fraction of a side (1.0 for an empty field).
static func average(side: Array[ArmyState]) -> float:
	var total: float = 0.0
	var count: int = 0
	for entry: Dictionary in entries(side):
		total += float(entry["fraction"])
		count += 1
	return total / float(count) if count > 0 else 1.0


static func mauled(side: Array[ArmyState]) -> int:
	var count: int = 0
	for entry: Dictionary in entries(side):
		if float(entry["fraction"]) < 1.0:
			count += 1
	return count


## Chevrons carried by a side, the quickest read of its experience.
static func chevrons(side: Array[ArmyState]) -> int:
	var total: int = 0
	for entry: Dictionary in entries(side):
		total += int(entry["medals"])
	return total


## Attaches the aftermath a plate and a despatch both read: every survivor's
## condition, how many were mauled, and the chevrons won (REQ-P2-03, REQ-P5-05).
static func attach(
	report: Dictionary,
	attacker_side: Array[ArmyState],
	defender_side: Array[ArmyState],
	atk_up: int,
	def_up: int
) -> void:
	report["attacker_health"] = entries(attacker_side)
	report["defender_health"] = entries(defender_side)
	report["attacker_mauled"] = mauled(attacker_side)
	report["defender_mauled"] = mauled(defender_side)
	report["attacker_chevrons"] = atk_up
	report["defender_chevrons"] = def_up
