class_name ShipLayer
extends Node2D
## Owns fleet markers and applies naval orders. NavalMovement decides outcomes;
## this layer animates them and reports zone entries for exploration.

signal zone_entered(zone_id: int, ship: Ship)
signal ship_selected(ship: Ship)
signal fleet_moved(fleet: FleetState, result: Dictionary)
signal warp_crossed(fleet: FleetState, result: Dictionary)

const TILE_SIZE: float = 22.0

var model: MapModel = null
## Both regions plus their warp links, for passage crossings.
var world: WorldMap = null
var fleets: Array[FleetState] = []
var ships: Array[Ship] = []
var selected_ship: Ship = null

var _rng := RandomNumberGenerator.new()
var _zoom: float = 1.0
var _muster := FleetMuster.new()
## The crown that owns the home fleet and may launch hulls at its capital.
var player_faction: int = FactionCatalog.PLAYER_FACTION
## Hull ids stay unique for the life of the save; save/load restores this
## cursor through the public field (REQ-P3-02 narrow APIs).
var next_hull: int = 1
## Fleet state per region: switching maps must not reroll or lose squadrons.
var regions := MapRegionTable.new()


func spawn(
	p_model: MapModel,
	count: int,
	seed_value: int,
	player_capital: int,
	player_present: bool = true,
	p_player_faction: int = FactionCatalog.PLAYER_FACTION
) -> void:
	model = p_model
	_rng.seed = seed_value
	player_faction = p_player_faction
	for ship: Ship in ships:
		ship.queue_free()
	ships.clear()
	selected_ship = null
	fleets = []
	if model.sea_zone_count() == 0:
		return
	if regions.has_region(model.region_id):
		fleets.assign(regions.value(model.region_id, []))
		regions.set_region(model.region_id, fleets)
		_rebuild_markers()
		return
	# Hull ids stay unique for the life of the save, so the counter runs on
	# across regions (wiki: ships-and-naval § Ship instances); never collide.
	_muster.rng = _rng
	_muster.next_hull = next_hull
	fleets = _muster.build(model, count, player_capital, player_present, p_player_faction)
	next_hull = _muster.next_hull
	for fleet: FleetState in fleets:
		_make_marker(fleet)
	regions.set_region(model.region_id, fleets)


func _make_marker(fleet: FleetState) -> void:
	var ship := Ship.new()
	ship.fleet_id = fleet.id
	ship.faction = fleet.owner
	ship.bob_phase = _rng.randf() * TAU
	ship.speed = 26.0 + _rng.randf() * 16.0
	_place_ship(ship, fleet)
	add_child(ship)
	ships.append(ship)


func _rebuild_markers() -> void:
	for ship: Ship in ships:
		ship.queue_free()
	ships.clear()
	selected_ship = null
	for fleet: FleetState in fleets:
		_make_marker(fleet)


func _place_ship(ship: Ship, fleet: FleetState) -> void:
	if fleet.is_in_port():
		var data: ProvinceState = model.province_data(fleet.province)
		var port: Vector2i = data.port_tile if data != null else Vector2i(-1, -1)
		ship.position = MapGeo.tile_center(port.x, port.y, TILE_SIZE)
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


## Crosses a passage: rules verify the link, then the fleet leaves this roster
## for the counterpart's, renumbered so regions never share an id.
func cross(fleet: FleetState) -> Dictionary:
	var result: Dictionary = WarpTravel.apply_crossing(world, model.region_id, fleet)
	if not bool(result.get("ok", false)):
		return result
	var to_region: int = int(result["to_region"])
	var destination: Array[FleetState] = []
	destination.assign(regions.value(to_region, []))
	var next_id: int = 0
	for raw: Variant in regions.values():
		var stored: Array[FleetState] = []
		stored.assign(raw)
		for other: FleetState in stored:
			next_id = maxi(next_id, other.id + 1)
	fleets.erase(fleet)
	fleet.id = next_id
	destination.append(fleet)
	regions.set_region(to_region, destination)
	regions.set_region(model.region_id, fleets)
	_rebuild_markers()
	warp_crossed.emit(fleet, result)
	return result


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


## The crown's squadron moored in a port, if any: the home fleet
## (wiki: ships-and-naval § Home Fleet).
func home_fleet(province_id: int) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet.owner != player_faction or not fleet.is_in_port():
			continue
		if fleet.province == province_id:
			return fleet
	return null


## Launches one paid-for hull into the home fleet, founding it at the slip when
## the crown keeps no squadron in that port (wiki: ships-and-naval § Ship build
## economy). The view only mirrors what FleetYard already allowed.
func launch_hull(province_id: int, type_id: String, economy: PlayerEconomy) -> Dictionary:
	var fleet: FleetState = home_fleet(province_id)
	var founded: bool = fleet == null
	if founded:
		fleet = FleetState.empty_in_port(_next_fleet_id(), player_faction, province_id)
	var hull_id: String = "ship_%d" % next_hull
	var result: Dictionary = FleetYard.launch(economy, fleet, type_id, hull_id)
	if not bool(result.get("ok", false)):
		return result
	next_hull += 1
	if founded:
		fleets.append(fleet)
		regions.set_region(model.region_id, fleets)
		_make_marker(fleet)
	result["created"] = founded
	result["fleet"] = fleet
	return result


## Breaks up one hull of an own squadron; an emptied fleet leaves the map
## (wiki: ships-and-naval § Ship muster and the breaker's yard).
func scrap_hull(fleet: FleetState, hull_id: String, economy: PlayerEconomy) -> Dictionary:
	if fleet == null or fleet.owner != player_faction:
		return {"ok": false, "reason": "Own colours only.", "hull": "", "type": "", "retired": false}
	var result: Dictionary = FleetYard.scrap(economy, fleet, hull_id)
	if not bool(result.get("ok", false)) or not bool(result.get("retired", false)):
		return result
	var ship: Ship = ship_for(fleet)
	if ship != null:
		if selected_ship == ship:
			deselect()
		ships.erase(ship)
		ship.queue_free()
	fleets.erase(fleet)
	regions.set_region(model.region_id, fleets)
	return result


## A founded home fleet takes the next free id in this region.
func _next_fleet_id() -> int:
	var next_id: int = 0
	for other: FleetState in fleets:
		next_id = maxi(next_id, other.id + 1)
	return next_id


## Resets readiness in every region: a fleet parked off-screen must still be
## able to sail when its map is opened again.
func begin_turn() -> void:
	for stored: Array in regions.values():
		var region_fleets: Array[FleetState] = []
		region_fleets.assign(stored)
		NavalMovement.begin_turn(region_fleets)


## Resolves contested zones in every region, visible or not (wiki: map-topology
## § two regions). `hostile` gates each pair; without it all pairs are hostile.
func resolve_battles(
	world: WorldMap, hostile: Callable = Callable()
) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for index in world.region_count():
		var region_fleets: Array[FleetState] = []
		if model != null and index == model.region_id:
			region_fleets = fleets
		else:
			region_fleets.assign(regions.value(index, []))
		if region_fleets.is_empty():
			continue
		var battles: Array[Dictionary] = NavalCombat.resolve_turn(region_fleets, hostile)
		if battles.is_empty():
			continue
		var alive: Array[FleetState] = []
		var on_screen: bool = model != null and index == model.region_id
		for fleet: FleetState in region_fleets:
			if fleet.is_afloat():
				alive.append(fleet)
				continue
			if not on_screen:
				continue
			var ship: Ship = ship_for(fleet)
			if ship != null:
				if selected_ship == ship:
					deselect()
				ships.erase(ship)
				ship.queue_free()
		regions.set_region(index, alive)
		if on_screen:
			fleets = alive
		for battle: Dictionary in battles:
			battle["region"] = index
			all.append(battle)
	return all


## A Join Empire absorption transfers the loser's squadrons and markers.
## Absorption transfers the loser's squadrons; `MapModel.NO_ID` retires them.
func transfer_owner(from_id: int, to_id: int) -> void:
	var retire: bool = to_id == MapModel.NO_ID
	for raw: Variant in regions.values():
		var stored: Array = raw
		for index in range(stored.size() - 1, -1, -1):
			var fleet: FleetState = stored[index]
			if fleet == null or fleet.owner != from_id:
				continue
			if retire:
				stored.remove_at(index)
				continue
			fleet.owner = to_id
	for index in range(fleets.size() - 1, -1, -1):
		var fleet: FleetState = fleets[index]
		if fleet == null or fleet.owner != from_id:
			continue
		if retire:
			fleets.remove_at(index)
			continue
		fleet.owner = to_id
	var kept: Array[Ship] = []
	for ship: Ship in ships:
		if ship.faction != from_id:
			kept.append(ship)
			continue
		if not retire:
			ship.faction = to_id
			kept.append(ship)
			continue
		if ship == selected_ship:
			selected_ship = null
		ship.queue_free()
	ships = kept


## Hulls still afloat for one faction across every fleet it keeps.
func hull_count(owner: int) -> int:
	var total: int = 0
	for fleet: FleetState in fleets:
		if fleet.owner == owner:
			total += fleet.ship_count()
	return total


## Every region counts: reading another map must not hide hulls or upkeep.
func hull_count_all(owner: int) -> int:
	var total: int = 0
	for raw: Variant in regions.values():
		var stored: Array[FleetState] = []
		stored.assign(raw)
		for fleet: FleetState in stored:
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
	var data: ProvinceState = model.province_data(province_id)
	var port: Vector2i = data.port_tile if data != null else Vector2i(-1, -1)
	if port.x < 0 or port.y < 0:
		return model.province_center(province_id) * TILE_SIZE
	return MapGeo.tile_center(port.x, port.y, TILE_SIZE)


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
