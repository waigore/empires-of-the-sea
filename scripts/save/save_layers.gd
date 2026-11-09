class_name SaveLayers
extends RefCounted
## Serialises the map layers' hidden per-region tables without growing their
## public classes past the file-size bars. Layers own a MapRegionTable; this
## module only walks that API and never reads private dictionaries (REQ-P3-02).

# --- civilians ---------------------------------------------------------------


static func capture_civilians(layer: CivilianLayer) -> Dictionary:
	return {
		"next_id": layer.next_id,
		"works": layer.works_regions.encode(_works_entry),
		"units": layer.regions.encode(_unit_entry),
	}


static func restore_civilians(layer: CivilianLayer, data: Dictionary) -> bool:
	if layer == null:
		return false
	layer._clear_markers()
	layer.units.clear()
	layer.selected_unit = null
	layer.works = null
	layer.works_regions.clear()
	layer.regions.clear()
	layer.next_id = maxi(int(data.get("next_id", 1)), 1)
	layer.works_regions.decode(_dictionary(data.get("works")), _works_from)
	layer.regions.decode(_dictionary(data.get("units")), _units_from)
	return true


# --- fleets ------------------------------------------------------------------


static func capture_fleets(layer: ShipLayer) -> Dictionary:
	return {"next_hull": layer.next_hull, "fleets": layer.regions.encode(_fleet_entry)}


static func restore_fleets(layer: ShipLayer, data: Dictionary) -> bool:
	if layer == null:
		return false
	layer.fleets = []
	layer.regions.clear()
	layer.next_hull = maxi(int(data.get("next_hull", 1)), 1)
	layer.regions.decode(_dictionary(data.get("fleets")), _fleets_from)
	return true


# --- armies ------------------------------------------------------------------


static func capture_armies(layer: ArmyLayer) -> Dictionary:
	return {
		"next_army": layer.next_army,
		"next_regiment": layer.next_regiment,
		"armies": layer.regions.encode(_army_entry),
	}


static func restore_armies(layer: ArmyLayer, data: Dictionary) -> bool:
	if layer == null:
		return false
	# The region reload that follows a restore rebuilds the markers from scratch.
	layer.armies.clear()
	layer.selected_army = null
	layer.regions.clear()
	layer.next_army = maxi(int(data.get("next_army", 1)), 1)
	layer.next_regiment = maxi(int(data.get("next_regiment", 1)), 1)
	layer.regions.decode(_dictionary(data.get("armies")), _armies_from)
	return true


# --- entries -----------------------------------------------------------------


static func _works_entry(works: LandWorks) -> Dictionary:
	return works.to_dict()


static func _unit_entry(unit: CivilianState) -> Dictionary:
	return unit.to_dict()


static func _fleet_entry(fleet: FleetState) -> Dictionary:
	return fleet.to_dict()


static func _army_entry(army: ArmyState) -> Dictionary:
	return army.to_dict()


static func _works_from(entry: Variant) -> Variant:
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	return LandWorks.from_dict(entry)


static func _units_from(entries: Variant) -> Array[CivilianState]:
	var roster: Array[CivilianState] = []
	if typeof(entries) != TYPE_ARRAY:
		return roster
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			roster.append(CivilianState.from_dict(entry))
	return roster


static func _fleets_from(entries: Variant) -> Array[FleetState]:
	var roster: Array[FleetState] = []
	if typeof(entries) != TYPE_ARRAY:
		return roster
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			roster.append(FleetState.from_dict(entry))
	return roster


static func _armies_from(entries: Variant) -> Array[ArmyState]:
	var roster: Array[ArmyState] = []
	if typeof(entries) != TYPE_ARRAY:
		return roster
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			roster.append(ArmyState.from_dict(entry))
	return roster


static func _dictionary(raw: Variant) -> Dictionary:
	return raw if typeof(raw) == TYPE_DICTIONARY else {}
