class_name NavalPortLoss
extends RefCounted
## Squadrons caught in a port that changes hands (wiki: ships-and-naval
## § Ports that change hands; DR-20261109-11, DR-20261109-12). Pure rules over
## map data and fleet state: the map layer only reports and repaints
## (REQ-P3-03), so a conquest resolves headless and the AI obeys the same rule.

const NO_ID: int = MapModel.NO_ID


## The sea zone a squadron sorts out into: the lowest-id zone bordering the
## province, or NO_ID when the province has no coast.
static func sortie_zone(model: MapModel, province_id: int) -> int:
	if model == null:
		return NO_ID
	var zones: Array[int] = NavalMovement.province_sea_zones(model, province_id)
	return zones[0] if not zones.is_empty() else NO_ID


## Re-moors a reassigned crown's in-port home squadron at its new seat. Returns
## {"moved": [reports], "merged": n, "ashore": [army ids]}. An inland seat
## changes nothing here: the eviction pass then sorts the stranded squadron out
## of the lost port.
static func relocate_home(
	model: MapModel,
	fleets: Array[FleetState],
	faction: int,
	lost: int,
	seat: int
) -> Dictionary:
	var moved: Array[Dictionary] = []
	var ashore: Array[int] = []
	if model == null or lost == NO_ID or seat == NO_ID or lost == seat:
		return {"moved": moved, "merged": 0, "ashore": ashore}
	if sortie_zone(model, seat) == NO_ID:
		return {"moved": moved, "merged": 0, "ashore": ashore}
	var target: FleetState = null
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != faction or not fleet.is_in_port():
			continue
		if fleet.province == seat and (target == null or fleet.id < target.id):
			target = fleet
	var merged: int = 0
	for fleet: FleetState in fleets.duplicate():
		if fleet == null or fleet.owner != faction or not fleet.is_in_port():
			continue
		if fleet.province != lost:
			continue
		if not fleet.is_afloat():
			fleets.erase(fleet)
			continue
		if target == null:
			fleet.province = seat
			target = fleet
			moved.append({
				"fleet": fleet.id, "owner": faction, "from": lost, "to": seat,
			})
			continue
		var displaced: int = target.merge_from(fleet)
		if displaced >= 0:
			ashore.append(displaced)
		fleets.erase(fleet)
		merged += 1
	return {"moved": moved, "merged": merged, "ashore": ashore}


## Sorts out every in-port squadron whose province is no longer its own. A
## squadron with no coast to sort into is scuttled (data-defect guard); an empty
## yard slip is dropped without a report.
static func evict_stranded(model: MapModel, fleets: Array[FleetState]) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if model == null:
		return reports
	for fleet: FleetState in fleets.duplicate():
		if fleet == null or not fleet.is_in_port():
			continue
		var data: ProvinceState = model.province_data(fleet.province)
		if data == null or data.owner == fleet.owner:
			continue
		if not fleet.is_afloat():
			fleets.erase(fleet)
			continue
		var province: int = fleet.province
		var zone: int = sortie_zone(model, province)
		if zone == NO_ID:
			fleets.erase(fleet)
			reports.append({
				"fleet": fleet.id,
				"owner": fleet.owner,
				"province": province,
				"zone": NO_ID,
				"scuttled": true,
			})
			continue
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = zone
		fleet.province = NO_ID
		fleet.moved = true
		reports.append({
			"fleet": fleet.id,
			"owner": fleet.owner,
			"province": province,
			"zone": zone,
			"scuttled": false,
		})
	return reports
