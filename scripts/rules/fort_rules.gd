class_name FortRules
extends RefCounted
## Forts, walls and emplaced batteries (wiki: siege-mechanics, combat § Battle
## Mode, tech-tree-military § Artillery and Forts).
## Tables and maths: a province stores only `fort_level`; walls, guns and build
## gates are derived here so combat, work orders and the dossier read the same
## numbers (REQ-P3-03). The one write, `apply_build`, lands a finished build.

const MAX_LEVEL: int = 3

## Level 0 is open field. Wall HP soaks auto-resolve strength; the damage
## reduction table is the same profile applied to defender casualties.
const LEVELS: Array[Dictionary] = [
	{},
	{
		"name": "Wood",
		"guns": 1,
		"wall_hp": 10.0,
		"damage_reduction": 0.25,
		"turns": 1,
		"tech": "",
		"cost": {"lumber": 3, "bronze": 3},
	},
	{
		"name": "Stone",
		"guns": 2,
		"wall_hp": 20.0,
		"damage_reduction": 0.45,
		"turns": 2,
		"tech": "mine_engineering",
		"cost": {"lumber": 4, "bronze": 4},
	},
	{
		"name": "Modern",
		"guns": 3,
		"wall_hp": 30.0,
		"damage_reduction": 0.60,
		"turns": 3,
		"tech": "modern_forts",
		"cost": {"steel": 5, "lumber": 5},
	},
]

## Emplaced battery quality follows the researched Royal → Heavy → Siege line
## (wiki: tech-tree-military). Courts without those techs keep Royal pieces.
const EMPLACED_TECHS: Array[Dictionary] = [
	{"tech": "emplaced_siege_guns", "type": "siege_guns"},
	{"tech": "heavy_emplaced_artillery", "type": "heavy_artillery"},
]
const EMPLACED_TYPE: String = "royal_artillery"


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
