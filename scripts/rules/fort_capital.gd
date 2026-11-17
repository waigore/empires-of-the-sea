class_name FortCapital
extends RefCounted
## An Old World capital stands behind a Wood wall from the first day, and a
## Great Power's fort tech lifts its own capital one level once
## (wiki: siege-mechanics § Fort Levels; issue #919).
##
## Two rules, both one-shot and both on the province's stored `fort_level`:
## `seed` is the start-of-campaign grant, `apply_research` the free bump at a
## tech's unlock moment. Neither is a floor the province is re-raised toward: a
## capital taken down by a siege stays down until an Engineer rebuilds it, and a
## crown that never researches the fort line keeps the wall it started with.

## Every Old World capital starts here: Wood, the level an Engineer builds first.
const START_LEVEL: int = 1
## Tech id -> the level its unlock raises the crown's own capital to, once.
const LEVELS: Dictionary = {
	"mine_engineering": 2,
	"modern_forts": 3,
}


## Gives every Old World capital province (Great Power and Minor alike) the Wood
## wall. New World and colonial capitals get nothing: a tribe's seat and a
## crown's colony are settled ground, not a walled seat. Returns how many walls
## the pass raised, for the bootstrap report.
static func seed(model: MapModel) -> int:
	if model == null or model.region_id != FactionCatalog.OLD_WORLD:
		return 0
	var raised: int = 0
	for province: ProvinceState in model.provinces:
		if not province.capital or province.fort_level >= START_LEVEL:
			continue
		province.fort_level = START_LEVEL
		raised += 1
	return raised


## The level one unlock grants, or 0 for a tech with no wall in it.
static func unlock_level(tech_id: String) -> int:
	return int(LEVELS.get(tech_id, 0))


## The free bump one research report earns: the highest level its unlocks grant,
## once, and only for a Great Power's own capital. A Minor researches the same
## forts through its own ledger and keeps the walls it built.
##
## Returns the level the capital was raised to, or 0 when nothing moved. A
## capital already at or above the unlock's level is left alone, and because the
## bump only reads the techs that finished **this** turn, a later downgrade is
## never restored by it.
static func apply_research(
	world: WorldMap, faction: int, research: Dictionary
) -> int:
	if world == null or research.is_empty():
		return 0
	if FactionCatalog.type_of(faction) != FactionCatalog.Type.GREAT_POWER:
		return 0
	var wanted: int = 0
	for raw: Variant in research.get("researched", []):
		wanted = maxi(wanted, unlock_level(String(raw)))
	if wanted <= 0:
		return 0
	var province: ProvinceState = capital(world, faction)
	if province == null or province.fort_level >= wanted:
		return 0
	province.fort_level = wanted
	return wanted


## The crown's capital in the Old World chart — the one the start grant walled.
## A court that lost its seat has no capital flag here and no free bump: its new
## seat's walls are whatever an Engineer builds.
static func capital(world: WorldMap, faction: int) -> ProvinceState:
	var model: MapModel = old_world(world)
	if model == null:
		return null
	var seat: int = WorldBootstrap.capital_province(model, faction)
	return model.province_data(seat) if seat >= 0 else null


## The Old World chart of a generated world, or null for a world without one.
static func old_world(world: WorldMap) -> MapModel:
	if world == null:
		return null
	for model: MapModel in world.regions:
		if model.region_id == FactionCatalog.OLD_WORLD:
			return model
	return null