class_name ArmyModifiers
extends RefCounted
## Land-combat modifiers and side strength (wiki: combat § Modifiers,
## military-generals § Medals, leader-bonuses).
## Pure maths: medal morale aura, deployment limit, feeding coverage, terrain,
## leader bonus, the difficulty layer and the deterministic "deployed" slice of
## a side. ArmyCombat owns the battle chain; this module owns the numbers it
## compares.
##
## Terrain is a two-sided modifier (wiki: resource-terrain-region-rules §
## Acceptance Criteria — the forest split prints 0.9 for the attacker and
## 1.5 / 1.1 for the defender). Broken ground slows the advance as well as
## sheltering the defence, so both sides read one province's dominant terrain.

const W_MEDAL: float = 10.0
## Initiative cavalry weight (wiki: combat § Configurable Values).
const W_CAV: float = 50.0
const MEDAL_MORALE_STEP: float = 0.05
const MEDAL_MORALE_CAP: float = 0.20
const BASE_DEPLOYMENT: int = 10
const NATIONALISM_DEPLOYMENT: int = 12

## Defender-only multiplier by province terrain.
const TERRAIN_DEFENCE: Dictionary = {
	MapModel.Terrain.PLAINS: 1.0,
	MapModel.Terrain.HARDWOOD_FOREST: 1.5,
	MapModel.Terrain.SCRUB_FOREST: 1.1,
	MapModel.Terrain.HILLS: 1.15,
	MapModel.Terrain.MOUNTAINS: 1.25,
	MapModel.Terrain.DESERT: 1.05,
	MapModel.Terrain.SWAMP: 1.1,
}

## Attacker multiplier by province terrain: a forest attack goes in at ×0.9,
## every other terrain leaves the march at 1.0 (wiki:
## resource-terrain-region-rules § Acceptance Criteria — forest split).
const TERRAIN_ATTACK: Dictionary = {
	MapModel.Terrain.HARDWOOD_FOREST: 0.9,
	MapModel.Terrain.SCRUB_FOREST: 0.9,
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


## A side's morale this turn: the feeding multiplier its coverage buys. The
## ratio bands compare the two sides' morale, so a hungry attacker's win is
## blunted (wiki: combat § Auto-resolve ratio bands).
static func morale(context: Dictionary, owner: int) -> float:
	var feeding: Dictionary = context.get("feeding", {}) as Dictionary
	return feeding_multiplier(float(feeding.get(owner, 1.0)))


static func terrain_multiplier(terrain: int) -> float:
	return float(TERRAIN_DEFENCE.get(terrain, 1.0))


## The attacker's side of the same terrain: a formed wood is slow going, so an
## advance through it fights at ×0.9 (wiki: resource-terrain-region-rules
## § Acceptance Criteria — forest split).
static func terrain_attack_multiplier(terrain: int) -> float:
	return float(TERRAIN_ATTACK.get(terrain, 1.0))


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
## first so reserves are the weakest. A regiment's rank is its (FPN + FPM)
## scaled by chevrons, by remaining health and by the weight its citations buy
## (wiki: combat § Strength; DR-20261113-04), so a mauled regiment yields its
## place to a fresh one and a decorated colours holds the line over a bare twin.
static func deployed(side: Array[ArmyState], limit: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for army: ArmyState in side:
		if army == null:
			continue
		for regiment_id: String in army.regiments:
			var data: Dictionary = army.condition_of(regiment_id)
			candidates.append({
				"army": army,
				"id": regiment_id,
				"rank": rank_of(
					String(data["type"]), int(data["medals"]), float(data["fraction"]),
					RegimentDecorations.strength_multiplier(army, regiment_id)
				),
				"medals": int(data["medals"]),
				"fraction": float(data["fraction"]),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["rank"]), float(b["rank"])):
			return float(a["rank"]) > float(b["rank"])
		return String(a["id"]) < String(b["id"])
	)
	if limit > 0 and candidates.size() > limit:
		candidates.resize(limit)
	return candidates


## One regiment's effective strength: stats × chevrons × health × the weight its
## citations buy (`decoration`, DR-20261113-04; 1.0 for a colours with none).
static func rank_of(
	type_id: String, medals: int, fraction: float, decoration: float = 1.0
) -> float:
	return (
		float(RegimentCatalog.strength(type_id))
		* RegimentCatalog.medal_multiplier(medals)
		* clampf(fraction, 0.0, 1.0)
		* maxf(decoration, 1.0)
	)


## Mean tactical weight of one deployed regiment: (FPN + FPM) × chevrons ×
## health, and the citation's weight. An action spends its share of a line as
## weight, so a veteran line absorbs more fire than a levy one (wiki:
## quick-battle § Cohesion and effective strength).
static func average_rank(side: Array[ArmyState], limit: int = 0) -> float:
	var slice: Array[Dictionary] = deployed(side, limit)
	if slice.is_empty():
		return 1.0
	var total: float = 0.0
	for entry: Dictionary in slice:
		total += float(entry["rank"])
	return total / float(slice.size())


## Σ of the deployed slice, scaled by the side multiplier.
static func strength(side: Array[ArmyState], limit: int, multiplier: float) -> float:
	var total: float = 0.0
	for entry: Dictionary in deployed(side, limit):
		total += float(entry["rank"])
	return total * multiplier


## The line and the reserve for one engagement (wiki: combat § The line and the
## reserve; DR-20261111-15). The strongest `limit` stand, the rest are spared.
static func line_fields(
	attacker: Array[ArmyState], atk_limit: int,
	defender: Array[ArmyState], def_limit: int
) -> Dictionary:
	var atk_total: int = 0
	for army: ArmyState in attacker:
		if army != null:
			atk_total += army.count()
	var def_total: int = 0
	for army: ArmyState in defender:
		if army != null:
			def_total += army.count()
	var atk_deployed: int = mini(atk_total, atk_limit)
	var def_deployed: int = mini(def_total, def_limit)
	return {
		"attacker_deployed": atk_deployed,
		"defender_deployed": def_deployed,
		"attacker_limit": atk_limit,
		"defender_limit": def_limit,
		"attacker_reserve": maxi(0, atk_total - atk_deployed),
		"defender_reserve": maxi(0, def_total - def_deployed),
	}


## Modifier bundle for one side of one engagement.
static func modifiers(
	context: Dictionary,
	medals: int,
	is_defender: bool,
	model: MapModel,
	province: int,
	owner: int
) -> Dictionary:
	var leaders: Dictionary = context.get("leaders", {}) as Dictionary
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var multiplier: float = medal_aura(medals)
	multiplier *= morale(context, owner)
	multiplier *= leader_multiplier(String(leaders.get(owner, "")))
	## Difficulty scales a rival side against the human crown (wiki: combat
	## § Modifiers; ruleset-config § Layers). No context key = published maths.
	var difficulty: Dictionary = context.get("difficulty", {}) as Dictionary
	multiplier *= float(difficulty.get(owner, 1.0))
	var terrain: int = terrain_for(model, province)
	multiplier *= (
		terrain_multiplier(terrain) if is_defender else terrain_attack_multiplier(terrain)
	)
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
