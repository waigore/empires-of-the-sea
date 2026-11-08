class_name ShipLayer
extends Node2D
## Owns fleet markers and applies naval orders. Rules outcomes come from
## NavalMovement; this layer only animates them and reports zone entries so
## exploration can reveal the map (wiki: ships-and-naval).

signal zone_entered(zone_id: int, ship: Ship)
signal ship_selected(ship: Ship)
signal fleet_moved(fleet: FleetState, result: Dictionary)

const TILE_SIZE: float = 22.0
const PLAYER_FLEETS: int = 3
## Starting squadrons, cycling by fleet index (wiki: ships-and-naval roster).
const HULL_SETS: Array[Array] = [
	["carrack", "carrack", "sloop"],
	["carrack", "fluyte"],
	["galleon", "carrack", "fluyte"],
	["sloop", "carrack"],
	["carrack", "carrack"],
	["frigate", "carrack"],
	["fluyte", "fluyte"],
]

var model: MapModel = null
var fleets: Array[FleetState] = []
var ships: Array[Ship] = []
var selected_ship: Ship = null

var _rng := RandomNumberGenerator.new()
var _zoom: float = 1.0
var _next_hull: int = 1


func spawn(p_model: MapModel, count: int, seed_value: int, player_capital: int) -> void:
	model = p_model
	_rng.seed = seed_value
	for ship: Ship in ships:
		ship.queue_free()
	ships.clear()
	fleets.clear()
	selected_ship = null
	_next_hull = 1
	if model.sea_zone_count() == 0:
		return
	for index in count:
		var owner: int = _owner_for_index(index, count)
		var fleet: FleetState = _make_fleet(index, owner, player_capital)
		_assign_hulls(fleet, index)
		fleets.append(fleet)
		var ship := Ship.new()
		ship.fleet_id = fleet.id
		ship.faction = fleet.owner
		ship.bob_phase = _rng.randf() * TAU
		ship.speed = 26.0 + _rng.randf() * 16.0
		_place_ship(ship, fleet)
		add_child(ship)
		ships.append(ship)


static func _owner_for_index(index: int, count: int) -> int:
	var player_count: int = mini(PLAYER_FLEETS, count)
	if index < player_count:
		return 0
	return 1 + (index - player_count) % 3


func _make_fleet(id: int, owner: int, player_capital: int) -> FleetState:
	if owner == 0 and id == 2:
		var port: int = _player_port(player_capital)
		if port >= 0:
			return FleetState.in_port(id, owner, port)
	var zones: Array[int] = _coastal_zones(owner)
	if zones.is_empty():
		for zone: Dictionary in model.sea_zones:
			zones.append(int(zone.get("id", 0)))
	if zones.is_empty():
		return FleetState.at_sea(id, owner, 0)
	var zone: int = zones[_rng.randi_range(0, zones.size() - 1)]
	return FleetState.at_sea(id, owner, zone)


## Gives the fleet a deterministic starting squadron of typed hull instances.
func _assign_hulls(fleet: FleetState, index: int) -> void:
	var types: Array = HULL_SETS[index % HULL_SETS.size()]
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for type_id: String in types:
		var hull_id: String = "ship_%d" % _next_hull
		_next_hull += 1
		hull_ids.append(hull_id)
		hull_types[hull_id] = type_id
	fleet.set_hulls(hull_ids, hull_types)


func _coastal_zones(owner: int) -> Array[int]:
	var zones: Array[int] = []
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != owner:
			continue
		var province_id: int = int(province.get("id", MapModel.NO_ID))
		for zone: int in NavalMovement.province_sea_zones(model, province_id):
			if not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones


func _player_port(player_capital: int) -> int:
	# Sea-going fleets never sit in the capital port (home-fleet rule); prefer a
	# non-capital harbour, and the capital only when it is the sole option.
	for province: Dictionary in model.provinces:
		if int(province.get("owner", MapModel.NO_ID)) != 0:
			continue
		var province_id: int = int(province.get("id", MapModel.NO_ID))
		if province_id == player_capital:
			continue
		if NavalMovement.has_harbour(model, province_id):
			return province_id
	if player_capital >= 0 and model.province_owner(player_capital) == 0:
		if NavalMovement.has_harbour(model, player_capital):
			return player_capital
	return -1


func _place_ship(ship: Ship, fleet: FleetState) -> void:
	if fleet.is_in_port():
		var data: Dictionary = model.province_data(fleet.province)
		var port: Vector2i = data.get("port_tile", Vector2i(-1, -1))
		ship.position = model.tile_center(port.x, port.y, TILE_SIZE)
		ship.docked = true
		ship.zone = -1
		ship.province = fleet.province
		return
	ship.position = model.sea_zone_center(fleet.sea_zone) * TILE_SIZE
	ship.docked = false
	ship.zone = fleet.sea_zone
	ship.province = -1


func set_zoom(value: float) -> void:
	_zoom = maxf(value, 0.001)
	for ship: Ship in ships:
		var scale_factor: float = clampf(1.0 / _zoom, 0.6, 1.0)
		ship.scale = Vector2.ONE * scale_factor


func select(ship: Ship) -> void:
	if selected_ship != null and is_instance_valid(selected_ship):
		selected_ship.set_selected(false)
	selected_ship = ship
	if ship != null:
		ship.set_selected(true)
	ship_selected.emit(ship)


func deselect() -> void:
	if selected_ship != null and is_instance_valid(selected_ship):
		selected_ship.set_selected(false)
	if selected_ship == null:
		return
	selected_ship = null
	ship_selected.emit(null)


func ship_at(world_position: Vector2, radius: float = 26.0) -> Ship:
	var best: Ship = null
	var best_distance: float = radius
	for ship: Ship in ships:
		if not ship.visible:
			continue
		var distance: float = ship.position.distance_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = ship
	return best


func fleet_of(ship: Ship) -> FleetState:
	if ship == null:
		return null
	for fleet: FleetState in fleets:
		if fleet.id == ship.fleet_id:
			return fleet
	return null


func ship_for(fleet: FleetState) -> Ship:
	if fleet == null:
		return null
	for ship: Ship in ships:
		if ship.fleet_id == fleet.id:
			return ship
	return null


func valid_destinations(fleet: FleetState) -> Dictionary:
	return NavalMovement.valid_destinations(model, fleet)


## Applies a naval order through the rules module, then animates the marker.
func order(fleet: FleetState, destination: int, destination_id: int) -> Dictionary:
	var result: Dictionary = NavalMovement.apply_move(
		model, fleet, destination, destination_id
	)
	if not bool(result.get("ok", false)):
		return result
	var ship: Ship = ship_for(fleet)
	if ship != null:
		if destination == FleetState.Location.AT_SEA:
			ship.docked = false
			ship.zone = fleet.sea_zone
			ship.province = MapModel.NO_ID
			_sail(ship, model.sea_zone_center(fleet.sea_zone) * TILE_SIZE)
			zone_entered.emit(fleet.sea_zone, ship)
		else:
			ship.docked = true
			ship.zone = -1
			ship.province = fleet.province
			_sail(ship, _port_position(fleet.province))
	fleet_moved.emit(fleet, result)
	return result


func begin_turn() -> void:
	NavalMovement.begin_turn(fleets)


## Removes fleets whose last hull has been sunk and frees their map markers.
func prune_destroyed() -> void:
	var alive: Array[FleetState] = []
	for fleet: FleetState in fleets:
		if fleet.is_afloat():
			alive.append(fleet)
			continue
		var ship: Ship = ship_for(fleet)
		if ship != null:
			if selected_ship == ship:
				deselect()
			ships.erase(ship)
			ship.queue_free()
	fleets = alive


## Hulls still afloat for one faction across every fleet it keeps.
func hull_count(owner: int) -> int:
	var total: int = 0
	for fleet: FleetState in fleets:
		if fleet.owner == owner:
			total += fleet.ship_count()
	return total


func at_sea_zones(owner: int) -> Array[int]:
	var zones: Array[int] = []
	for fleet: FleetState in fleets:
		if fleet.owner != owner or not fleet.is_at_sea():
			continue
		if not zones.has(fleet.sea_zone):
			zones.append(fleet.sea_zone)
	return zones


func _port_position(province_id: int) -> Vector2:
	var data: Dictionary = model.province_data(province_id)
	var port: Vector2i = data.get("port_tile", Vector2i(-1, -1))
	if port.x < 0 or port.y < 0:
		return model.province_center(province_id) * TILE_SIZE
	return model.tile_center(port.x, port.y, TILE_SIZE)


func _sail(ship: Ship, target: Vector2) -> void:
	if ship.has_meta("sail_tween"):
		var previous: Tween = ship.get_meta("sail_tween") as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	var tween: Tween = create_tween()
	tween.tween_property(ship, "position", target, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN_OUT
	)
	ship.set_meta("sail_tween", tween)
