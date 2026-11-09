class_name ImprovementSystem
extends RefCounted
## Owned estate connectivity and per-turn extraction (wiki:
## extraction-and-improvements, capital-and-connectivity).
## Pure rules state: the map layer and the estates ledger read this, never the
## other way round (REQ-P3-03).


## Road/Town/Port connectivity for extraction. The capital tile, every built
## port and every road tile form the network; tiles on or beside it extract.
## LandConnectivity owns the path transport detail; this wrapper keeps the
## legacy boolean set for callers that only need membership.
static func connected_tiles(
	model: MapModel, works: LandWorks, owner: int, capital_tile: Vector2i
) -> Dictionary:
	var connected: Dictionary = {}
	if model == null or works == null:
		return connected
	var resolved: Dictionary = LandConnectivity.resolve(
		model, works, owner, capital_tile
	)
	for raw: Variant in (resolved.get("tiles", {}) as Dictionary).keys():
		connected[int(raw)] = true
	return connected


## The province's town tile: the stored town (capital tile in a capital
## province; otherwise the port or centre tile). Hand-built maps without a town
## fall back to the capital tile, then a built port; else -1.
static func town_tile(
	model: MapModel, works: LandWorks, province_id: int, capital_tile: Vector2i
) -> Vector2i:
	var province: ProvinceState = model.province_data(province_id)
	if province != null and province.town_tile.x >= 0:
		return province.town_tile
	if capital_tile.x >= 0 and model.province_at(capital_tile.x, capital_tile.y) == province_id:
		return capital_tile
	for tile: Vector2i in model.province_tiles(province_id):
		if works != null and works.has_port(model, tile):
			return tile
	return Vector2i(-1, -1)


## End-of-turn Extraction is owned by `Extraction.yields`, which calls
## `connected_tiles`; this module stays the connectivity source.


static func output_text(totals: Dictionary) -> String:
	if totals.is_empty():
		return "nothing yet"
	var parts: PackedStringArray = PackedStringArray()
	var ids: Array = totals.keys()
	ids.sort()
	for raw: Variant in ids:
		var commodity_id: String = String(raw)
		var amount: int = int(totals[commodity_id])
		parts.append(
			"%d %s" % [amount, ImprovementCatalog.commodity_label(commodity_id)]
		)
	return " · ".join(parts)


static func tile_of(model: MapModel, index: int) -> Vector2i:
	var y: int = int(index / model.width)
	return Vector2i(index - y * model.width, y)


## Commodities still short of a cost row (empty when affordable).
static func short_inputs(cost: Dictionary, stockpile: Dictionary) -> Dictionary:
	var short: Dictionary = {}
	for raw: Variant in cost.keys():
		var id: String = String(raw)
		if int(stockpile.get(id, 0)) < int(cost[raw]):
			short[id] = cost[raw]
	return short
