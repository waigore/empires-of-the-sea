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
	for province_id: int in provinces_by_zone(model, zone_id):
		if model.province_owner(province_id) == owner:
			provinces.append(province_id)
	return provinces


## Every province that shares a P-S edge with the sea zone, whatever its owner
## (wiki: map-topology, ships-and-naval § Missions).
static func provinces_by_zone(model: MapModel, zone_id: int) -> Array[int]:
	var provinces: Array[int] = []
	var data: SeaZoneState = model.sea_zone_data(zone_id)
	for tile: Vector2i in data.tiles if data != null else []:
		for offset: Vector2i in ORTHOGONAL:
			var province_id: int = model.province_at(tile.x + offset.x, tile.y + offset.y)
			if province_id == MapModel.NO_ID:
				continue
			if not provinces.has(province_id):
				provinces.append(province_id)
	provinces.sort()
	return provinces


static func has_harbour(model: MapModel, province_id: int) -> bool:
	var data: ProvinceState = model.province_data(province_id)
	if data == null:
		return false
	var port: Vector2i = data.port_tile if data != null else Vector2i(-1, -1)
	return port.x >= 0 and port.y >= 0


## The home fleet is the crown's squadron in port at its own capital. It never
## sails: naval move orders do not change its location (wiki: ships-and-naval
## § Home Fleet).
static func is_home_fleet(model: MapModel, fleet: FleetState) -> bool:
	if model == null or fleet == null or not fleet.is_in_port():
		return false
	var data: ProvinceState = model.province_data(fleet.province)
	return data != null and data.capital and data.owner == fleet.owner


## A sea-going fleet that docks at its own capital merges into the home fleet:
## instance ids are preserved and the sea-going fleet leaves the roster
## (wiki: ships-and-naval § Home Fleet — membership and state). Returns
## {"fleet": the home fleet, "displaced": an army the merge could not keep
## aboard (-1 when none)}, or {"fleet": null} when the docking fleet is already
## the only squadron at that port.
static func merge_into_home(
	model: MapModel, roster: Array[FleetState], fleet: FleetState
) -> Dictionary:
	if not is_home_fleet(model, fleet):
		return {"fleet": null, "displaced": -1}
	for other: FleetState in roster:
		if other == null or other == fleet or other.owner != fleet.owner:
			continue
		if not is_home_fleet(model, other):
			continue
		var displaced: int = other.merge_from(fleet)
		roster.erase(fleet)
		return {"fleet": other, "displaced": displaced}
	return {"fleet": null, "displaced": -1}


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
	if fleet == null or is_home_fleet(model, fleet):
		return []
	var zones: Array[int] = []
	if fleet.is_at_sea():
		for zone: int in MapGeo.sea_zone_neighbors(model, fleet.sea_zone):
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
	if is_home_fleet(model, fleet):
		return _deny("The home fleet cannot leave its capital port; launch a squadron instead.")
	if fleet.moved:
		return _deny("This fleet has already moved this turn.")
	if destination == FleetState.Location.AT_SEA:
		return _can_enter_zone(model, fleet, destination_id)
	return _can_dock(model, fleet, destination_id)


static func _can_enter_zone(
	model: MapModel, fleet: FleetState, zone_id: int
) -> Dictionary:
	if zone_id < 0 or model.sea_zone_data(zone_id) == null:
		return _deny("That is not a sea zone.")
	if fleet.is_at_sea():
		if zone_id == fleet.sea_zone:
			return _deny("The fleet is already in that sea zone.")
		if not MapGeo.sea_zone_neighbors(model, fleet.sea_zone).has(zone_id):
			return _deny("A fleet sails one adjacent sea zone per turn.")
		return _allow()
	if not province_sea_zones(model, fleet.province).has(zone_id):
		return _deny("That sea zone does not border the fleet's port.")
	return _allow()


static func _can_dock(
	model: MapModel, fleet: FleetState, province_id: int
) -> Dictionary:
	if province_id < 0 or model.province_data(province_id) == null:
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
	# A squadron that leaves the station gives up its landing site and mission
	# (wiki: ships-and-naval § Missions and Movement).
	fleet.clear_beachhead()
	fleet.clear_mission()
	fleet.moved = true
	return {"ok": true, "reason": "", "entered_zone": entered_zone}


static func begin_turn(fleets: Array[FleetState]) -> void:
	for fleet: FleetState in fleets:
		fleet.moved = false


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
