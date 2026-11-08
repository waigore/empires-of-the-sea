class_name NavalMovement
extends RefCounted
## Sea-going fleet movement, docking and undocking (wiki: ships-and-naval,
## map-topology). Pure rules: callers apply the result, this module never
## touches nodes (REQ-P3-03).
##
## One fleet may make exactly one move per turn: S<->S between adjacent sea
## zones, undock from an owned port into an adjacent sea zone, or dock at an
## owned coastal province adjacent to the fleet's zone.

const ORTHOGONAL: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
]


## Sea zones sharing a P-S edge with the province.
static func province_sea_zones(model: MapModel, province_id: int) -> Array[int]:
	var zones: Array[int] = []
	for tile: Vector2i in model.province_tiles(province_id):
		for offset: Vector2i in ORTHOGONAL:
			var zone: int = model.sea_zone_at(tile.x + offset.x, tile.y + offset.y)
			if zone != MapModel.NO_ID and not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones


## Provinces of `owner` that share a P-S edge with the sea zone.
static func owned_provinces_by_zone(
	model: MapModel, zone_id: int, owner: int
) -> Array[int]:
	var provinces: Array[int] = []
	var data: Dictionary = model.sea_zone_data(zone_id)
	for tile: Vector2i in data.get("tiles", []):
		for offset: Vector2i in ORTHOGONAL:
			var province_id: int = model.province_at(tile.x + offset.x, tile.y + offset.y)
			if province_id == MapModel.NO_ID:
				continue
			if model.province_owner(province_id) != owner:
				continue
			if not provinces.has(province_id):
				provinces.append(province_id)
	provinces.sort()
	return provinces


static func has_harbour(model: MapModel, province_id: int) -> bool:
	var data: Dictionary = model.province_data(province_id)
	if data.is_empty():
		return false
	var port: Vector2i = data.get("port_tile", Vector2i(-1, -1))
	return port.x >= 0 and port.y >= 0


## Ports the fleet could dock at right now (owned, adjacent, with a harbour).
static func dockable_provinces(model: MapModel, fleet: FleetState) -> Array[int]:
	if fleet == null or not fleet.is_at_sea():
		return []
	var result: Array[int] = []
	for province_id: int in owned_provinces_by_zone(model, fleet.sea_zone, fleet.owner):
		if has_harbour(model, province_id):
			result.append(province_id)
	return result


## Sea zones the fleet could enter right now.
static func destination_zones(model: MapModel, fleet: FleetState) -> Array[int]:
	if fleet == null:
		return []
	var zones: Array[int] = []
	if fleet.is_at_sea():
		for zone: int in model.sea_zone_neighbors(fleet.sea_zone):
			zones.append(zone)
	else:
		zones = province_sea_zones(model, fleet.province)
	zones.sort()
	return zones


## Both destination lists, shaped for the map overlay and the fleet panel.
static func valid_destinations(model: MapModel, fleet: FleetState) -> Dictionary:
	return {
		"sea_zones": destination_zones(model, fleet),
		"provinces": dockable_provinces(model, fleet),
	}


## Validates an order without mutating anything.
static func can_move(
	model: MapModel, fleet: FleetState, destination: int, destination_id: int
) -> Dictionary:
	if fleet == null:
		return _deny("There is no fleet to order.")
	if fleet.moved:
		return _deny("This fleet has already moved this turn.")
	if destination == FleetState.Location.AT_SEA:
		return _can_enter_zone(model, fleet, destination_id)
	return _can_dock(model, fleet, destination_id)


static func _can_enter_zone(
	model: MapModel, fleet: FleetState, zone_id: int
) -> Dictionary:
	if zone_id < 0 or model.sea_zone_data(zone_id).is_empty():
		return _deny("That is not a sea zone.")
	if fleet.is_at_sea():
		if zone_id == fleet.sea_zone:
			return _deny("The fleet is already in that sea zone.")
		if not model.sea_zone_neighbors(fleet.sea_zone).has(zone_id):
			return _deny("A fleet sails one adjacent sea zone per turn.")
		return _allow()
	if not province_sea_zones(model, fleet.province).has(zone_id):
		return _deny("That sea zone does not border the fleet's port.")
	return _allow()


static func _can_dock(
	model: MapModel, fleet: FleetState, province_id: int
) -> Dictionary:
	if province_id < 0 or model.province_data(province_id).is_empty():
		return _deny("That is not a province.")
	if fleet.is_in_port():
		return _deny("The fleet is already in port.")
	if model.province_owner(province_id) != fleet.owner:
		return _deny("A fleet may only dock in a province it owns.")
	if not owned_provinces_by_zone(model, fleet.sea_zone, fleet.owner).has(province_id):
		return _deny("That province does not border the fleet's sea zone.")
	if not has_harbour(model, province_id):
		return _deny("That province has no harbour.")
	return _allow()


## Validates, mutates the fleet, and reports whether a zone was entered.
static func apply_move(
	model: MapModel, fleet: FleetState, destination: int, destination_id: int
) -> Dictionary:
	var check: Dictionary = can_move(model, fleet, destination, destination_id)
	if not bool(check.get("ok", false)):
		return {"ok": false, "reason": String(check.get("reason", "")), "entered_zone": -1}
	var entered_zone: int = -1
	if destination == FleetState.Location.AT_SEA:
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = destination_id
		fleet.province = MapModel.NO_ID
		entered_zone = destination_id
	else:
		fleet.location = FleetState.Location.IN_PORT
		fleet.province = destination_id
		fleet.sea_zone = MapModel.NO_ID
	fleet.moved = true
	return {"ok": true, "reason": "", "entered_zone": entered_zone}


static func begin_turn(fleets: Array[FleetState]) -> void:
	for fleet: FleetState in fleets:
		fleet.moved = false


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
