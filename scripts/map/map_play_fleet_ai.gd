class_name MapPlayFleetAi
extends RefCounted
## Rival naval turn: every region's stored roster is planned and applied through
## NavalMovement, so a squadron that sails this turn fights this turn
## (docs/ai.md). Squadrons parked in another region still move, so switching
## maps never freezes the other theatre.


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
	return trace


static func _run_region(
	play: PlaySession, model: MapModel, roster: Array[FleetState], trace: Array[Dictionary]
) -> bool:
	var changed: bool = false
	var on_screen: bool = play.ship_layer.model != null and (
		play.ship_layer.model.region_id == model.region_id
	)
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		for order: Dictionary in AiNavalPlanner.orders(
			config, play.diplomacy, model, roster
		)["orders"]:
			var fleet: FleetState = _fleet_by_id(roster, int(order["fleet_id"]), faction)
			if fleet == null:
				continue
			var result: Dictionary = _apply(play, model, fleet, order, on_screen)
			if not bool(result.get("ok", false)):
				continue
			changed = true
			trace.append({
				"faction": faction,
				"kind": String(order["kind"]),
				"fleet": fleet.id,
				"zone": fleet.sea_zone,
				"province": fleet.province,
			})
			_report_sail(play, model, faction, order)
	return changed


## The on-screen roster has markers, so its move goes through ShipLayer and the
## squadron visibly sails; an off-screen roster only needs the rules applied.
static func _apply(
	play: PlaySession,
	model: MapModel,
	fleet: FleetState,
	order: Dictionary,
	on_screen: bool
) -> Dictionary:
	var destination: int = int(order["destination"])
	var target: int = int(order["zone"])
	if destination == FleetState.Location.IN_PORT:
		target = int(order["province"])
	if not on_screen:
		return NavalMovement.apply_move(model, fleet, destination, target)
	return play.ship_layer.order(fleet, destination, target)


## A rival squadron entering the waters off human land is never silent; battles
## report through the naval combat line instead.
static func _report_sail(
	play: PlaySession, model: MapModel, faction: int, order: Dictionary
) -> void:
	if play.hud == null or int(order["destination"]) != FleetState.Location.AT_SEA:
		return
	var coasts: Array[int] = NavalMovement.owned_provinces_by_zone(
		model, int(order["zone"]), play.player_faction
	)
	if coasts.is_empty():
		return
	play.hud.toast(
		"%s's squadron enters the waters off %s"
		% [FactionCatalog.name_of(faction), model.province_name(coasts[0])]
	)


static func _fleet_by_id(
	fleets: Array[FleetState], fleet_id: int, owner: int
) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet != null and fleet.id == fleet_id and fleet.owner == owner:
			return fleet
	return null
