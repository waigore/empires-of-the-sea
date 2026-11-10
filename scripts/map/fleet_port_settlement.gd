class_name FleetPortSettlement
extends RefCounted
## Applies the port-capture rules across every region's roster (wiki:
## ships-and-naval § Ports that change hands; DR-20261109-11, DR-20261109-12).
## Kept node-free so the layer only repaints and reports (REQ-P3-03).


## Returns {"reports": [...], "regions": [changed region ids], "sorties": [...]}.
static func settle(
	world: WorldMap, regions: MapRegionTable, reassigned: Array
) -> Dictionary:
	var reports: Array[Dictionary] = []
	var changed: Array[int] = []
	var sorties: Array[Dictionary] = []
	if world == null or regions == null:
		return {"reports": reports, "regions": changed, "sorties": sorties}
	for index in world.region_count():
		if not regions.has_region(index):
			continue
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var roster: Array[FleetState] = []
		roster.assign(regions.value(index, []))
		var touched: bool = false
		for entry: Dictionary in reassigned:
			if int(entry.get("region", -1)) != index:
				continue
			var result: Dictionary = NavalPortLoss.relocate_home(
				model,
				roster,
				int(entry["faction"]),
				int(entry["lost"]),
				int(entry["province"])
			)
			for row: Dictionary in result.get("moved", []):
				row["region"] = index
				reports.append(row)
				touched = true
			if int(result.get("merged", 0)) > 0:
				reports.append({
					"merged": int(result["merged"]),
					"owner": int(entry["faction"]),
					"to": int(entry["province"]),
					"region": index,
					"ashore": result.get("ashore", []),
				})
				touched = true
		for row: Dictionary in NavalPortLoss.evict_stranded(model, roster):
			row["region"] = index
			reports.append(row)
			touched = true
			if not bool(row.get("scuttled", false)):
				sorties.append({
					"fleet": int(row["fleet"]),
					"owner": int(row["owner"]),
					"zone": int(row["zone"]),
					"region": index,
				})
		if not touched:
			continue
		regions.set_region(index, roster)
		changed.append(index)
	return {"reports": reports, "regions": changed, "sorties": sorties}
