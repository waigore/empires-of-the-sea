class_name ImprovementSystem
extends RefCounted
## Owned estate connectivity and per-turn extraction (wiki:
## extraction-and-improvements, capital-and-connectivity).
## Pure rules state: the map layer and the estates ledger read this, never the
## other way round (REQ-P3-03).

const NEIGHBORS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Road/Town/Port connectivity for extraction. The capital tile, every built
## port and every road tile form the network; tiles on or beside it extract.
static func connected_tiles(
	model: MapModel, works: LandWorks, owner: int, capital_tile: Vector2i
) -> Dictionary:
	var connected: Dictionary = {}
	if model == null or works == null:
		return connected
	var owned: Dictionary = _owned_indices(model, owner)
	if owned.is_empty():
		return connected
	var queue: Array[Vector2i] = []
	var seeds: Array[Vector2i] = []
	if capital_tile.x >= 0 and owned.has(model.index_of(capital_tile.x, capital_tile.y)):
		seeds.append(capital_tile)
	for raw: Variant in works.ports.keys():
		var index: int = int(raw)
		if owned.has(index):
			seeds.append(tile_of(model, index))
	for seed: Vector2i in seeds:
		var index: int = model.index_of(seed.x, seed.y)
		if connected.has(index):
			continue
		connected[index] = true
		queue.append(seed)
	var head: int = 0
	while head < queue.size():
		var tile: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if not model.in_bounds(next.x, next.y):
				continue
			var next_index: int = model.index_of(next.x, next.y)
			if not owned.has(next_index) or connected.has(next_index):
				continue
			if not _has_transport(model, works, next):
				continue
			connected[next_index] = true
			queue.append(next)
	for raw: Variant in connected.keys():
		var tile: Vector2i = tile_of(model, int(raw))
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = tile + offset
			if model.in_bounds(next.x, next.y):
				var next_index: int = model.index_of(next.x, next.y)
				if owned.has(next_index):
					connected[next_index] = true
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != owner:
			continue
		var town: Vector2i = town_tile(model, works, int(province["id"]), capital_tile)
		if town.x < 0 or not connected.has(model.index_of(town.x, town.y)):
			continue
		for offset: Vector2i in NEIGHBORS:
			var next: Vector2i = town + offset
			if model.in_bounds(next.x, next.y):
				var next_index: int = model.index_of(next.x, next.y)
				if owned.has(next_index):
					connected[next_index] = true
	return connected


## The province's town is the capital tile in the capital province and a built
## port elsewhere. Without a town tile the road rule still works.
static func town_tile(
	model: MapModel, works: LandWorks, province_id: int, capital_tile: Vector2i
) -> Vector2i:
	if capital_tile.x >= 0 and model.province_at(capital_tile.x, capital_tile.y) == province_id:
		return capital_tile
	for tile: Vector2i in model.province_tiles(province_id):
		if works.has_port(model, tile):
			return tile
	return Vector2i(-1, -1)


## End-of-turn Extraction: credit every connected, prospected improvement.
static func collect(
	model: MapModel,
	works: LandWorks,
	owner: int,
	capital_tile: Vector2i,
	stockpile: Dictionary
) -> Dictionary:
	var totals: Dictionary = {}
	var report: Dictionary = {
		"totals": totals,
		"improved_tiles": 0,
		"producing_tiles": 0,
		"blocked_tiles": 0,
	}
	if model == null or works == null:
		return report
	var connected: Dictionary = connected_tiles(model, works, owner, capital_tile)
	for raw: Variant in works.improvement.keys():
		var index: int = int(raw)
		var level: int = int(works.improvement[raw])
		if level <= 0:
			continue
		var tile: Vector2i = tile_of(model, index)
		var province: int = model.province_at(tile.x, tile.y)
		if model.province_owner(province) != owner:
			continue
		var resource: int = model.resource_at(tile.x, tile.y)
		if resource < 0:
			continue
		report["improved_tiles"] = int(report["improved_tiles"]) + 1
		if not connected.has(index):
			report["blocked_tiles"] = int(report["blocked_tiles"]) + 1
			continue
		if ImprovementCatalog.needs_prospecting(resource) and not works.is_prospected(owner, model, tile):
			report["blocked_tiles"] = int(report["blocked_tiles"]) + 1
			continue
		var commodity_id: String = ImprovementCatalog.commodity(resource)
		if commodity_id.is_empty():
			continue
		totals[commodity_id] = int(totals.get(commodity_id, 0)) + ImprovementCatalog.production(level)
		report["producing_tiles"] = int(report["producing_tiles"]) + 1
	for raw: Variant in totals.keys():
		var commodity_id: String = String(raw)
		stockpile[commodity_id] = int(stockpile.get(commodity_id, 0)) + int(totals[commodity_id])
	return report


static func summary_line(report: Dictionary) -> String:
	var totals: Dictionary = report.get("totals", {})
	if totals.is_empty():
		return "The estates yield nothing — no improved tile reaches the crown."
	return "Estates yield: %s" % output_text(totals)


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


# --- helpers ----------------------------------------------------------------


static func _owned_indices(model: MapModel, owner: int) -> Dictionary:
	var owned: Dictionary = {}
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != owner:
			continue
		for tile: Vector2i in province.get("tiles", []):
			owned[model.index_of(tile.x, tile.y)] = true
	return owned


static func _has_transport(model: MapModel, works: LandWorks, tile: Vector2i) -> bool:
	return (
		works.has_port(model, tile)
		or works.transport_at(model, tile) >= LandWorks.TRANSPORT_ROAD
	)
