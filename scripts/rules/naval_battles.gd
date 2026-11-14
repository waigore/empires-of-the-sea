class_name NavalBattles
extends RefCounted
## Sea-zone combat across every region (REQ-P3-03). A battle must not wait for
## the player to open that chart (wiki: map-topology § two regions), so the
## squadrons of every region resolve in one pass and the drowned leave their
## roster. Pure data in, battle reports out — [ShipLayer] only repaints its
## markers, exactly as [ArmyBattles] leaves [ArmyLayer] to redraw the standards.


## Resolves every region's contested zones and writes each fighting region's
## pruned roster back into `regions`; a region without a battle keeps the roster
## it had. `hostile` gates each pair, so peace never spills blood; without it
## every pair is hostile. `context` carries the campaign seed/turn and is
## completed with the region model so interception and retreat resolve per map
## (DR-20261109-16). Returns one entry per battle with its `region`.
static func resolve_region_turn(
	world: WorldMap,
	regions: MapRegionTable,
	hostile: Callable = Callable(),
	context: Dictionary = {}
) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for index in world.region_count():
		var region_fleets: Array[FleetState] = []
		region_fleets.assign(regions.value(index, []))
		if region_fleets.is_empty():
			continue
		var region_context: Dictionary = context.duplicate(true)
		region_context["model"] = world.region(index)
		region_context["fleets"] = region_fleets
		var battles: Array[Dictionary] = NavalCombat.resolve_turn(
			region_fleets, hostile, region_context
		)
		if battles.is_empty():
			continue
		# Every region prunes its own drowned hulls, on screen or not: a sunk
		# squadron must never come back with the next chart.
		FleetRosters.prune(region_fleets)
		regions.set_region(index, region_fleets)
		for battle: Dictionary in battles:
			battle["region"] = index
			all.append(battle)
	return all
