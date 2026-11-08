class_name ArmyModifiers
extends RefCounted
## Land-combat modifiers and side strength (wiki: combat § Modifiers,
## military-generals § Medals, leader-bonuses).
## Pure maths: medal morale aura, deployment limit, feeding coverage, terrain,
## leader bonus and the deterministic "deployed" slice of a side. ArmyCombat
## owns the battle chain; this module owns the numbers it compares.
##
## Terrain values are interim constants: the wiki names terrain modifiers but
## publishes no per-type numbers, so these are code-side config documented in
## docs/armies.md until a ruleset loader exists.

const W_MEDAL: float = 10.0
const MEDAL_MORALE_STEP: float = 0.05
const MEDAL_MORALE_CAP: float = 0.20
const BASE_DEPLOYMENT: int = 10
const NATIONALISM_DEPLOYMENT: int = 12

## Defender-only multiplier by province terrain.
const TERRAIN_DEFENCE: Dictionary = {
	MapModel.Terrain.PLAINS: 1.0,
	MapModel.Terrain.FOREST: 1.1,
	MapModel.Terrain.HILLS: 1.15,
	MapModel.Terrain.MOUNTAINS: 1.25,
	MapModel.Terrain.DESERT: 1.05,
	MapModel.Terrain.SWAMP: 1.1,
}

## leaderKey -> melee multiplier lives in LeaderCatalog, the roster's single
## source of truth (wiki: leader-bonuses § Bonus Table).


static func medal_aura(medals: int) -> float:
	var clamped: int = clampi(medals, 0, GeneralRoster.MAX_MEDALS)
	return 1.0 + minf(float(clamped) * MEDAL_MORALE_STEP, MEDAL_MORALE_CAP)


static func deployment_limit(medals: int, nationalism: bool) -> int:
	var base: int = NATIONALISM_DEPLOYMENT if nationalism else BASE_DEPLOYMENT
	return base + clampi(medals, 0, GeneralRoster.MAX_MEDALS)


## Coverage >= 1.0 full rations, >= 0.5 three quarters, below half rations.
static func feeding_multiplier(coverage: float) -> float:
	if coverage >= 1.0:
		return 1.0
	if coverage >= 0.5:
		return 0.75
	return 0.5


static func terrain_multiplier(terrain: int) -> float:
	return float(TERRAIN_DEFENCE.get(terrain, 1.0))


## Dominant terrain of the province; ties fall to the lower terrain id.
static func terrain_for(model: MapModel, province: int) -> int:
	var data: ProvinceState = model.province_data(province) if model != null else null
	if data == null or data.tiles.is_empty():
		return MapModel.Terrain.PLAINS
	var counts: Dictionary = {}
	for tile: Vector2i in data.tiles:
		var terrain: int = model.terrain_at(tile.x, tile.y)
		counts[terrain] = int(counts.get(terrain, 0)) + 1
	var best: int = MapModel.Terrain.PLAINS
	var best_count: int = -1
	for terrain: Variant in counts.keys():
		var id: int = int(terrain)
		var count: int = int(counts[terrain])
		if count > best_count or (count == best_count and id < best):
			best = id
			best_count = count
	return best


static func leader_multiplier(leader_key: String) -> float:
	return LeaderCatalog.multiplier_for(leader_key)


## Fallback medals when no general is available (wiki: combat § Modifiers).
static func fallback_medals(leader_key: String) -> int:
	var multiplier: float = leader_multiplier(leader_key)
	if multiplier >= 1.25:
		return 4
	if multiplier >= 1.20:
		return 3
	if multiplier >= 1.15:
		return 2
	if multiplier >= 1.10:
		return 1
	return 0


## The strongest `limit` regiments of a side (limit <= 0 means all), strongest
## first so reserves are the weakest. Casualties and strength use this slice.
static func deployed(side: Array[ArmyState], limit: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			candidates.append({
				"army": army,
				"id": regiment_id,
				"rank": RegimentCatalog.strength(army.type_of(regiment_id)),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) > int(b["rank"])
		return String(a["id"]) < String(b["id"])
	)
	if limit > 0 and candidates.size() > limit:
		candidates.resize(limit)
	return candidates


## Σ (FPN + FPM) over the deployed slice, scaled by the side multiplier.
static func strength(side: Array[ArmyState], limit: int, multiplier: float) -> float:
	var total: float = 0.0
	for entry: Dictionary in deployed(side, limit):
		total += float(entry["rank"])
	return total * multiplier


## Modifier bundle for one side of one engagement.
static func modifiers(
	context: Dictionary,
	medals: int,
	is_defender: bool,
	model: MapModel,
	province: int,
	owner: int
) -> Dictionary:
	var feeding: Dictionary = context.get("feeding", {}) as Dictionary
	var leaders: Dictionary = context.get("leaders", {}) as Dictionary
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var multiplier: float = medal_aura(medals)
	multiplier *= feeding_multiplier(float(feeding.get(owner, 1.0)))
	multiplier *= leader_multiplier(String(leaders.get(owner, "")))
	if is_defender:
		multiplier *= terrain_multiplier(terrain_for(model, province))
	var unlocked: Dictionary = tech.get(owner, {}) as Dictionary
	var nationalism: bool = bool(unlocked.get("nationalism", false))
	var fort: int = FortRules.level_at(model, province)
	return {
		"medals": clampi(medals, 0, GeneralRoster.MAX_MEDALS),
		"limit": deployment_limit(medals, nationalism),
		"multiplier": multiplier,
		"fort": fort,
		## Sides read one key each: walls spend the attacker's strength, the
		## battery adds defending strength, the wall shrinks their losses.
		"wall_hp": 0.0 if is_defender else FortRules.wall_hp(fort),
		"emplaced": FortRules.emplaced_strength(fort, unlocked) if is_defender else 0.0,
		"loss_scale": FortRules.loss_scale(fort) if is_defender else 1.0,
	}
