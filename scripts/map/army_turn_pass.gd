class_name ArmyTurnPass
extends RefCounted
## Land turn resolution across every region: readiness reset and battles.
## Kept out of `ArmyLayer` so the layer stays a marker view and order surface
## (REQ-P3-01; wiki: map-topology § two regions, military-armies). Mirrors
## ShipTurnPass for the sea.


## Resets readiness in every region: an army parked off-screen must still be
## able to march when its map is opened again. Each region rests by its own
## hospitals (DR-20261111-12).
static func begin_turn(layer: ArmyLayer, world: WorldMap = null) -> void:
	if layer == null:
		return
	for region_id: int in layer.regions.region_ids():
		var stored: Array[ArmyState] = []
		stored.assign(layer.regions.value(region_id, []))
		var region_model: MapModel = world.region(region_id) if world != null else layer.model
		ArmyMovement.begin_turn(stored, region_model)


## Resolves land battles in every region: a battle must not wait for the player
## to open that map (wiki: map-topology § two regions); `context["hostile"]` is
## the court's war query so peace never spills blood.
##
## The pass may mint a garrison (wiki: combat § Garrison recovery), so the
## crown's own id cursors travel with it: one army id and one regiment id per
## instance, never a number a standard or a man already wears in the other chart
## (wiki: military-armies § Split and combine).
static func resolve_battles(
	layer: ArmyLayer, world: WorldMap, context: Dictionary = {}
) -> Array[Dictionary]:
	if layer == null or world == null:
		return []
	var by_region: Dictionary = {}
	for index in world.region_count():
		var region_armies: Array[ArmyState] = []
		if layer.model != null and index == layer.model.region_id:
			region_armies = layer.armies
		else:
			region_armies.assign(layer.regions.value(index, []))
		by_region[index] = region_armies
	var pass_context: Dictionary = context.duplicate()
	var ids: Dictionary = {"army": layer.next_army, "regiment": layer.next_regiment}
	pass_context["ids"] = ids
	var all: Array[Dictionary] = ArmyBattles.resolve_region_turn(
		world, by_region, layer.generals, pass_context
	)
	layer.next_army = maxi(layer.next_army, int(ids.get("army", layer.next_army)))
	layer.next_regiment = maxi(layer.next_regiment, int(ids.get("regiment", layer.next_regiment)))
	for index in world.region_count():
		var region_armies: Array[ArmyState] = []
		region_armies.assign(by_region.get(index, []))
		# Whatever the pass minted, a cursor never falls behind a live instance:
		# the next split and the next muster hand out a number no standard or
		# man wears (a save written before the cursors travelled keeps its ids).
		for army: ArmyState in region_armies:
			if army == null:
				continue
			layer.next_army = maxi(layer.next_army, army.id + 1)
			for regiment_id: String in army.regiments:
				var number: int = ArmyCommand.unit_number(regiment_id)
				if number >= 0:
					layer.next_regiment = maxi(layer.next_regiment, number + 1)
		layer.regions.set_region(index, region_armies)
		if layer.model != null and index == layer.model.region_id:
			layer.armies = region_armies
			layer.prune_markers()
	return all
