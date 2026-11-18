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
## The ids are the published ones: a swamp province fights on `marsh` ground.
const TERRAIN: Dictionary = {
	"open": {"label": "Open field", "volley": 1.0, "assault": 1.0, "entrench": 1.0},
	"hill": {"label": "Hillside", "volley": 0.9, "assault": 0.75, "entrench": 1.2},
	"woods": {"label": "Woods", "volley": 0.75, "assault": 0.6, "entrench": 1.3},
	"town": {"label": "Town streets", "volley": 0.7, "assault": 0.55, "entrench": 1.4},
	"marsh": {"label": "Marsh", "volley": 0.9, "assault": 0.7, "entrench": 0.8},
}


## Infantry man the wall; cavalry and artillery shelter behind it.
static func is_wall_type(type_id: String) -> bool:
	return RegimentCatalog.is_infantry(type_id)


static func wall_ids(side: Array[ArmyState]) -> Array[String]:
	return _ids_where(side, true)


static func behind_ids(side: Array[ArmyState]) -> Array[String]:
	return _ids_where(side, false)


## The garrison as it is deployed on the two lanes: the strongest `limit`
## regiments of the side, split into the infantry that man the wall and the horse
## and guns that wait behind it. A regiment past the deployment limit is the
## reserve, and a reserve stands in neither lane (wiki: combat § The line and the
## reserve; quick-battle § Wings and collapse — "the reserve is dealt nowhere").
static func line_ids(side: Array[ArmyState], limit: int) -> Dictionary:
	var lanes: Dictionary = {
		"wall": [] as Array[String],
		"behind": [] as Array[String],
	}
	for entry: Dictionary in ArmyModifiers.deployed(side, limit):
		var army: ArmyState = entry["army"]
		var regiment_id: String = String(entry["id"])
		var lane: String = "wall" if is_wall_type(army.type_of(regiment_id)) else "behind"
		(lanes[lane] as Array[String]).append(regiment_id)
	return lanes


## At least one regiment can shoot at the wall (firearms or artillery).
static func can_reach_wall(side: Array[ArmyState]) -> bool:
	for type_id: String in ArmyForce.side_types(side):
		if RegimentCatalog.stat(type_id, "rng") >= FIREARM_RNG:
			return true
	return false


## Only artillery can drop shot behind the parapet. `line` names the men the
## battle dealt when it opened: a piece held in reserve never took the field, so
## it opens no parapet (wiki: combat § The line and the reserve — "a reserve adds
## no strength"). Empty keeps the older read for a caller with no line.
static func can_reach_behind(side: Array[ArmyState], line: Array[String] = []) -> bool:
	for entry: Dictionary in _deployed(side, line):
		if RegimentCatalog.is_artillery(String(entry["type"])):
			return true
	return false


## Share of a garrison that can shoot over or at a parapet. Melee-only
## regiments cannot; they must sortie to engage (wiki: siege-mechanics
## § Quick Battle lanes).
static func return_fire_share(side: Array[ArmyState]) -> float:
	var types: Array[String] = ArmyForce.side_types(side)
	if types.is_empty():
		return 0.0
	var firing: int = 0
	for type_id: String in types:
		if RegimentCatalog.stat(type_id, "rng") >= FIREARM_RNG:
			firing += 1
	return float(firing) / float(types.size())


## The weight of a blow that can reach a wall: the deployed regiments that carry
## firearms, bows or guns (`RNG >= 2`), ranked exactly as
## [method ArmyModifiers.strength] ranks a side. A pike's weight is left out, so
## a line of melee alone weighs nothing against a parapet, its battery or its
## gates (wiki: siege-mechanics § Damage Reduction — "melee-only units cannot
## attack walls"; § Quick Battle lanes — "only regiments with RNG >= 2 can strike
## it").
##
## `line` names the men the battle dealt when it opened: the blow is weighed over
## **those** survivors, so a reserve that steps into the slice after casualties
## carries no shot to the wall (wiki: combat § The line and the reserve — "a
## reserve adds no strength"; quick-battle § Battlefield layout — "the reserve is
## dealt nowhere"). Empty keeps the older read for a caller with no line.
static func striking_weight(
	side: Array[ArmyState], limit: int, multiplier: float, line: Array[String] = []
) -> float:
	var total: float = 0.0
	## A line names its men by id, so the walk is the whole side filtered to them
	## — never the strongest `limit`, which a mauled line would drop out of.
	for entry: Dictionary in ArmyModifiers.deployed(side, 0 if not line.is_empty() else limit):
		var regiment_id: String = String(entry["id"])
		if not line.is_empty() and not line.has(regiment_id):
			continue
		var army: ArmyState = entry["army"]
		if RegimentCatalog.stat(army.type_of(regiment_id), "rng") >= FIREARM_RNG:
			total += float(entry["rank"])
	return total * multiplier


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
			return "marsh"
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
## `lanes` is the split the battle read when it opened ([method line_ids]); a
## caller that has none (a single probe blow) has the deployed line read here.
## `attacker_line` is the line the besieging side was dealt when the battle
## opened: the share that crosses the parapet is that line's own guns over the
## line's own men, so a gun held in reserve never drops shot behind a wall it
## never approached (wiki: siege-mechanics § Quick Battle lanes — "artillery /
## besieging regiments"; combat § The line and the reserve — "a reserve adds no
## strength"). Empty keeps the older read for a caller with no line.
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
	gates: Dictionary = {},
	lanes: Dictionary = {},
	attacker_line: Array[String] = []
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
	# The artillery share of the besieging line: the guns are counted over the men
	# the line was dealt, so a piece held in reserve neither opens the parapet nor
	# thins the share of the guns that did take the field (wiki: siege-mechanics
	# § Quick Battle lanes; combat § The line and the reserve).
	var artillery: int = _artillery_count(attacking, attacker_line)
	if artillery > 0 and can_reach_behind(attacking, attacker_line):
		var besiegers: int = maxi(_deployed_count(attacking, attacker_line), 1)
		behind_share = float(artillery) / float(besiegers)
	# A gate already beaten down is a way in for every arm, not just guns.
	behind_share = maxf(behind_share, breach_share(gates))
	var behind_blow: int = mini(blow, roundi(float(blow) * behind_share))
	var wall_blow: int = maxi(0, blow - behind_blow)
	## Only the deployed line stands in a lane: the wall holds the line's foot and
	## the behind lane its horse and guns, so a reserve is never a casualty
	## (wiki: combat § The line and the reserve; quick-battle § Wings and collapse).
	if lanes.is_empty():
		lanes = line_ids(defending, def_limit)
	var wall_line: Array[String] = []
	var behind_line: Array[String] = []
	wall_line.assign(lanes.get("wall", []) as Array)
	behind_line.assign(lanes.get("behind", []) as Array)
	var wall_lost: Array[String] = []
	if wall_blow > 0 and not wall_line.is_empty():
		wall_lost = ArmyForce.apply_losses(
			armies, defending, wall_blow, 0, Callable(), wall_line
		)
	# One blow bleeds no more than the deployed slice: the wall draws first and
	# the behind lane gets whatever is left of the limit, never a second helping
	# (wiki: combat § Auto-resolve casualty selection — reserves take no losses).
	var behind_left: int = -1
	if def_limit > 0:
		behind_left = maxi(def_limit - wall_lost.size(), 0)
	var behind_lost: Array[String] = []
	if behind_blow > 0 and behind_left != 0 and not behind_line.is_empty():
		var cap: int = behind_blow if behind_left < 0 else mini(behind_blow, behind_left)
		if cap > 0:
			behind_lost = ArmyForce.apply_losses(
				armies, defending, cap, 0, Callable(), behind_line
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
	for entry: Dictionary in ArmyForce.side_entries(side):
		if is_wall_type(String(entry["type"])) == on_wall:
			ids.append(String(entry["id"]))
	return ids


static func _artillery_count(side: Array[ArmyState], line: Array[String] = []) -> int:
	var count: int = 0
	for entry: Dictionary in _deployed(side, line):
		if RegimentCatalog.is_artillery(String(entry["type"])):
			count += 1
	return count


## How many men of a besieging side took the field: the line the battle dealt
## when it opened, or the whole side for a caller that dealt none.
static func _deployed_count(side: Array[ArmyState], line: Array[String]) -> int:
	return _deployed(side, line).size()


## The regiments of a side that took the field, as [method ArmyForce.side_entries]
## lists them: the ones the battle dealt into the line when `line` names it, and
## every man of the side otherwise.
static func _deployed(side: Array[ArmyState], line: Array[String]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = ArmyForce.side_entries(side)
	if line.is_empty():
		return entries
	var deployed: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if line.has(String(entry["id"])):
			deployed.append(entry)
	return deployed
