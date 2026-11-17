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
## FleetYard already allowed.
static func launch_hull(
	layer: ShipLayer,
	province_id: int,
	type_id: String,
	economy: PlayerEconomy,
	flown: Array = []
) -> Dictionary:
	if layer == null:
		return {"ok": false, "reason": "No chart.", "hull": "", "type": ""}
	var fleet: FleetState = home_fleet(layer.fleets, layer.player_faction, province_id)
	var founded: bool = fleet == null
	if founded:
		fleet = FleetState.empty_in_port(
			FleetRosters.next_id(layer.fleets), layer.player_faction, province_id
		)
	var hull_id: String = "ship_%d" % layer.next_hull
	var result: Dictionary = FleetYard.launch(economy, fleet, type_id, hull_id, flown)
	if not bool(result.get("ok", false)):
		return result
	layer.next_hull += 1
	if founded:
		layer.fleets.append(fleet)
		layer.regions.set_region(layer.model.region_id, layer.fleets)
		layer.attach_marker(fleet)
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
	return result


## Re-reads a squadron's hulls onto its marker after a raid sank one.
static func refresh_hulls(layer: ShipLayer, fleet: FleetState) -> void:
	if layer == null or fleet == null:
		return
	layer.markers.hulls(fleet)
