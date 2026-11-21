class_name ShipLayer
extends Node2D
## Owns fleet markers and applies naval orders. NavalMovement decides outcomes;
## ShipTurnPass resolves the turn's battles and port losses; ShipYardOps owns
## launch and scrap. Roster surgery lives in FleetRosters, marker nodes in
## ShipMarkers (REQ-P3-01, REQ-P3-03).

signal zone_entered(zone_id: int, ship: Ship)
signal ship_selected(ship: Ship)
signal fleet_moved(fleet: FleetState, result: Dictionary)
signal warp_crossed(fleet: FleetState, result: Dictionary)

const TILE_SIZE: float = 22.0

var model: MapModel = null
## Both regions plus their warp links, for passage crossings.
var world: WorldMap = null
var fleets: Array[FleetState] = []

var markers := ShipMarkers.new()
var _muster := FleetMuster.new()
## The crown that owns the home fleet and may launch hulls at its capital.
var player_faction: int = FactionCatalog.PLAYER_FACTION
## Hull ids stay unique for the life of the save; save/load restores this
## cursor through the public field (REQ-P3-02 narrow APIs).
var next_hull: int = 1
## Fleet state per region: switching maps must not reroll or lose squadrons.
var regions := MapRegionTable.new()
var crown_view: Callable = Callable() ## the chart's reading of one squadron: drawn, read


## Markers the shown region draws, in mint order (view handles for taps).
var ships: Array[Ship]:
	get:
		return markers.ships


func spawn(
	p_model: MapModel,
	count: int,
	seed_value: int,
	player_capital: int,
	player_present: bool = true,
	p_player_faction: int = FactionCatalog.PLAYER_FACTION
) -> void:
	model = p_model
	markers.model = model
	markers.rng.seed = seed_value
	markers.player = p_player_faction
	player_faction = p_player_faction
	markers.clear()
	fleets = []
	if model.sea_zone_count() == 0:
		return
	if regions.has_region(model.region_id):
		fleets.assign(regions.value(model.region_id, []))
		regions.set_region(model.region_id, fleets)
		rebuild_markers()
		return
	# Hull ids stay unique for the life of the save, so the counter runs on
	# across regions (wiki: ships-and-naval § Ship instances); never collide.
	_muster.rng = markers.rng
	_muster.next_hull = next_hull
	fleets = _muster.build(model, count, player_capital, player_present, p_player_faction)
	next_hull = _muster.next_hull
	for fleet: FleetState in fleets:
		attach_marker(fleet)
	relayout()
	regions.set_region(model.region_id, fleets)


func attach_marker(fleet: FleetState) -> void:
	add_child(markers.make(fleet, crown_view))


func rebuild_markers() -> void:
	markers.clear()
	for fleet: FleetState in fleets:
		attach_marker(fleet)
	relayout()


## Fans the crown's squadrons out over their station and stacks the rest, so a
## crowded sea zone can still be read and picked (wiki: ships-and-naval
## § Fleets in one station; DR-20261119-08).
func relayout() -> void:
	markers.layout(fleets, player_faction)


## Re-reads the chart after the roster changed with no marker of its own: a
## squadron folded into her home fleet leaves the station, and the squadron she
## joined flies the hulls she brought (wiki: ships-and-naval § Home Fleet,
## § Fleets in one station; DR-20261119-17). The region on screen answers from
## the fleet table, so a pass that folded into its own copy is still read here:
## a marker whose command has left is dropped rather than left to draw, and the
## row closes up behind her.
func roster_changed() -> void:
	if model == null:
		return
	fleets.assign(regions.value(model.region_id, []))
	markers.prune(fleets)
	markers.sync(fleets)
	relayout()


func set_zoom(value: float) -> void:
	markers.set_zoom(value)


## Re-reads a squadron's station onto her marker without moving the hull: a
## station taken or given up at the dossier repaints the work loop (issue
## #1198).
func station(fleet: FleetState) -> void:
	if fleet == null:
		return
	var ship: Ship = ship_for(fleet)
	if ship != null:
		markers.station_order(ship, fleet)


func select(ship: Ship) -> void:
	if markers.selected_ship != null and is_instance_valid(markers.selected_ship):
		markers.selected_ship.set_selected(false)
	markers.selected_ship = ship
	if ship != null:
		ship.set_selected(true)
	# The squadron in the crown's hand comes to the head of her stack, so the
	# marker she tapped keeps drawing the hull (REQ-P5-05).
	relayout()
	ship_selected.emit(ship)


## The squadron a tap picks: the hull under the finger, or the next squadron in
## her stack when she is already in the crown's hand — a mixed station is read
## one command at a time (wiki: ships-and-naval § Fleets in one station).
func tap(ship: Ship) -> Ship:
	if ship == null or markers.selected_ship != ship:
		return ship
	var next: Ship = markers.next_in_stack(ship)
	return next if next != null else ship


func deselect() -> void:
	if markers.selected_ship == null:
		return
	select(null)


## The hull the player has selected, if any.
func selected() -> Ship:
	return markers.selected_ship


func ship_at(world_position: Vector2, radius: float = 26.0) -> Ship:
	var best: Ship = null
	var best_distance: float = radius
	for ship: Ship in markers.ships:
		if not ship.visible or ship.covered:
			continue
		var distance: float = ship.drawn_position().distance_to(world_position)
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
	return markers.find(fleet.id)


## Crosses a passage: rules verify the link, then the fleet leaves this roster
## for the counterpart's, renumbered so regions never share an id
## (FleetRosters.hand_to_region).
func cross(fleet: FleetState) -> Dictionary:
	var result: Dictionary = WarpTravel.apply_crossing(world, model.region_id, fleet)
	if not bool(result.get("ok", false)):
		return result
	FleetRosters.hand_to_region(
		regions, model.region_id, fleet, int(result["to_region"]), fleets
	)
	rebuild_markers()
	warp_crossed.emit(fleet, result)
	return result


## Applies a naval order through the rules module, then animates the marker.
## Docking at the crown's own capital resolves by merging into the home fleet,
## so the sea-going squadron disappears from the roster (wiki: ships-and-naval
## § Home Fleet).
func order(fleet: FleetState, destination: int, destination_id: int) -> Dictionary:
	var result: Dictionary = NavalMovement.apply_move(
		model, fleet, destination, destination_id
	)
	if not bool(result.get("ok", false)):
		return result
	var ship: Ship = ship_for(fleet)
	var arrived: FleetState = fleet
	if destination == FleetState.Location.IN_PORT:
		var merge: Dictionary = NavalMovement.merge_into_home(model, fleets, fleet)
		var merged: FleetState = merge.get("fleet") as FleetState
		if merged != null:
			arrived = merged
			result["merged_into"] = merged.id
			result["merged_hulls"] = int(merge.get("hulls", 0))
			# The merge carries hulls and passengers; a second army cannot stay
			# aboard, so the report names it for the layer to land at the port.
			if merged.embarked_army >= 0:
				result["embarked_army"] = merged.embarked_army
			result["displaced_army"] = int(merge.get("displaced", -1))
			if ship != null:
				markers.remove(ship)
				ship = null
			# The home squadron just took on hulls: its marker flies more now.
			markers.hulls(merged)
			regions.set_region(model.region_id, fleets)
	if ship != null:
		markers.refit(ship, fleet)
		if destination == FleetState.Location.AT_SEA:
			ShipMarkers.sail(ship, model.sea_zone_center(fleet.sea_zone) * TILE_SIZE)
			zone_entered.emit(fleet.sea_zone, ship)
		else:
			ShipMarkers.sail(ship, ShipMarkers.port_position(model, fleet.province))
	relayout()
	fleet_moved.emit(arrived, result)
	return result


## The crown's squadron moored in a port, if any: the home fleet
## (wiki: ships-and-naval § Home Fleet).
func home_fleet(province_id: int) -> FleetState:
	return ShipYardOps.home_fleet(fleets, player_faction, province_id)


## Frees the deck of a squadron whose carried army has left the field: an
## emptied field army retires, so no squadron carries it any more (wiki:
## military-armies § Dismissing regiments; ships-and-naval § Naval transport).
## Returns the squadron that was freed, or null when none carried it.
func release_deck(army_id: int) -> FleetState:
	if army_id < 0:
		return null
	for region: int in regions.region_ids():
		var stored: Array = regions.value(region, [])
		for fleet: FleetState in stored:
			if fleet != null and fleet.embarked_army == army_id:
				fleet.embarked_army = -1
				markers.hulls(fleet)
				return fleet
	return null


## The home squadron puts to sea (wiki: ships-and-naval § Home Fleet;
## DR-20261109-17): the rules spend its move, the marker leaves the port and
## the entered zone is revealed like any sail order.
func sortie(fleet: FleetState, zone: int) -> Dictionary:
	var result: Dictionary = FleetSortie.apply(model, fleet, zone)
	if not bool(result.get("ok", false)):
		return result
	var ship: Ship = ship_for(fleet)
	if ship != null:
		markers.refit(ship, fleet)
		zone_entered.emit(zone, ship)
	relayout()
	fleet_moved.emit(fleet, result)
	return result


## A Join Empire absorption transfers the loser's squadrons and markers.
## `MapModel.NO_ID` retires them instead: the crown leaves the map. The roster
## surgery is FleetRosters.hand_over; this layer keeps the shown roster live and
## repaints the colours (or drops the markers).
func transfer_owner(from_id: int, to_id: int) -> void:
	for region: int in regions.region_ids():
		var stored: Array[FleetState] = []
		stored.assign(regions.value(region, []))
		FleetRosters.hand_over(stored, from_id, to_id)
		regions.set_region(region, stored)
		if model != null and region == model.region_id:
			fleets = stored
	for ship: Ship in markers.ships:
		if ship.faction == from_id and to_id != MapModel.NO_ID:
			ship.faction = to_id
	markers.prune(fleets)
	# An absorbed squadron now answers to the crown, so her busiest loop (a
	# station) is read again under the new flag (issue #1198).
	markers.sync(fleets)
	relayout()


## Every region counts: reading another map must not hide hulls or upkeep.
func hull_count_all(owner: int) -> int:
	return FleetRosters.hulls_afloat(regions, owner)


func at_sea_zones(owner: int) -> Array[int]:
	return FleetRosters.zones_at_sea(fleets, owner)
