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
		if faction == play.player_faction and not play.observer_mode:
			continue
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var plan: Dictionary = AiNavalPlanner.orders(
			config, play.diplomacy, model, roster, play.court_charts
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
			MapPlayCourtFog.note_fleet_entry(play, model.region_id, fleet, zone)
			trace.append({
				"faction": faction,
				"kind": String(order["kind"]),
				"fleet": fleet.id,
				"zone": zone,
				"zone_name": model.sea_zone_name(zone),
				"region": model.region_id,
				"threat": int(order["threat"]),
			})
			_report_sighting(play, model, faction, zone)
		_station_orders(play, model, roster, faction)
	return changed


## A squadron that did not sortie still takes a station: blockade an enemy coast
## in its zone when one is at war, otherwise hold (wiki: ships-and-naval
## § Missions and Movement; DR-20261109-16).
static func _station_orders(
	play: PlaySession, model: MapModel, roster: Array[FleetState], faction: int
) -> void:
	var hostile := func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(play.diplomacy, a, b)
	for fleet: FleetState in roster:
		if fleet == null or fleet.owner != faction:
			continue
		if not fleet.is_at_sea() or not fleet.is_afloat() or fleet.moved:
			continue
		var mission: int = fleet.mission
		if mission == FleetState.Mission.BLOCKADE:
			if FleetMissions.is_blockading(model, fleet, hostile):
				continue
			fleet.clear_mission()
			mission = FleetState.Mission.NONE
		if mission != FleetState.Mission.NONE and mission != FleetState.Mission.DEFEND:
			continue
		var targets: Array[int] = FleetMissions.blockade_targets(model, fleet, hostile)
		targets = _charted_targets(play, model, faction, targets)
		if not targets.is_empty():
			FleetMissions.assign(
				model, fleet, FleetState.Mission.BLOCKADE, targets[0], hostile
			)
			continue
		if mission == FleetState.Mission.NONE:
			FleetMissions.assign(
				model, fleet, FleetState.Mission.DEFEND, MapModel.NO_ID, hostile
			)


## A blockade is never posted on a coast the court has not charted: the same
## fog that gates a sortie gates the station (DR-20261110-21).
static func _charted_targets(
	play: PlaySession, model: MapModel, faction: int, targets: Array[int]
) -> Array[int]:
	if play.court_charts == null:
		return targets
	var kept: Array[int] = []
	for province: int in targets:
		if play.court_charts.knows_province(faction, model.region_id, province):
			kept.append(province)
	return kept


## Re-reads the on-screen markers after the rules moved a squadron; the player's
## selected fleet survives the rebuild when it is still in the region.
static func _adopt_visible(play: PlaySession) -> void:
	var selected: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	play.ship_layer.spawn(
		play.ship_layer.model, 0, 0, -1, false, play.player_faction
	)
	if selected != null:
		play.ship_layer.select(play.ship_layer.ship_for(selected))


## Rival movement never reveals fog: a zone the human has not charted stays
## quiet, and one already charted (fogged or better) earns a single line
## (wiki: fog-and-exploration § Visibility Levels; REQ-P2-03).
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
	if play.visibility.level_at(tile.x, tile.y) < VisibilityModel.Level.FOGGED:
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
