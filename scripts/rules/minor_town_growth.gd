class_name MinorTownGrowth
extends RefCounted
## A deed raises a Minor or Tribe province's town (wiki: civilian-units
## § Merchant; extraction-and-improvements § Town manufacturing bonus;
## DR-20261112-01). Minors and Tribes never submit orders, build or research, so
## a Great Power's purchased land is the only play path that develops their
## towns: each deed the province carries lifts the town one level, capped at 4.
## Development is built, not rented, so losing a deed never lowers a town that
## has grown. Pure rules over the model (REQ-P2-03, REQ-P3-03).

## Town development tops out at 4 (wiki: civilian-units § Builder upgrade_town).
const MAX_LEVEL: int = 4


## The level a province's deeds support: the level-1 baseline plus one per deed.
static func level_for(deeds: int) -> int:
	return clampi(1 + maxi(deeds, 0), 1, MAX_LEVEL)


## Alias of `level_for` (parallel call sites / tests).
static func level_for_deeds(deeds: int) -> int:
	return level_for(deeds)


## Deeds (purchased land) held in this province by any crown.
static func deeds_in(model: MapModel, province: ProvinceState) -> int:
	if model == null or province == null:
		return 0
	var count: int = 0
	for tile: Vector2i in province.tiles:
		if model.is_purchased_tile(tile):
			count += 1
	return count


## Raises the province's town to the level its deeds support. Returns the level
## it set, or 0 when nothing moved: no deed, a province no Minor or Tribe owns,
## or a town already at or above that level.
static func apply(model: MapModel, province: ProvinceState) -> int:
	if model == null or province == null:
		return 0
	var kind: int = FactionCatalog.type_of(province.owner)
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return 0
	var level: int = level_for(deeds_in(model, province))
	if level <= province.town_level():
		return 0
	province.town_development = level
	return level


## Province-id entry for `apply` (parallel call sites).
static func raise_on_deed(model: MapModel, province: int) -> int:
	if model == null:
		return 0
	return apply(model, model.province_data(province))


## The level the province's latest deed lifted the town to, else 0. Read after
## the deed is recorded, so the turn's report can name it (RUB-P5-05).
static func raised_by_latest_deed(model: MapModel, province: int) -> int:
	if model == null:
		return 0
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return 0
	var kind: int = FactionCatalog.type_of(model.province_owner(province))
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return 0
	var deeds: int = deeds_in(model, data)
	var target: int = level_for(deeds)
	if target <= level_for(deeds - 1):
		return 0
	if data.town_level() != target:
		return 0
	return target


## The line a signed deed prints: the purchase, and the town it developed when
## the province stands at its deed level (REQ-P5-05 — never a silent change).
static func deed_line(model: MapModel, province: ProvinceState, place: String) -> String:
	var line: String = "The deed to %s is signed; the tile answers to your crown." % place
	if province == null:
		return line
	var level: int = province.town_level()
	if level >= 2 and level == level_for(deeds_in(model, province)):
		line += " The town rises to level %d." % level
	return line
