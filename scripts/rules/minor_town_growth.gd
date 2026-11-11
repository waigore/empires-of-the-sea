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


## The line a signed deed prints: the purchase, and the town it developed when
## this deed is the one that raised it (REQ-P5-05 — never a silent change, and
## never a rise the province did not take). `raised` is the level the completion
## actually set, so a deed a town already meets says nothing about the town.
static func deed_line(
	model: MapModel, province: ProvinceState, place: String, raised: int = 0
) -> String:
	var line: String = "The deed to %s is signed; the tile answers to your crown." % place
	if model == null or province == null or raised < 2:
		return line
	return line + " The town rises to level %d." % raised
