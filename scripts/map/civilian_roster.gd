class_name CivilianRoster
extends RefCounted
## Roster housekeeping that follows a change of ownership: crown-land crews
## caught behind new borders withdraw or leave play, and a fallen crown's
## civilians leave with its regiments and squadrons. Kept out of `CivilianLayer`
## so the layer stays inside its size bar (RUB-P3-01); the passes only touch the
## layer's public roster table and repaint through its public helpers.


## Withdraws stranded crown-land crews in every region. Returns one report per
## affected crew (see `CivilianStranding`).
static func settle_stranding(layer: CivilianLayer, world: WorldMap) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	if layer == null or world == null:
		return reports
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		var roster: Array[CivilianState] = _roster_for(layer, index)
		var affected: Array[Dictionary] = CivilianStranding.withdraw(model, roster)
		if affected.is_empty():
			continue
		for report: Dictionary in affected:
			report["region"] = index
			reports.append(report)
		_store(layer, index, roster)
	return reports


## Removes every civilian a crown fielded, across every region: a terminal fall
## takes its units out of play with its regiments and squadrons.
static func remove_owner(layer: CivilianLayer, owner: int) -> int:
	var removed: int = 0
	if layer == null:
		return removed
	var touched: Dictionary = {}
	for index in layer.regions.region_ids():
		touched[index] = true
	if layer.model != null:
		touched[layer.model.region_id] = true
	for index: int in touched.keys():
		var roster: Array[CivilianState] = _roster_for(layer, index)
		for position in range(roster.size() - 1, -1, -1):
			var unit: CivilianState = roster[position]
			if unit == null or unit.owner != owner:
				continue
			roster.remove_at(position)
			removed += 1
		_store(layer, index, roster)
	return removed


## The live array for a region: the on-screen roster is the same object the
## layer draws from, so edits must land in it rather than a copy.
static func _roster_for(layer: CivilianLayer, index: int) -> Array[CivilianState]:
	if layer.model != null and index == layer.model.region_id:
		return layer.units
	var roster: Array[CivilianState] = []
	roster.assign(layer.regions.value(index, []))
	return roster


## Writes a changed roster back and repaints the visible region.
static func _store(layer: CivilianLayer, index: int, roster: Array[CivilianState]) -> void:
	layer.regions.set_region(index, roster)
	if layer.model == null or index != layer.model.region_id:
		return
	layer.units = roster
	if layer.selected_unit != null and not roster.has(layer.selected_unit):
		layer.selected_unit = null
	layer._rebuild_markers()
	layer.refresh_works()
