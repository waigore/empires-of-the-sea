class_name ShipTurnPass
extends RefCounted
## Naval turn resolution across every region: beachheads, battles and ports that
## change hands. Kept out of `ShipLayer` so the layer stays a marker view and
## order surface (REQ-P3-01; wiki: map-topology § two regions, ships-and-naval).


## Resets readiness in every region: a fleet parked off-screen must still be
## able to sail when its map is opened again.
static func begin_turn(layer: ShipLayer) -> void:
	if layer == null:
		return
	FleetRosters.each(layer.regions, NavalMovement.begin_turn)


## Expires landing sites whose one full turn has run (wiki: ships-and-naval
## § Missions and Movement), in every region.
static func expire_beachheads(layer: ShipLayer, turn: int) -> void:
	if layer == null:
		return
	FleetRosters.each(layer.regions, NavalTransport.expire_beachheads.bind(turn))


## Resolves contested zones in every region, visible or not. NavalBattles
## decides who fights and who drowns; this pass drops the markers that lost
## their command and sails the retreats. `hostile` gates each pair; without it
## all pairs are hostile. `context` carries the campaign seed/turn and is
## completed with the region model so interception and retreat resolve per map
## (DR-20261109-16).
static func resolve_battles(
	layer: ShipLayer,
	world: WorldMap,
	hostile: Callable = Callable(),
	context: Dictionary = {}
) -> Array[Dictionary]:
	if layer == null:
		return []
	var shown: int = layer.model.region_id if layer.model != null else MapModel.NO_ID
	if layer.model != null:
		# The table holds the layer's live roster; a battle must resolve the
		# squadrons the chart is showing, not a stale copy of them.
		layer.regions.set_region(shown, layer.fleets)
	var battles: Array[Dictionary] = NavalBattles.resolve_region_turn(
		world, layer.regions, hostile, context
	)
	var on_screen: bool = false
	for battle: Dictionary in battles:
		if int(battle.get("region", -1)) == shown:
			on_screen = true
			break
	if not on_screen:
		return battles
	var alive: Array[FleetState] = []
	alive.assign(layer.regions.value(shown, []))
	# The layer and the table share one roster array, so later orders store once.
	layer.regions.set_region(shown, alive)
	layer.fleets = alive
	# Sunk hulls leave the marker: the survivor flies its new count.
	layer.markers.prune(layer.fleets)
	layer.markers.sync(layer.fleets)
	for battle: Dictionary in battles:
		if int(battle.get("region", -1)) != shown:
			continue
		for marker: Ship in layer.markers.retreat(battle, layer.fleets):
			layer.zone_entered.emit(marker.zone, marker)
	return battles


## Applies the port-capture rules after a Combat phase: a reassigned crown's
## home squadron re-moors at its new seat, then every squadron left in a port it
## no longer owns sorts out (wiki: ships-and-naval § Ports that change hands;
## DR-20261109-11, DR-20261109-12). Returns one report per event.
static func settle_port_losses(
	layer: ShipLayer, world: WorldMap, reassigned: Array
) -> Array[Dictionary]:
	if layer == null:
		return []
	var result: Dictionary = FleetPortSettlement.settle(world, layer.regions, reassigned)
	var reports: Array[Dictionary] = []
	reports.assign(result.get("reports", []))
	if layer.model == null or not (result.get("regions", []) as Array).has(layer.model.region_id):
		return reports
	layer.fleets.assign(layer.regions.value(layer.model.region_id, []))
	layer.rebuild_markers()
	for row: Dictionary in result.get("sorties", []):
		if int(row.get("region", -1)) != layer.model.region_id:
			continue
		if int(row.get("owner", MapModel.NO_ID)) != layer.player_faction:
			continue
		var marker: Ship = layer.ship_for(FleetRosters.find(layer.fleets, int(row["fleet"])))
		if marker != null:
			layer.zone_entered.emit(int(row["zone"]), marker)
	return reports
