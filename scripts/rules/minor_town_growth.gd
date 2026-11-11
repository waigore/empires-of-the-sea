class_name MinorTownGrowth
extends RefCounted
## A deed raises a Minor or Tribe province's town (wiki: civilian-units
## § Merchant; extraction-and-improvements § Town manufacturing bonus;
## DR-20261112-01). Minors and Tribes submit no orders and build nothing, so a
## purchased tile is the only play path that develops their town: the province
## stands at min(4, 1 + deeds), where `deeds` counts every tile any Great Power
## has bought there. Development is built, not rented — a lost deed never lowers
## the town — and a Great Power's own province is untouched.

const MAX_LEVEL: int = 4


## The level a province's town stands at for a given deed count.
static func level_for_deeds(deeds: int) -> int:
	return clampi(1 + maxi(deeds, 0), 1, MAX_LEVEL)


## Tiles any Great Power has bought in this province.
static func deeds_in(model: MapModel, province: int) -> int:
	var data: ProvinceState = model.province_data(province) if model != null else null
	if data == null:
		return 0
	var deeds: int = 0
	for tile: Vector2i in data.tiles:
		if model.is_purchased_tile(tile):
			deeds += 1
	return deeds


## Raises the province's town after a deed is signed. Returns the level the town
## now stands at when this deed lifted it, else 0 (a Great Power province, or a
## town already at or above its deed level).
static func raise_on_deed(model: MapModel, province: int) -> int:
	var data: ProvinceState = _growing(model, province)
	if data == null:
		return 0
	var target: int = level_for_deeds(deeds_in(model, province))
	if target <= data.town_level():
		return 0
	data.town_development = target
	return target


## The level the province's latest deed lifted the town to, else 0. Read after
## the deed is recorded, so the turn's report can name it (RUB-P5-05).
static func raised_by_latest_deed(model: MapModel, province: int) -> int:
	var data: ProvinceState = _growing(model, province)
	if data == null:
		return 0
	var deeds: int = deeds_in(model, province)
	var target: int = level_for_deeds(deeds)
	if target <= level_for_deeds(deeds - 1):
		return 0
	if data.town_level() != target:
		return 0
	return target


## A Minor or Tribe province's record, or null when the province is a Great
## Power's (its town is its own Builder's work) or unknown.
static func _growing(model: MapModel, province: int) -> ProvinceState:
	if model == null:
		return null
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return null
	var kind: int = FactionCatalog.type_of(model.province_owner(province))
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return null
	return data
