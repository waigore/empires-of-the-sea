class_name FortRules
extends RefCounted
## Forts, walls and emplaced batteries (wiki: siege-mechanics, combat § Battle
## Mode, tech-tree-military § Artillery and Forts).
## Tables and maths: a province stores only `fort_level`; walls, guns and build
## gates are derived here so combat, work orders and the dossier read the same
## numbers (REQ-P3-03). The one write, `apply_build`, lands a finished build.

const MAX_LEVEL: int = 5

## Level 0 is open field. Wall HP soaks auto-resolve strength; the damage
## reduction table is the same profile applied to defender casualties.
##
## Scaling formula (wiki: siege-mechanics § Fort Levels; issue #1314): every
## level n ≥ 1 prices its wall and its battery off one ladder —
## `wall_hp(n) = WALL_BASE * n`, `guns(n) = n`,
## `damage_reduction(n) = n / 10` (ten points of cover a level). The era
## retune keeps the shape but lifts the base: the smallest force that cracks a
## fort eats the ration share the issue fixes (150/100/70/30/50%), so each
## level's wall HP is the strength the opening Great Power host (the L1
## calibration anchor) must field above the battery before the ratio bands
## give it the province. E.g. L1 40 vs the 21-strength opening muster: the
## soaking and the single gun leave the attacker below the 1.0 band and the
## fort holds.
const WALL_BASE: float = 40.0
const REDUCTION_STEP: float = 0.1
const LEVELS: Array[Dictionary] = [
	{},
	{
		"name": "Wood",
		"guns": 1,
		"wall_hp": 40.0,
		"damage_reduction": 0.10,
		"turns": 1,
		"tech": "",
		"cost": {"lumber": 3, "bronze": 3},
	},
	{
		"name": "Stone",
		"guns": 2,
		"wall_hp": 80.0,
		"damage_reduction": 0.20,
		"turns": 2,
		"tech": "mine_engineering",
		"cost": {"lumber": 4, "bronze": 4},
	},
	{
		"name": "Modern",
		"guns": 3,
		"wall_hp": 120.0,
		"damage_reduction": 0.30,
		"turns": 3,
		"tech": "modern_forts",
		"cost": {"steel": 5, "lumber": 5},
	},
	{
		"name": "Bastion",
		"guns": 4,
		"wall_hp": 160.0,
		"damage_reduction": 0.40,
		"turns": 3,
		"tech": "bastion_forts",
		"cost": {"steel": 5, "lumber": 4, "bronze": 3},
	},
	{
		"name": "Star",
		"guns": 5,
		"wall_hp": 200.0,
		"damage_reduction": 0.50,
		"turns": 4,
		"tech": "star_forts",
		"cost": {"steel": 6, "lumber": 6},
	},
]

## Emplaced battery quality follows the researched Royal → Heavy → Siege line
## (wiki: tech-tree-military). Courts without those techs keep Royal pieces.
const EMPLACED_TECHS: Array[Dictionary] = [
	{"tech": "emplaced_siege_guns", "type": "siege_guns"},
	{"tech": "heavy_emplaced_artillery", "type": "heavy_artillery"},
]
const EMPLACED_TYPE: String = "royal_artillery"

## The top of the emplaced line (wiki: tech-tree-military § Artillery and
## Forts — Royal → Heavy → Siege). A caller that cannot see the defender's
## studies prices the wall at its strongest possible battery.
const CEILING_TECH: Dictionary = {
	"heavy_emplaced_artillery": true, "emplaced_siege_guns": true,
}


static func clamp_level(level: int) -> int:
	return clampi(level, 0, MAX_LEVEL)


static func is_siege(level: int) -> bool:
	return level >= 1


static func battle_mode(level: int) -> String:
	return "siege" if is_siege(level) else "field"


static func level_name(level: int) -> String:
	return String(_entry(level).get("name", "None"))


static func guns(level: int) -> int:
	return int(_entry(level).get("guns", 0))


static func wall_hp(level: int) -> float:
	return float(_entry(level).get("wall_hp", 0.0))


static func damage_reduction(level: int) -> float:
	return float(_entry(level).get("damage_reduction", 0.0))


static func turns(level: int) -> int:
	return int(_entry(level).get("turns", 1))


static func cost(level: int) -> Dictionary:
	return (LEVELS[clamp_level(level)].get("cost", {}) as Dictionary).duplicate()


## Owned tech id required to raise the province to `level`, or "" when free.
static func tech_gate(level: int) -> String:
	return String(_entry(level).get("tech", ""))


static func next_level(current: int) -> int:
	return mini(clamp_level(current) + 1, MAX_LEVEL)


static func level_at(model: MapModel, province: int) -> int:
	if model == null:
		return 0
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return 0
	return clamp_level(data.fort_level)


## The tile a fort is raised on: the province's town (wiki: siege-mechanics
## § Fort Levels). Capital provinces fall back to the capital tile; a legacy map
## with neither keeps the old any-land rule and returns NO_TILE.
static func site_tile(model: MapModel, province: int) -> Vector2i:
	if model == null:
		return Vector2i(-1, -1)
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return Vector2i(-1, -1)
	if data.town_tile.x >= 0:
		return data.town_tile
	if data.capital_tile.x >= 0:
		return data.capital_tile
	return Vector2i(-1, -1)


## Emplaced gun type for the defender's researched battery line.
static func emplaced_type(tech: Dictionary) -> String:
	for row: Dictionary in EMPLACED_TECHS:
		if bool(tech.get(String(row["tech"]), false)):
			return String(row["type"])
	return EMPLACED_TYPE


## Aggregate auto-resolve bonus: gun count × that type's FPN + FPM.
static func emplaced_strength(level: int, tech: Dictionary) -> float:
	return float(guns(level)) * float(RegimentCatalog.strength(emplaced_type(tech)))


## Wall HP soak: incoming strength is spent against the wall before it tells.
static func wall_soak(strength: float, level: int) -> float:
	if not is_siege(level):
		return strength
	return maxf(0.0, strength - wall_hp(level))


## The storming ladder for an empty walled province (issue #1314): the wall and
## the standing battery together are the strength a storm must beat. The
## resolver and the rival planners' storm gates read the same figure, so a
## march the gate admits the ladder can never repel — and a host under it never
## takes the ground.
static func storm_threshold(tech: Dictionary, level: int) -> float:
	return wall_hp(level) + emplaced_strength(level, tech)


## The storm's price, read off the same ladder: every whole STORM_STEP of the
## host's strength spent crossing the threshold is one regiment the storm
## loses, floored. Zero below the threshold: the wall stands.
static func storm_losses(strength: float, tech: Dictionary, level: int) -> int:
	var over: float = strength - storm_threshold(tech, level)
	if over <= 0.0:
		return 0
	return int(floor(over / STORM_STEP))


## The wall at the heaviest battery any court can mount: what a planner that
## cannot read the defender's studies must beat. The resolver prices the
## province owner's own line ([method storm_threshold] with the defender's
## tech); a gate that assumes the floor instead admits a host the ladder
## repels (wiki: siege-mechanics § Storming an empty walled province — "a thin
## host never marches on a wall it cannot beat").
static func storm_ceiling(level: int) -> float:
	return storm_threshold(CEILING_TECH, level)


## The ladder's own step: strength is soaked by the wall, then each whole
## STORM_STEP over it is one regiment the storm loses.
const STORM_STEP: float = 10.0


## Defenders behind the wall take a reduced share of their casualty band.
static func loss_scale(level: int) -> float:
	if not is_siege(level):
		return 1.0
	return 1.0 - damage_reduction(level)


## Dossier / toast wording, e.g. "Wood fort · 1 emplaced gun".
static func describe(level: int) -> String:
	if not is_siege(level):
		return "No fort"
	var pieces: int = guns(level)
	return "%s fort · %d emplaced gun%s" % [
		level_name(level), pieces, "" if pieces == 1 else "s"
	]


## The line a finished build reports: the level raised, the wall it stands
## behind and the battery it mounts. A crown that spends two turns and its
## materials learns exactly what it bought (wiki: § Fort Levels, § Emplaced
## Artillery).
static func raise_text(level: int) -> String:
	if not is_siege(level):
		return "no fort raised"
	var pieces: int = guns(level)
	return "%s fort raised · %d wall hp · %d emplaced gun%s" % [
		level_name(level).to_lower(), roundi(wall_hp(level)), pieces,
		"" if pieces == 1 else "s",
	]


## The line a finished project reports, read against the level it found. Two
## projects may run in one province, and the later completion adds no level
## (wiki: siege-mechanics § Fort Levels), so a duplicate that finishes after the
## wall already stands says so instead of claiming a raise it did not make.
static func raise_line(before: int, after: int) -> String:
	if after > before:
		return raise_text(after)
	if after <= 0:
		return "no fort stands here"
	return "no level added — the province already stands at a %s fort" % (
		level_name(after).to_lower()
	)


## Applies a finished build: the province reaches the level that project was
## ordered for, never past it. Two projects running in one province cannot
## leap a level (or the tech gate and materials that level costs).
static func apply_build(data: ProvinceState, ordered: int) -> void:
	if data == null:
		return
	var target: int = ordered if ordered > 0 else next_level(data.fort_level)
	data.fort_level = clampi(maxi(data.fort_level, target), 0, MAX_LEVEL)


static func _entry(level: int) -> Dictionary:
	return LEVELS[clamp_level(level)]
