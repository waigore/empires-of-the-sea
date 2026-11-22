class_name FortCapital
extends RefCounted
## Old World start walls and the Great Power's fort-tech lift (wiki:
## siege-mechanics § Fort Levels; issues #919, #1314).
##
## Start walls (#1314): every Old World **province** of a Great Power or Minor
## — seat or not — opens at **Wood (1)**; its **capital** opens at **Stone (2)**
## even before Mine Engineering. New World and colonial ground gets nothing: a
## tribe's seat and a crown's colony are settled ground, not a walled land.
##
## Three rules, all one-shot on the province's stored `fort_level`: `seed` is
## the start-of-campaign grant, `apply_research` the free bump at a tech's
## unlock moment. Neither is a floor the province is re-raised toward: a
## province taken down by a siege stays down until an Engineer rebuilds it, and
## a crown that never researches the fort line keeps the wall it started with.
##
## The bump reads the highest level its unlocks grant and only ever lifts the
## crown's **own** capital — the seat that mustered the realm's army — through
## the line: Stone with Mine Engineering, Modern with Modern Forts, Bastion
## with Bastion Forts, Star with Star Forts. Minors never receive it: their
## walls are what an Engineer builds.

## Start level of every Old World province of a walled crown (#1314).
const START_LEVEL: int = 1
## Start level of an Old World capital, seat of the realm's army (#1314).
const CAPITAL_START_LEVEL: int = 2
## Tech id -> the level its unlock raises the crown's own capital to, once.
const LEVELS: Dictionary = {
	"mine_engineering": 2,
	"modern_forts": 3,
	"bastion_forts": 4,
	"star_forts": 5,
}


## Gives every Old World province owned by a Great Power or Minor the Wood wall,
## and every Old World capital — Great Power and Minor alike — the Stone wall.
## New World and colonial provinces get nothing. Returns how many walls the
## pass raised, for the bootstrap report.
static func seed(model: MapModel) -> int:
	if model == null or model.region_id != FactionCatalog.OLD_WORLD:
		return 0
	var raised: int = 0
	for province: ProvinceState in model.provinces:
		if not _walled_owner(province.owner):
			continue
		var wanted: int = (
			CAPITAL_START_LEVEL if province.capital else START_LEVEL
		)
		if province.fort_level >= wanted:
			continue
		province.fort_level = wanted
		raised += 1
	return raised


## True for the crowns the start grant walls: any Old World Great Power or
## Minor. A tribe's ground and a colony stay open.
static func _walled_owner(faction: int) -> bool:
	var kind: int = FactionCatalog.type_of(faction)
	return kind == FactionCatalog.Type.GREAT_POWER \
		or kind == FactionCatalog.Type.MINOR_NATION


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