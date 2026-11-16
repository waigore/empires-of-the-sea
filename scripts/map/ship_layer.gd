class_name ShipLayer
extends Node2D
## Owns fleet markers and applies naval orders. NavalMovement decides outcomes;
## NavalBattles resolves the turn's battles in every region; this layer only
## animates them and reports zone entries for exploration. Roster surgery lives
## in FleetRosters, marker nodes in ShipMarkers (REQ-P3-01, REQ-P3-03).

signal zone_entered(zone_id: int, ship: Ship)
signal ship_selected(ship: Ship)
signal fleet_moved(fleet: FleetState, result: Dictionary)
signal warp_crossed(fleet: FleetState, result: Dictionary)

const TILE_SIZE: float = 22.0

var model: MapModel = null
## Both regions plus their warp links, for passage crossings.
var world: WorldMap = null
var fleets: Array[FleetState] = []

var _markers := ShipMarkers.new()
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
		return _markers.ships


func spawn(
	p_model: MapModel,
	count: int,
	seed_value: int,
	player_capital: int,
	player_present: bool = true,
	p_player_faction: int = FactionCatalog.PLAYER_FACTION
) -> void:
	model = p_model
	_markers.model = model
	_markers.rng.seed = seed_value
	player_faction = p_player_faction
	_markers.clear()
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
	_muster.rng = _markers.rng
	_muster.next_hull = next_hull
	fleets = _muster.build(model, count, player_capital, player_present, p_player_faction)
	next_hull = _muster.next_hull
	for fleet: FleetState in fleets:
		_attach_marker(fleet)
	regions.set_region(model.region_id, fleets)


func _attach_marker(fleet: FleetState) -> void:
	add_child(_markers.make(fleet, crown_view))


func rebuild_markers() -> void:
	_markers.clear()
	for fleet: FleetState in fleets:
		_attach_marker(fleet)


func set_zoom(value: float) -> void:
	_markers.set_zoom(value)


func select(ship: Ship) -> void:
	if _markers.selected_ship != null and is_instance_valid(_markers.selected_ship):
		_markers.selected_ship.set_selected(false)
	_markers.selected_ship = ship
	if ship != null:
		ship.set_selected(true)
	ship_selected.emit(ship)


func deselect() -> void:
	if _markers.selected_ship == null:
		return
	select(null)


## The hull the player has selected, if any.
func selected() -> Ship:
	return _markers.selected_ship


func ship_at(world_position: Vector2, radius: float = 26.0) -> Ship:
	var best: Ship = null
	var best_distance: float = radius
	for ship: Ship in _markers.ships:
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
	return _markers.find(fleet.id)


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
				_markers.remove(ship)
				ship = null
			# The home squadron just took on hulls: its marker flies more now.
			_markers.hulls(merged)
			regions.set_region(model.region_id, fleets)
	if ship != null:
		_markers.refit(ship, fleet)
		if destination == FleetState.Location.AT_SEA:
			ShipMarkers.sail(ship, model.sea_zone_center(fleet.sea_zone) * TILE_SIZE)
			zone_entered.emit(fleet.sea_zone, ship)
		else:
			ShipMarkers.sail(ship, ShipMarkers.port_position(model, fleet.province))
	fleet_moved.emit(arrived, result)
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
		fleet = FleetState.empty_in_port(
			FleetRosters.next_id(fleets), player_faction, province_id
		)
	var hull_id: String = "ship_%d" % next_hull
	var result: Dictionary = FleetYard.launch(economy, fleet, type_id, hull_id)
	if not bool(result.get("ok", false)):
		return result
	next_hull += 1
	if founded:
		fleets.append(fleet)
		regions.set_region(model.region_id, fleets)
		_attach_marker(fleet)
	_markers.hulls(fleet)
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
		_markers.hulls(fleet)
		return result
	_markers.remove(ship_for(fleet))
	fleets.erase(fleet)
	regions.set_region(model.region_id, fleets)
	return result


## Re-reads a squadron's hulls onto its marker after a raid sank one.
func refresh_hulls(fleet: FleetState) -> void:
	if fleet != null:
		_markers.hulls(fleet)


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
				_markers.hulls(fleet)
				return fleet
	return null


## Resets readiness in every region: a fleet parked off-screen must still be
## able to sail when its map is opened again.
func begin_turn() -> void:
	FleetRosters.each(regions, NavalMovement.begin_turn)


## Expires landing sites whose one full turn has run (wiki: ships-and-naval
## § Missions and Movement), in every region.
func expire_beachheads(turn: int) -> void:
	FleetRosters.each(regions, NavalTransport.expire_beachheads.bind(turn))


## Resolves contested zones in every region, visible or not (wiki: map-topology
## § two regions). NavalBattles decides who fights and who drowns; this layer
## only drops the markers that lost their command and sails the retreats.
## `hostile` gates each pair; without it all pairs are hostile. `context`
## carries the campaign seed/turn and is completed with the region model so
## interception and retreat resolve per map (DR-20261109-16).
func resolve_battles(
	world: WorldMap, hostile: Callable = Callable(), context: Dictionary = {}
) -> Array[Dictionary]:
	var shown: int = model.region_id if model != null else MapModel.NO_ID
	if model != null:
		# The table holds the layer's live roster; a battle must resolve the
		# squadrons the chart is showing, not a stale copy of them.
		regions.set_region(shown, fleets)
	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, regions, hostile, context
	)
	var on_screen: bool = false
	for battle: Dictionary in battles:
		if int(battle.get("region", -1)) == shown:
			on_screen = true
			break
	if not on_screen:
		return battles
	var alive: Array[FleetState] = []
	alive.assign(regions.value(shown, []))
	# The layer and the table share one roster array, so later orders store once.
	regions.set_region(shown, alive)
	fleets = alive
	# Sunk hulls leave the marker: the survivor flies its new count.
	_markers.prune(fleets)
	_markers.sync(fleets)
	for battle: Dictionary in battles:
		if int(battle.get("region", -1)) != shown:
			continue
		for marker: Ship in _markers.retreat(battle, fleets):
			zone_entered.emit(marker.zone, marker)
	return battles


## Applies the port-capture rules after a Combat phase: a reassigned crown's
## home squadron re-moors at its new seat, then every squadron left in a port it
## no longer owns sorts out (wiki: ships-and-naval § Ports that change hands;
## DR-20261109-11, DR-20261109-12). Returns one report per event.
func settle_port_losses(world: WorldMap, reassigned: Array) -> Array[Dictionary]:
	var result: Dictionary = FleetPortSettlement.settle(world, regions, reassigned)
	var reports: Array[Dictionary] = []
	reports.assign(result.get("reports", []))
	if model == null or not (result.get("regions", []) as Array).has(model.region_id):
		return reports
	fleets.assign(regions.value(model.region_id, []))
	rebuild_markers()
	for row: Dictionary in result.get("sorties", []):
		if int(row.get("region", -1)) != model.region_id:
			continue
		if int(row.get("owner", MapModel.NO_ID)) != player_faction:
			continue
		var marker: Ship = ship_for(FleetRosters.find(fleets, int(row["fleet"])))
		if marker != null:
			zone_entered.emit(int(row["zone"]), marker)
	return reports


## The home squadron puts to sea (wiki: ships-and-naval § Home Fleet;
## DR-20261109-17): the rules spend its move, the marker leaves the port and
## the entered zone is revealed like any sail order.
func sortie(fleet: FleetState, zone: int) -> Dictionary:
	var result: Dictionary = FleetSortie.apply(model, fleet, zone)
	if not bool(result.get("ok", false)):
		return result
	var ship: Ship = ship_for(fleet)
	if ship != null:
		_markers.refit(ship, fleet)
		zone_entered.emit(zone, ship)
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
	for ship: Ship in _markers.ships:
		if ship.faction == from_id and to_id != MapModel.NO_ID:
			ship.faction = to_id
	_markers.prune(fleets)


## Every region counts: reading another map must not hide hulls or upkeep.
func hull_count_all(owner: int) -> int:
	return FleetRosters.hulls_afloat(regions, owner)


func at_sea_zones(owner: int) -> Array[int]:
	return FleetRosters.zones_at_sea(fleets, owner)

