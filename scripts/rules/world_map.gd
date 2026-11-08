class_name WorldMap
extends RefCounted
## The world as one map per region plus their warp links (wiki: map-topology).
## Regions never share grid adjacency; they connect only through paired edge sea
## zones, so naval pathfinding can cross between Old and New World explicitly.

const OLD_WORLD: int = 0
const NEW_WORLD: int = 1

## Side ids used by edge_zones(), clockwise from the top.
const SIDE_NORTH: int = 0
const SIDE_EAST: int = 1
const SIDE_SOUTH: int = 2
const SIDE_WEST: int = 3

var regions: Array[MapModel] = []
## One entry per direction: {from_region, from_zone, to_region, to_zone}.
var warp_links: Array[Dictionary] = []


func add_region(model: MapModel) -> void:
	regions.append(model)


func region(index: int) -> MapModel:
	if index < 0 or index >= regions.size():
		return null
	return regions[index]


func region_count() -> int:
	return regions.size()


## Faction ids configured for a region (GPs + Minors in the Old World, Tribes in
## the New World), regardless of current ownership.
func factions_in(region_index: int) -> Array[int]:
	var model: MapModel = region(region_index)
	if model == null:
		return []
	return model.faction_ids


func great_powers_in(region_index: int) -> Array[int]:
	var ids: Array[int] = []
	for faction_id: int in factions_in(region_index):
		if FactionCatalog.type_of(faction_id) == FactionCatalog.Type.GREAT_POWER:
			ids.append(faction_id)
	return ids


func total_provinces() -> int:
	var total: int = 0
	for model: MapModel in regions:
		total += model.province_count()
	return total


func capital_province_of(region_index: int, faction_id: int) -> int:
	var model: MapModel = region(region_index)
	if model == null:
		return MapModel.NO_ID
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == faction_id and bool(province["capital"]):
			return int(province["id"])
	return MapModel.NO_ID


## Seat the faction rules from in a region: its capital, else any holding.
func seat_province(region_index: int, faction_id: int) -> int:
	var capital: int = capital_province_of(region_index, faction_id)
	if capital != MapModel.NO_ID:
		return capital
	var model: MapModel = region(region_index)
	if model == null:
		return MapModel.NO_ID
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == faction_id:
			return int(province["id"])
	return MapModel.NO_ID


## Provinces the faction currently holds in a region.
func owned_provinces(region_index: int, faction_id: int) -> int:
	var model: MapModel = region(region_index)
	if model == null:
		return 0
	var total: int = 0
	for province: Dictionary in model.provinces:
		if int(province["owner"]) == faction_id:
			total += 1
	return total


## Region/zone a warp zone leads to, or an empty dictionary when the zone is
## ordinary water.
func warp_partner(region_index: int, zone_id: int) -> Dictionary:
	for link: Dictionary in warp_links:
		if (
			int(link["from_region"]) == region_index
			and int(link["from_zone"]) == zone_id
		):
			return link
	return {}


func is_warp_zone(region_index: int, zone_id: int) -> bool:
	return not warp_partner(region_index, zone_id).is_empty()


func warp_zones(region_index: int) -> Array[int]:
	var zones: Array[int] = []
	for link: Dictionary in warp_links:
		if int(link["from_region"]) != region_index:
			continue
		var zone: int = int(link["from_zone"])
		if not zones.has(zone):
			zones.append(zone)
	zones.sort()
	return zones


## Pairs one edge sea zone per side between two maps. Each link is stored in both
## directions so either map can resolve the crossing (wiki: warp zones).
static func pair_warp_zones(region_models: Array[MapModel]) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	if region_models.size() < 2:
		return links
	var first: MapModel = region_models[0]
	var second: MapModel = region_models[1]
	var first_edges: Array[int] = edge_zones(first)
	var second_edges: Array[int] = edge_zones(second)
	for side in 4:
		var from_zone: int = first_edges[side]
		var to_zone: int = second_edges[side]
		if from_zone == MapModel.NO_ID or to_zone == MapModel.NO_ID:
			continue
		links.append({
			"from_region": 0,
			"from_zone": from_zone,
			"to_region": 1,
			"to_zone": to_zone,
		})
		links.append({
			"from_region": 1,
			"from_zone": to_zone,
			"to_region": 0,
			"to_zone": from_zone,
		})
	return links


## Largest sea zone touching each side of one map (ties go to the lowest id).
static func edge_zones(model: MapModel) -> Array[int]:
	var zones: Array[int] = [
		MapModel.NO_ID, MapModel.NO_ID, MapModel.NO_ID, MapModel.NO_ID
	]
	var tallies: Array[Dictionary] = [{}, {}, {}, {}]
	for y in model.height:
		for x in model.width:
			if not model.is_sea(x, y):
				continue
			var zone: int = model.sea_zone_at(x, y)
			if zone == MapModel.NO_ID:
				continue
			if y == 0:
				_count_tile(tallies[SIDE_NORTH], zone)
			if x == model.width - 1:
				_count_tile(tallies[SIDE_EAST], zone)
			if y == model.height - 1:
				_count_tile(tallies[SIDE_SOUTH], zone)
			if x == 0:
				_count_tile(tallies[SIDE_WEST], zone)
	for side in 4:
		var best: int = MapModel.NO_ID
		var best_count: int = 0
		var keys: Array = tallies[side].keys()
		keys.sort()
		for zone: int in keys:
			var count: int = int(tallies[side][zone])
			if count > best_count:
				best_count = count
				best = zone
		zones[side] = best
	return zones


static func _count_tile(tally: Dictionary, zone: int) -> void:
	tally[zone] = int(tally.get(zone, 0)) + 1
