class_name DeedTerms
extends RefCounted
## What a Merchant's deed buys, in the rules' own words (wiki: civilian-units
## § Merchant; world-market § First right of refusal; extraction-and-improvements
## § Town manufacturing bonus). The province stays its owner's and the seller
## keeps publishing the tile's harvest, so what the crown holds by a deed is the
## **first right of refusal** on those units and the **share** a rival's purchase
## pays it ([world-market-first-right-of-refusal] § Eligibility), beside the one
## town level the deed develops ([MinorTownGrowth]). Pure reads over the model
## (REQ-P2-03, REQ-P3-03); it prices nothing and moves nothing.

## The crown that holds the deed on this tile, `MapModel.NO_ID` when it is unsold.
static func holder(model: MapModel, tile: Vector2i) -> int:
	if model == null or not model.is_purchased_tile(tile):
		return MapModel.NO_ID
	return model.ownership.purchaser(model.index_of(tile.x, tile.y))


## The commodity the tile publishes on the book, "" when the seller can never
## work it — a mineral no Minor prospects, or rich ground. A deed there buys no
## unit, so only the town level is left to name.
static func commodity(model: MapModel, tile: Vector2i) -> String:
	return MinorMarket.estate_commodity(model, tile)


## The crew's order row, under the Merchant's price: the unit on the book whose
## bid fills first and the share a rival's purchase pays the crown, then the town
## level this deed develops. "" when this deed buys neither — a mineral tile in a
## province whose town already stands at the level its deeds support.
static func order_line(model: MapModel, tile: Vector2i) -> String:
	var parts: PackedStringArray = []
	var unit: String = commodity(model, tile)
	if not unit.is_empty():
		parts.append(
			(
				"your bid fills first on %d %s / turn, and a rival's buy pays "
				+ "you a share"
			)
			% [MinorMarket.PER_TILE_YIELD, ImprovementCatalog.commodity_label(unit)]
		)
	var town: String = town_clause(model, tile)
	if not town.is_empty():
		parts.append(town)
	if parts.is_empty():
		return ""
	return "Deed: " + " · ".join(parts)


## The town level this deed develops in the seller's province — the level-1
## baseline plus one per deed, capped at 4 — named only while the town still
## stands below it. A province no Minor or Tribe owns never takes the step
## ([MinorTownGrowth.apply]), so it is named for no other owner.
static func town_clause(model: MapModel, tile: Vector2i) -> String:
	if model == null:
		return ""
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null:
		return ""
	var kind: int = FactionCatalog.type_of(province.owner)
	if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
		return ""
	var deeds: int = MinorTownGrowth.deeds_in(model, province) + 1
	var level: int = MinorTownGrowth.level_for(deeds)
	if level <= province.town_level():
		return ""
	return "%s's town rises to L%d" % [FactionCatalog.name_of(province.owner), level]


## The crew's own sheet where it stands on bought ground: who signed the deed and
## what it keeps for them (REQ-P5-03, REQ-P5-05). "" when the tile is unsold.
static func held_line(model: MapModel, tile: Vector2i) -> String:
	var buyer: int = holder(model, tile)
	if buyer == MapModel.NO_ID:
		return ""
	var line: String = FactionCatalog.name_of(buyer)
	var unit: String = commodity(model, tile)
	if unit.is_empty():
		return line
	return "%s · first refusal on %d %s / turn" % [
		line, MinorMarket.PER_TILE_YIELD, ImprovementCatalog.commodity_label(unit)
	]
