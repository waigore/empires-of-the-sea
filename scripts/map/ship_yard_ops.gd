class_name ShipYardOps
extends RefCounted
## Home-fleet yard mutations for the chart: launch, scrap and hull refresh.
## Kept out of `ShipLayer` so the layer stays orders, markers and signals
## (REQ-P3-01; wiki: ships-and-naval § Ship build economy, § Ship muster).


## The crown's squadron moored in a port, if any: the home fleet
## (wiki: ships-and-naval § Home Fleet).
static func home_fleet(
	fleets: Array[FleetState], player_faction: int, province_id: int
) -> FleetState:
	for fleet: FleetState in fleets:
		if fleet.owner != player_faction or not fleet.is_in_port():
			continue
		if fleet.province == province_id:
			return fleet
	return null


## Launches one paid-for hull into the home fleet, founding it at the slip when
## the crown keeps no squadron in that port. The view only mirrors what
## FleetYard already allowed. `roster` names the chart's fleet list the slip
## stands on: the Build/work pass hands over the seat's own chart, so a crown
## watching a colony when the turn closes still launches at its capital (wiki:
## capital-and-connectivity § Capital; world-model-identity). Empty reads the
## chart on screen.
static func launch_hull(
	layer: ShipLayer,
	province_id: int,
	type_id: String,
	economy: PlayerEconomy,
	flown: Array = [],
	roster: Array = []
) -> Dictionary:
	if layer == null:
		return {"ok": false, "reason": "No chart.", "hull": "", "type": ""}
	var fleets: Array = layer.fleets if roster.is_empty() else roster
	var live: bool = fleets == layer.fleets
	var fleet: FleetState = home_fleet(fleets, layer.player_faction, province_id)
	var founded: bool = fleet == null
	if founded:
		fleet = FleetState.empty_in_port(
			FleetRosters.next_id(fleets), layer.player_faction, province_id
		)
	var hull_id: String = "ship_%d" % layer.next_hull
	var result: Dictionary = FleetYard.launch(economy, fleet, type_id, hull_id, flown)
	if not bool(result.get("ok", false)):
		return result
	layer.next_hull += 1
	if founded:
		fleets.append(fleet)
	if live:
		if founded:
			layer.regions.set_region(layer.model.region_id, layer.fleets)
			layer.attach_marker(fleet)
			# The station takes a squadron more: the row and the stack are re-laid
			# so the newcomer never draws over a marker already there
			# (wiki: ships-and-naval § Fleets in one station).
			layer.relayout()
		layer.markers.hulls(fleet)
	result["created"] = founded
	result["fleet"] = fleet
	return result


## Breaks up one hull of an own squadron; an emptied fleet leaves the map
## (wiki: ships-and-naval § Ship muster and the breaker's yard).
static func scrap_hull(
	layer: ShipLayer, fleet: FleetState, hull_id: String, economy: PlayerEconomy
) -> Dictionary:
	if layer == null or fleet == null or fleet.owner != layer.player_faction:
		return {
			"ok": false,
			"reason": "Own colours only.",
			"hull": "",
			"type": "",
			"retired": false,
		}
	var result: Dictionary = FleetYard.scrap(economy, fleet, hull_id)
	if not bool(result.get("ok", false)) or not bool(result.get("retired", false)):
		layer.markers.hulls(fleet)
		return result
	layer.markers.remove(layer.ship_for(fleet))
	layer.fleets.erase(fleet)
	layer.regions.set_region(layer.model.region_id, layer.fleets)
	# A squadron leaves the station: the row closes up behind her
	# (wiki: ships-and-naval § Fleets in one station).
	layer.relayout()
	return result


## Re-reads a squadron's hulls onto its marker after a raid sank one.
static func refresh_hulls(layer: ShipLayer, fleet: FleetState) -> void:
	if layer == null or fleet == null:
		return
	layer.markers.hulls(fleet)
