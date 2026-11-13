class_name ArmyBattles
extends RefCounted
## Land-combat turn across every region (REQ-P3-03). A battle must not wait for
## the player to open that map (wiki: map-topology § two regions), so the armies
## of every region resolve in one pass; generals bind once for the whole phase.
## Pure data in, battle reports out — [ArmyLayer] only repaints its markers.


## `by_region` holds each region's live roster (the caller's array is mutated).
## `context` carries the court's `hostile` war query plus an optional `seed`, so
## peace never spills blood. Returns one entry per battle with its `region`.
static func resolve_region_turn(
	world: WorldMap,
	by_region: Dictionary,
	generals: GeneralRoster,
	context: Dictionary = {}
) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	var phase: Dictionary = context.duplicate()
	phase["roster"] = generals
	## Every crown's roster is reconciled with its own research before binding.
	## The ledger only keeps the human's pool in step, so without this a rival
	## that studied organised_regiments would still field one commander
	## (wiki: military-generals § Count and tech-gated cap).
	var tech: Variant = context.get("tech", {})
	if generals != null and typeof(tech) == TYPE_DICTIONARY:
		generals.reconcile(tech as Dictionary)
	## Binding reads the same war query as resolution: a march into land its
	## crown is at peace with is no engagement and must not spend a commander
	## (wiki: military-generals § Assignment).
	var binding: Dictionary = GeneralBinding.bind_phase(
		world, by_region, generals, int(context.get("seed", 0)),
		context.get("hostile", Callable()) as Callable
	)
	phase["army_general"] = binding.get("army_general", {})
	phase["army_medals"] = binding.get("army_medals", {})
	for index in world.region_count():
		var region_armies: Array[ArmyState] = []
		region_armies.assign(by_region.get(index, []))
		if region_armies.is_empty():
			continue
		var battles: Array[Dictionary] = ArmyCombat.resolve_turn(
			world.region(index), region_armies, phase
		)
		if battles.is_empty():
			continue
		ArmyRoster.prune(region_armies)
		by_region[index] = region_armies
		for battle: Dictionary in battles:
			battle["region"] = index
			all.append(battle)
	return all
