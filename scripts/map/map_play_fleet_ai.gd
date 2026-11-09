class_name MapPlayFleetAi
extends RefCounted
## Rival naval turn: every region's stored squadrons are planned by
## AiNavalPlanner and moved through NavalMovement, so a sortie this turn can
## fight this turn (docs/ai.md). Rules stay pure; this only applies orders,
## resyncs markers and reports a sighting the human could already see.

const KIND_PURSUE: String = AiNavalPlanner.KIND_PURSUE
const KIND_SORTIE: String = AiNavalPlanner.KIND_SORTIE


static func run(play: PlaySession) -> Array[Dictionary]:
	var trace: Array[Dictionary] = []
	if play.ship_layer == null or play.diplomacy == null or play.world == null:
		return trace
	for region: int in play.ship_layer.regions.region_ids():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[FleetState] = []
		roster.assign(play.ship_layer.regions.value(region, []))
		if roster.is_empty():
			continue
		if not _run_region(play, model, roster, trace):
			continue
		play.ship_layer.regions.set_region(region, roster)
		if play.ship_layer.model != null and play.ship_layer.model.region_id == region:
			_adopt_visible(play)
	return trace


static func _run_region(
	play: PlaySession, model: MapModel, roster: Array[FleetState], trace: Array[Dictionary]
) -> bool:
	var changed: bool = false
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var plan: Dictionary = AiNavalPlanner.orders(
			config, play.diplomacy, model, roster
		)
		for order: Dictionary in plan["orders"]:
			var fleet: FleetState = _fleet_by_id(roster, int(order["fleet_id"]), faction)
			if fleet == null:
				continue
			var zone: int = int(order["zone"])
			var move: Dictionary = NavalMovement.apply_move(
				model, fleet, FleetState.Location.AT_SEA, zone
			)
			if not bool(move.get("ok", false)):
				continue
			changed = true
			trace.append({
				"faction": faction,
				"kind": String(order["kind"]),
				"fleet": fleet.id,
				"zone": zone,
				"threat": int(order["threat"]),
			})
			_report_sighting(play, model, faction, zone)
	return changed


## Re-reads the on-screen markers after the rules moved a squadron; the player's
## selected fleet survives the rebuild when it is still in the region.
static func _adopt_visible(play: PlaySession) -> void:
	var selected: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected_ship)
	play.ship_layer.spawn(
		play.ship_layer.model, 0, 0, -1, false, play.player_faction
	)
	if selected != null:
		play.ship_layer.select(play.ship_layer.ship_for(selected))


## Rival movement never reveals fog: a zone the human has not charted stays
## quiet, and one it can already see earns a single line (REQ-P2-03).
static func _report_sighting(
	play: PlaySession, model: MapModel, faction: int, zone: int
) -> void:
	if play.hud == null or play.visibility == null:
		return
	if model == null or model.region_id != play.region_index:
		return
	var data: SeaZoneState = model.sea_zone_data(zone)
	if data == null or data.tiles.is_empty():
		return
	var tile: Vector2i = data.tiles[0]
	if play.visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.FULLY_VISIBLE:
		return
	play.hud.toast(
		"%s's fleet is sighted in the %s"
		% [FactionCatalog.name_of(faction), model.sea_zone_name(zone)]
	)


static func _fleet_by_id(fleets: Array[FleetState], fleet_id: int, owner: int) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet != null and fleet.id == fleet_id and fleet.owner == owner:
			return fleet
	return null
