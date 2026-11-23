class_name MapPlaySeaStep
extends RefCounted
## One application of a rival squadron's sea step, so the invasion, colonisation
## and naval passes move hulls through the same rules instead of carrying three
## copies (REQ-P2-03, REQ-P3-01). The rules stay in NavalMovement, FleetSortie
## and WarpTravel; this only applies them and notes the water for the court's
## own chart. Pure state reads live in [MapPlayCourt], [MapPlayCourtHoldings] and
## [MapPlayCourtRoster]; this module is the one place a rival pass changes a roster.


## Puts a squadron to sea in `zone`: an ordinary move, or the one-zone sortie a
## home squadron needs (DR-20261109-17). The squadron charts the water it enters
## for its own court alone (wiki: ships-and-naval § Ship Reveal Mechanic). True
## when the rules accepted the step.
static func sail(
	play: PlaySession, model: MapModel, region: int, fleet: FleetState, zone: int
) -> bool:
	var sailed: Dictionary = NavalMovement.apply_move(
		model, fleet, FleetState.Location.AT_SEA, zone
	)
	if not bool(sailed.get("ok", false)):
		sailed = FleetSortie.apply(model, fleet, zone)
	if not bool(sailed.get("ok", false)):
		return false
	MapPlayCourtFog.note_fleet_entry(play, region, fleet, zone)
	return true


## Moors a squadron in `province`. True when the rules accepted the step; the
## caller folds a seat arrival into the home fleet.
static func dock(model: MapModel, fleet: FleetState, province: int) -> bool:
	var docked: Dictionary = NavalMovement.apply_move(
		model, fleet, FleetState.Location.IN_PORT, province
	)
	return bool(docked.get("ok", false))


## Crosses a Passage: the squadron leaves this region's stored roster and joins
## the destination's under a fresh id, so the two rosters never share a seat.
## Returns WarpTravel's result (empty on refusal); the caller carries its
## passengers and erases its own snapshot.
static func cross(play: PlaySession, region: int, fleet: FleetState) -> Dictionary:
	var result: Dictionary = WarpTravel.apply_crossing(play.world, region, fleet)
	if not bool(result.get("ok", false)):
		return result
	var to_region: int = int(result["to_region"])
	var source: Array = MapPlayCourtRoster.region_fleets(play, region)
	source.erase(fleet)
	play.ship_layer.regions.set_region(region, source)
	fleet.id = FleetRosters.next_id_all(play.ship_layer.regions)
	var destination: Array = MapPlayCourtRoster.region_fleets(play, to_region)
	destination.append(fleet)
	play.ship_layer.regions.set_region(to_region, destination)
	return result


## The court's money goal this turn: a court on **earn** sails for the far coast
## even while a war sits on its border (DR-20261113-19). Defence still comes
## first on its own soil, which each planner guards.
static func earning(
	play: PlaySession, faction: int, kind: String, config: Variant
) -> bool:
	# The win-bar reading the bank rides on (issue #995), so the expedition
	# pass reads the same goal the economy pass plans with — on the
	# submission surface; a baseline court keeps its published read.
	var conquest_gap: bool = (
		kind != AiControl.KIND_BASELINE
		and AiVictoryPressure.below_bar(
			play.world, faction, play.human_faction_id(), play.difficulty
		)
	)
	return str(
		AiBindEconomy.income_plan(
			kind, config, play.ledger_for(faction),
			MapPlayCourt.at_war(play, faction),
			MapPlayCourtHoldings.regiments(play, faction),
			MapPlayCourtHoldings.navy_chest(play, faction),
			MapPlayCourtHoldings.warships(play, faction),
			0,
			conquest_gap
		).get("goal", "")
	) == "earn"


## Keeps anything a crossing from a later-iterated region already landed in this
## roster before the pass writes its own copy back.
static func merge_stored(stored: Array, local: Array) -> void:
	for entity: Variant in stored:
		if entity != null and not local.has(entity):
			local.append(entity)
