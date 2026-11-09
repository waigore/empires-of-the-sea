class_name CapitalLoss
extends RefCounted
## A captured capital re-seats the court or ends the crown (wiki:
## capital-and-connectivity § Capital loss and reassignment; DR-20261109-02).
## Pure rules over the world map: no nodes, so the pass runs headless
## (REQ-P3-03).
##
## The caller snapshots every owned seat before Combat, then resolves the
## snapshot after it. A crown whose seat changed hands moves to the first owned
## province in its original region (seaboard first, then inland) or falls when
## it holds no province there. Reassignment moves only the seat: the new tile is
## the province tile nearest its centre, and no ports, roads or terrain change.

const NO_ID: int = MapModel.NO_ID
const NO_TILE: Vector2i = CapitalChoice.NO_TILE


## Faction -> {region, province} for each capital province it owns now.
static func snapshot(world: WorldMap) -> Dictionary:
	var seats: Dictionary = {}
	if world == null:
		return seats
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if not province.capital or province.owner < 0:
				continue
			if seats.has(province.owner):
				continue
			seats[province.owner] = {"region": model.region_id, "province": province.id}
	return seats


## Resolves each seat that changed hands since `seats` was taken, ascending by
## faction id, and returns one record per crown that lost its capital. The
## caller removes the fallen crown's forces and reports the verdict.
static func resolve(world: WorldMap, seats: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if world == null:
		return changes
	var factions: Array[int] = []
	for raw: Variant in seats.keys():
		factions.append(int(raw))
	factions.sort()
	for faction: int in factions:
		var entry: Dictionary = seats[faction]
		var model: MapModel = world.region(int(entry.get("region", -1)))
		if model == null:
			continue
		var seat: ProvinceState = model.get_province(int(entry.get("province", NO_ID)))
		if seat == null or seat.owner == faction or seat.owner < 0:
			continue
		var conqueror: int = seat.owner
		var fallen: bool = CapitalChoice.owned_provinces(model, faction).is_empty()
		var capital: Dictionary = {} if fallen else _reassign(model, faction)
		if fallen:
			_transfer_all(world, faction, conqueror)
		_clear_seat(seat)
		changes.append({
			"faction": faction,
			"region": model.region_id,
			"lost_province": seat.id,
			"conqueror": conqueror,
			"reassigned": not fallen,
			"capital_province": int(capital.get("province_id", NO_ID)),
			"capital_tile": capital.get("tile", NO_TILE),
			"fallen": fallen,
		})
	return changes


## Moves the seat to the first owned province in the original region: seaboard
## provinces ascending by id first, then inland. The new tile is the province
## tile nearest the province centre, ties by row then column (DR-20261109-02).
static func _reassign(model: MapModel, faction: int) -> Dictionary:
	var coast: Array[int] = []
	var inland: Array[int] = []
	for province_id: int in CapitalChoice.owned_provinces(model, faction):
		if CapitalChoice.is_sea_bound(model, province_id):
			coast.append(province_id)
		else:
			inland.append(province_id)
	var ordered: Array[int] = []
	ordered.append_array(coast)
	ordered.append_array(inland)
	if ordered.is_empty():
		return {}
	var province_id: int = ordered[0]
	var province: ProvinceState = model.get_province(province_id)
	if province == null:
		return {}
	var tile: Vector2i = seat_tile(province)
	province.capital = true
	province.capital_tile = tile
	if FactionCatalog.type_of(faction) == FactionCatalog.Type.GREAT_POWER:
		province.town_development = CapitalChoice.CAPITAL_TOWN_DEVELOPMENT
	return {"province_id": province_id, "tile": tile}


## The province tile nearest the province centre; ties by row, then column.
static func seat_tile(province: ProvinceState) -> Vector2i:
	var centre := Vector2(province.center)
	var best: Vector2i = NO_TILE
	var best_distance: float = INF
	for tile: Vector2i in province.tiles:
		var distance: float = Vector2(tile).distance_squared_to(centre)
		if distance > best_distance:
			continue
		if distance == best_distance and best.x >= 0:
			if tile.y > best.y or (tile.y == best.y and tile.x > best.x):
				continue
		best = tile
		best_distance = distance
	return best


## Every holding changes colours with the fallen court, in every region; only
## `owner` changes (DR-20261109-02).
static func _transfer_all(world: WorldMap, faction: int, conqueror: int) -> int:
	var transferred: int = 0
	for model: MapModel in world.regions:
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			province.owner = conqueror
			province.capital = false
			province.capital_tile = NO_TILE
			transferred += 1
	return transferred


## The conqueror must not inherit a second palace on the captured town.
static func _clear_seat(province: ProvinceState) -> void:
	province.capital = false
	province.capital_tile = NO_TILE
