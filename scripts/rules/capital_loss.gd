class_name CapitalLoss
extends RefCounted
## Capital loss, reassignment and terminal fall (wiki: capital-and-connectivity
## § Capital loss and reassignment; DR-20261109-02). Pure rules: no nodes, so a
## conquest resolves headless and the map only reports the record (REQ-P3-03).
##
## A faction's seat is the province it owns carrying the capital flag. When a
## rival takes that province the survivor moves its court to the best owned
## province of its original region (seaboard first, then inland, ascending id);
## a crown with no province left in that region falls and its holdings pass to
## the conqueror. Great Powers keep the capital town development rule on the
## move; Minor Nations and Tribes keep whatever their new seat already has.

const NO_ID: int = MapModel.NO_ID
## Empty tile marker, shared with the capital-choice phase.
const NO_TILE: Vector2i = CapitalChoice.NO_TILE


## Faction -> capital province id (or NO_ID) at the moment of the snapshot.
## Taken before combat so resolution never has to guess whose seat was lost.
static func snapshot(model: MapModel) -> Dictionary:
	var seats: Dictionary = {}
	if model == null:
		return seats
	for faction: int in model.faction_ids:
		seats[faction] = NO_ID
	for province: ProvinceState in model.provinces:
		if province.capital and province.owner != NO_ID:
			seats[province.owner] = province.id
	return seats


## Snapshot for every region, indexed like `world.regions`.
static func snapshot_world(world: WorldMap) -> Array:
	var regions: Array = []
	if world == null:
		return regions
	for model: MapModel in world.regions:
		regions.append(snapshot(model))
	return regions


## Owned provinces of a faction in this region, ascending id.
static func owned_provinces(model: MapModel, faction: int) -> Array[int]:
	var owned: Array[int] = []
	if model == null:
		return owned
	for province: ProvinceState in model.provinces:
		if province.owner == faction:
			owned.append(province.id)
	owned.sort()
	return owned


## The province the faction currently holds as its seat, or NO_ID.
static func seat_of(model: MapModel, faction: int) -> int:
	if model == null:
		return NO_ID
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			return province.id
	return NO_ID


## Deterministic new seat: seaboard owned provinces first, then inland, both in
## ascending province id order (wiki: § Capital loss and reassignment).
static func pick_capital_province(model: MapModel, owned: Array[int]) -> int:
	if model == null or owned.is_empty():
		return NO_ID
	var seaboard: Array[int] = []
	var inland: Array[int] = []
	for province_id: int in owned:
		var data: ProvinceState = model.province_data(province_id)
		if data == null:
			continue
		var zones: Array[int] = NavalMovement.province_sea_zones(model, province_id)
		if zones.is_empty():
			inland.append(province_id)
		else:
			seaboard.append(province_id)
	seaboard.sort()
	inland.sort()
	if not seaboard.is_empty():
		return seaboard[0]
	if not inland.is_empty():
		return inland[0]
	return NO_ID


## Seat tile for a province that was not settled by the capital-choice phase:
## the tile nearest the province centre, ties by row then column. The tile map
## has no per-province town key yet, so this stands in for `townTileKey`.
static func town_tile(province: ProvinceState) -> Vector2i:
	if province == null or province.tiles.is_empty():
		return NO_TILE
	var tiles: Array[Vector2i] = []
	tiles.assign(province.tiles)
	tiles.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var left: float = Vector2(a).distance_squared_to(province.center)
			var right: float = Vector2(b).distance_squared_to(province.center)
			if is_equal_approx(left, right):
				if a.y == b.y:
					return a.x < b.x
				return a.y < b.y
			return left < right
	)
	return tiles[0]


## Applies reassignment and reports terminal falls for one region. `before` is
## the snapshot taken before the battles that changed ownership.
static func resolve(model: MapModel, before: Dictionary) -> Dictionary:
	var reassigned: Array[Dictionary] = []
	var fallen: Array[Dictionary] = []
	if model == null:
		return {"reassigned": reassigned, "fallen": fallen}
	for raw: Variant in before.keys():
		var faction: int = int(raw)
		if seat_of(model, faction) != NO_ID:
			continue
		var lost: int = int(before.get(raw, NO_ID))
		var owned: Array[int] = owned_provinces(model, faction)
		if owned.is_empty():
			if lost != NO_ID:
				_clear_seat(model.province_data(lost))
				fallen.append({
					"faction": faction,
					"conqueror": _owner_of(model, lost),
					"lost": lost,
				})
			continue
		if lost != NO_ID:
			_clear_seat(model.province_data(lost))
		var pick: int = pick_capital_province(model, owned)
		if pick == NO_ID:
			continue
		var seat: ProvinceState = model.province_data(pick)
		seat.capital = true
		seat.capital_tile = town_tile(seat)
		if FactionCatalog.type_of(faction) == FactionCatalog.Type.GREAT_POWER:
			seat.town_development = 4
		reassigned.append({"faction": faction, "province": pick, "lost": lost})
	return {"reassigned": reassigned, "fallen": fallen}


## Resolves every region in turn, then applies each fall across the whole world
## so a colony province follows its crown out of play.
static func resolve_world(world: WorldMap, before: Array) -> Dictionary:
	var reassigned: Array[Dictionary] = []
	var fallen: Array[Dictionary] = []
	if world == null:
		return {"reassigned": reassigned, "fallen": fallen}
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var seats: Dictionary = {}
		if index < before.size() and typeof(before[index]) == TYPE_DICTIONARY:
			seats = before[index]
		else:
			continue
		var result: Dictionary = resolve(model, seats)
		for entry: Variant in result["reassigned"]:
			var row: Dictionary = entry
			row["region"] = index
			reassigned.append(row)
		for entry: Variant in result["fallen"]:
			var row: Dictionary = entry
			row["region"] = index
			fallen.append(row)
	for row: Dictionary in fallen:
		transfer_all(world, int(row["faction"]), int(row["conqueror"]))
	return {"reassigned": reassigned, "fallen": fallen}


## Hands every province of a fallen faction to its conqueror and clears the
## old seat flags; returns how many provinces changed hands.
static func transfer_all(world: WorldMap, faction: int, conqueror: int) -> int:
	if world == null or faction == NO_ID or conqueror == NO_ID:
		return 0
	var moved: int = 0
	for model: MapModel in world.regions:
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if province.owner != faction:
				continue
			province.owner = conqueror
			province.capital = false
			province.capital_tile = NO_TILE
			moved += 1
	return moved


static func _clear_seat(province: ProvinceState) -> void:
	if province == null:
		return
	province.capital = false
	province.capital_tile = NO_TILE


static func _owner_of(model: MapModel, province_id: int) -> int:
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return NO_ID
	return data.owner
