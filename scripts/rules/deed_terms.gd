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
## work it — a mineral no Minor prospects, or rich ground — and "" as well once
## the province is no longer a Minor Nation's or Tribe's. A conquest takes the
## tile out of the purchased-tile index and the seller stops offering its unit,
## so the deed keeps no first refusal there (wiki:
## world-market-first-right-of-refusal § Purchased-tile index — the
## post-conquest filter; DR-20261119-02).
static func commodity(model: MapModel, tile: Vector2i) -> String:
	if not sold_by_a_minor(model, tile):
		return ""
	return MinorMarket.estate_commodity(model, tile)


## True while the province's owner still publishes the tile's harvest: only a
## Minor Nation or a Tribe offers the book a unit, so a province a Great Power
## has taken sends nothing to the auction. One reading, shared by the unit
## clause and the town clause (wiki: world-market § Minor and tribe auto-sell;
## DR-20261119-02).
static func sold_by_a_minor(model: MapModel, tile: Vector2i) -> bool:
	if model == null:
		return false
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null:
		return false
	var kind: int = FactionCatalog.type_of(province.owner)
	return kind == FactionCatalog.Type.MINOR_NATION or kind == FactionCatalog.Type.TRIBE


## The crew's order row, under the Merchant's price: the unit on the book whose
## bid fills first and the share a rival's purchase pays the crown, then the town
## level this deed develops. "" when this deed buys neither — a mineral tile in a
## province whose town already stands at the level its deeds support — and "" on
## ground that already carries a deed, because no purchase is left to sign there
## and the row is refused: the holder's own reading is [method held_line]
## (DR-20261119-02).
static func order_line(model: MapModel, tile: Vector2i) -> String:
	if model == null or model.is_purchased_tile(tile):
		return ""
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
	if model == null or not sold_by_a_minor(model, tile):
		return ""
	var province: ProvinceState = model.province_data(model.province_at(tile.x, tile.y))
	if province == null:
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
