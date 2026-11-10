class_name SiegeLanes
extends RefCounted
## Wall lanes and the ground they stand on for a siege Quick Battle (wiki:
## siege-mechanics § Damage Reduction, § Quick Battle lanes, § Gates and
## Sortie; quick-battle § Terrain).
##
## A garrison stands in two lanes. WALL is the infantry manning the parapet;
## BEHIND is the emplaced battery and the horse held under cover. Firearms
## (RNG >= 2) and artillery can reach the wall; only artillery can reach behind
## it; melee-only regiments (RNG 1) can touch neither and must sortie to fight.
## A sortie leaves the wall, so every defender may strike that round but none
## keeps the wall's protection.
##
## Depth on top of the two lanes:
## - **Lane terrain** (OPEN / HILL / WOODS / TOWN / MARSH) comes from the
##   province's dominant ground, or from the town a fort rings. Assaults and
##   volleys are weaker into broken ground; entrenching is surer there and
##   weaker in a marsh.
## - **Gates:** a fort has three. A besieger may not pass a gate; it must beat
##   the wall down until one is breached. Each gate falls after
##   `ceil(wall HP / 3)` casualties are drawn from the wall lane, after which
##   the wall's reduction no longer shelters the garrison and the attackers
##   pour through in the share of gates lost.
## Pure data and maths: no nodes (REQ-P3-01, REQ-P3-03).

## RNG at which a regiment can shoot over or at a parapet.
const FIREARM_RNG: int = 2
## A fort has three gates; the wall is stormed through one at a time.
const GATES: int = 3

## Lane terrain: how weak a blow is into that ground, and how much surer an
## entrenchment is there (wiki: quick-battle § Core actions — entrench
## especially in HILL, WOODS, TOWN; assault weaker into WOODS, TOWN, uphill HILL).
const TERRAIN: Dictionary = {
	"open": {"label": "Open field", "volley": 1.0, "assault": 1.0, "entrench": 1.0},
	"hill": {"label": "Hillside", "volley": 0.9, "assault": 0.75, "entrench": 1.2},
	"woods": {"label": "Woods", "volley": 0.75, "assault": 0.6, "entrench": 1.3},
	"town": {"label": "Town streets", "volley": 0.7, "assault": 0.55, "entrench": 1.4},
	"swamp": {"label": "Marsh", "volley": 0.9, "assault": 0.7, "entrench": 0.8},
}


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


# --- lane terrain ------------------------------------------------------------


## The ground the battle is fought over. `override` is the playtest/simulator
## hook; a real battle passes "" and reads the province.
## A fort rings its town on open ground; broken ground keeps its own character
## (the fight is for the approaches), so HILL and WOODS sieges are possible.
static func lane_terrain(
	model: MapModel, province: int, fort: int, override: String = ""
) -> String:
	if TERRAIN.has(override):
		return override
	var dominant: int = ArmyModifiers.terrain_for(model, province)
	match dominant:
		MapModel.Terrain.HILLS, MapModel.Terrain.MOUNTAINS:
			return "hill"
		MapModel.Terrain.HARDWOOD_FOREST, MapModel.Terrain.SCRUB_FOREST:
			return "woods"
		MapModel.Terrain.SWAMP:
			return "swamp"
	if fort > 0:
		return "town"
	return "open"


static func terrain_label(terrain: String) -> String:
	return String((TERRAIN.get(terrain, TERRAIN["open"]) as Dictionary)["label"])


## How much of a volley or an assault survives the ground it is delivered into.
static func terrain_scale(action: String, terrain: String) -> float:
	if action != "volley" and action != "assault":
		return 1.0
	return float((TERRAIN.get(terrain, TERRAIN["open"]) as Dictionary)[action])


## An entrenchment is surer in cover and weaker in a marsh.
static func entrench_scale(terrain: String) -> float:
	return float((TERRAIN.get(terrain, TERRAIN["open"]) as Dictionary)["entrench"])


# --- gates and breach --------------------------------------------------------


## Fresh gate state for a siege; empty in a field battle.
static func gates_for(fort: int) -> Dictionary:
	if fort <= 0:
		return {}
	return {
		"max": GATES, "broken": 0, "damage": 0,
		"threshold": breach_threshold(fort),
	}


## Wall casualties needed to open one gate. Three gates share the wall's HP.
static func breach_threshold(fort: int) -> int:
	if fort <= 0:
		return 0
	return ceili(FortRules.wall_hp(fort) / float(GATES))


## Books wall casualties against the gates; returns how many opened this blow.
static func batter(gates: Dictionary, wall_hits: int) -> int:
	if gates.is_empty() or int(gates.get("max", 0)) <= 0 or wall_hits <= 0:
		return 0
	gates["damage"] = int(gates.get("damage", 0)) + wall_hits
	var threshold: int = int(gates.get("threshold", 0))
	var reached: int = 0 if threshold <= 0 else int(gates["damage"]) / threshold
	var before: int = int(gates.get("broken", 0))
	# A gate already down stays down; new wall damage only opens more.
	gates["broken"] = maxi(before, mini(int(gates["max"]), reached))
	return int(gates["broken"]) - before


static func breached(gates: Dictionary) -> bool:
	return int(gates.get("broken", 0)) > 0


## Share of a fort's gates standing open, 0.0 while the wall holds.
static func breach_share(gates: Dictionary) -> float:
	var maximum: int = int(gates.get("max", 0))
	if maximum <= 0:
		return 0.0
	return float(int(gates.get("broken", 0))) / float(maximum)


# --- one blow ----------------------------------------------------------------


## One attacker blow spread over the lanes. The wall takes casualties first
## (reduced by the fort's damage reduction unless the defender has sortied, and
## not at all once a gate is down); the artillery share of the besieging force
## can reach behind the wall, and a breach lets the rest pour through it.
## Returns {"wall": lost ids, "behind": lost ids, "turned": uncounted blow,
## "gates_broken": gates opened by this blow}.
static func strike(
	armies: Array[ArmyState],
	attacking: Array[ArmyState],
	defending: Array[ArmyState],
	wanted: int,
	def_limit: int,
	fort: int,
	exposed: bool,
	gates: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"wall": [] as Array[String],
		"behind": [] as Array[String],
		"turned": 0,
		"gates_broken": 0,
	}
	if wanted <= 0 or defending.is_empty():
		return result
	# Melee-only besiegers cannot attack a wall or anything inside it.
	if not can_reach_wall(attacking):
		result["turned"] = wanted
		return result
	var blow: int = wanted
	if fort > 0 and not exposed and not breached(gates):
		blow = ceili(float(wanted) * FortRules.loss_scale(fort))
	var behind_share: float = 0.0
	var artillery: int = _artillery_count(attacking)
	if artillery > 0 and can_reach_behind(attacking):
		var besiegers: int = maxi(ArmyCombat.side_regiments(attacking), 1)
		behind_share = float(artillery) / float(besiegers)
	# A gate already beaten down is a way in for every arm, not just guns.
	behind_share = maxf(behind_share, breach_share(gates))
	var behind_blow: int = mini(blow, roundi(float(blow) * behind_share))
	var wall_blow: int = maxi(0, blow - behind_blow)
	var wall_lost: Array[String] = ArmyCombat.apply_losses(
		armies, defending, wall_blow, def_limit,
		func(type_id: String) -> bool: return is_wall_type(type_id)
	)
	# One blow bleeds no more than the deployed slice: the wall draws first and
	# the behind lane gets whatever is left of the limit, never a second helping
	# (wiki: combat § Auto-resolve casualty selection — reserves take no losses).
	var behind_left: int = -1
	if def_limit > 0:
		behind_left = maxi(def_limit - wall_lost.size(), 0)
	var behind_lost: Array[String] = []
	if behind_blow > 0 and behind_left != 0:
		behind_lost = ArmyCombat.apply_losses(
			armies, defending, behind_blow, 0 if behind_left < 0 else behind_left,
			func(type_id: String) -> bool: return not is_wall_type(type_id)
		)
	result["gates_broken"] = batter(gates, wall_lost.size())
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
