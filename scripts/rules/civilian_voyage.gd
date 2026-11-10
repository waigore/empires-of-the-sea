class_name CivilianVoyage
extends RefCounted
## Civilians aboard a crown squadron (wiki: civilian-units § Overseas
## deployment; ships-and-naval § Naval transport; DR-20261109-17). Pure rules:
## the dossier, the order path and tests share one gate (REQ-P3-03).
##
## A civilian boards a squadron in port and sails as a passenger: one hull
## carries one civilian, and a squadron carrying an army carries none. Landing
## puts the civilian on a coast the fleet can reach; a landing reveals the tile
## and its orthogonal neighbours (fog-and-exploration § New World arrival).

const NO_ID: int = MapModel.NO_ID
## Types that may be put ashore on any coast; every other civilian needs crown
## land (wiki: civilian-units § Overseas deployment).
const ANY_COAST: Array[String] = ["explorer", "merchant"]


## Civilians a squadron can carry: one per hull.
static func capacity(fleet: FleetState) -> int:
	if fleet == null:
		return 0
	return fleet.ship_count()


## A civilian in the fleet's port may board when the hulls can hold it.
static func can_embark(
	model: MapModel, unit: CivilianState, fleet: FleetState
) -> Dictionary:
	if unit == null:
		return _deny("There is no civilian to embark.")
	if fleet == null:
		return _deny("No squadron waits in this port.")
	if model == null:
		return _deny("The map is not ready.")
	if unit.owner != fleet.owner:
		return _deny("Own colours only.")
	if unit.is_embarked():
		return _deny("The civilian is already aboard a squadron.")
	if unit.is_working():
		return _deny("The civilian is busy working.")
	if unit.moved:
		return _deny("This civilian has already moved this turn.")
	if not fleet.is_in_port() or not fleet.is_afloat():
		return _deny("A civilian boards a squadron in port.")
	if fleet.moved:
		return _deny("This fleet has already sailed or taken a mission this turn.")
	if fleet.embarked_army >= 0:
		return _deny("The squadron carries troops; land them before taking colonists.")
	if model.province_at(unit.tile.x, unit.tile.y) != fleet.province:
		return _deny("The fleet is not in this port.")
	if fleet.civilian_count() >= capacity(fleet):
		return _deny(
			"The squadron has %d hull%s and cannot carry another civilian."
			% [capacity(fleet), "" if capacity(fleet) == 1 else "s"]
		)
	return _allow()


## Boards the civilian: it leaves the map, spends its move, and the squadron
## carries its instance id until it lands.
static func embark(
	model: MapModel, unit: CivilianState, fleet: FleetState
) -> Dictionary:
	var check: Dictionary = can_embark(model, unit, fleet)
	if not bool(check.get("ok", false)):
		return check
	unit.embark_on(fleet.id)
	fleet.add_civilian(unit.id)
	return _allow()


## Land tiles this passenger could take this turn: the port province when the
## squadron is docked, else the coastal land bordering its sea zone.
static func landing_tiles(
	model: MapModel, unit: CivilianState, fleet: FleetState
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if model == null or unit == null or fleet == null:
		return tiles
	if not fleet.has_civilian(unit.id):
		return tiles
	if fleet.is_in_port():
		for tile: Vector2i in model.province_tiles(fleet.province):
			if _can_go_ashore(model, unit, tile):
				tiles.append(tile)
		return tiles
	var zone: SeaZoneState = model.sea_zone_data(fleet.sea_zone)
	if zone == null:
		return tiles
	for water: Vector2i in zone.tiles:
		for offset: Vector2i in CivilianMovement.NEIGHBORS:
			var tile: Vector2i = water + offset
			if not model.in_bounds(tile.x, tile.y) or not model.is_land(tile.x, tile.y):
				continue
			if tiles.has(tile):
				continue
			if _can_go_ashore(model, unit, tile):
				tiles.append(tile)
	return tiles


## Provinces with at least one landing tile, for the dossier's coast rows.
static func landing_provinces(
	model: MapModel, unit: CivilianState, fleet: FleetState
) -> Array[int]:
	var provinces: Array[int] = []
	for tile: Vector2i in landing_tiles(model, unit, fleet):
		var province: int = model.province_at(tile.x, tile.y)
		if province != NO_ID and not provinces.has(province):
			provinces.append(province)
	provinces.sort()
	return provinces


## First landing tile in a province, so a coast button needs no tile picking.
static func landing_tile_in(
	model: MapModel, unit: CivilianState, fleet: FleetState, province_id: int
) -> Vector2i:
	for tile: Vector2i in landing_tiles(model, unit, fleet):
		if model.province_at(tile.x, tile.y) == province_id:
			return tile
	return CivilianState.NO_TILE


## The civilian may go ashore here: the fleet can reach the tile and the type's
## own land-entry rule allows it (Builders stay on crown land, Explorers roam).
static func can_disembark(
	model: MapModel, unit: CivilianState, fleet: FleetState, tile: Vector2i
) -> Dictionary:
	if unit == null or fleet == null:
		return _deny("No civilian is aboard this fleet.")
	if not fleet.has_civilian(unit.id):
		return _deny("No civilian is aboard this fleet.")
	if not landing_tiles(model, unit, fleet).has(tile):
		return _deny("That coast is out of the squadron's reach.")
	return _allow()


## Puts the civilian ashore; it has spent this turn's move.
static func disembark(
	model: MapModel, unit: CivilianState, fleet: FleetState, tile: Vector2i
) -> Dictionary:
	var check: Dictionary = can_disembark(model, unit, fleet, tile)
	if not bool(check.get("ok", false)):
		return check
	unit.put_ashore(tile)
	fleet.remove_civilian(unit.id)
	return {"ok": true, "reason": "", "tile": tile}


## Landing is stricter than walking: Explorers and Merchants may land on any
## coast, while Builder, Engineer, Rail Builder and Spy need crown land — a
## purchased deed counts (wiki: civilian-units § Overseas deployment;
## DR-20261109-17). A Spy roams foreign provinces overland but cannot be put
## ashore on a coast its crown does not hold.
static func _can_go_ashore(
	model: MapModel, unit: CivilianState, tile: Vector2i
) -> bool:
	if unit.is_working():
		return false
	if ANY_COAST.has(unit.type_id):
		return CivilianMovement.may_enter(model, unit.type_id, unit.owner, tile)
	return model.owner_at(tile.x, tile.y) == unit.owner


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
