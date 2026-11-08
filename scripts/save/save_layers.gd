class_name SaveLayers
extends RefCounted
## Serialises the map layers' hidden per-region caches without growing their
## public classes past the file-size bars. Layer instances stay the owners of
## the data; this module only reads and replaces it (REQ-P3-01, save/load).

# --- civilians ---------------------------------------------------------------


static func capture_civilians(layer: CivilianLayer) -> Dictionary:
	var works: Dictionary = {}
	for raw: Variant in layer._works_by_region.keys():
		var region: int = int(raw)
		var table: LandWorks = layer._works_by_region[raw]
		if table != null:
			works[region] = table.to_dict()
	var units: Dictionary = {}
	for raw: Variant in layer._units_by_region.keys():
		var region: int = int(raw)
		var roster: Array[CivilianState] = []
		roster.assign(layer._units_by_region[raw])
		var entries: Array[Dictionary] = []
		for unit: CivilianState in roster:
			if unit != null:
				entries.append(unit.to_dict())
		units[region] = entries
	return {"next_id": layer._next_id, "works": works, "units": units}


static func restore_civilians(layer: CivilianLayer, data: Dictionary) -> bool:
	if layer == null:
		return false
	layer._clear_markers()
	layer.units.clear()
	layer.selected_unit = null
	layer.works = null
	layer._works_by_region.clear()
	layer._units_by_region.clear()
	layer._next_id = maxi(int(data.get("next_id", 1)), 1)
	var works: Dictionary = data.get("works", {})
	for raw: Variant in works.keys():
		var entry: Variant = works[raw]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		layer._works_by_region[int(raw)] = LandWorks.from_dict(entry)
	var units: Dictionary = data.get("units", {})
	for raw: Variant in units.keys():
		var roster: Array[CivilianState] = []
		if typeof(units[raw]) != TYPE_ARRAY:
			layer._units_by_region[int(raw)] = roster
			continue
		var entries: Array = units[raw]
		for entry: Variant in entries:
			if typeof(entry) == TYPE_DICTIONARY:
				roster.append(CivilianState.from_dict(entry))
		layer._units_by_region[int(raw)] = roster
	return true


# --- fleets ------------------------------------------------------------------


static func capture_fleets(layer: ShipLayer) -> Dictionary:
	var fleets: Dictionary = {}
	for raw: Variant in layer._fleets_by_region.keys():
		var region: int = int(raw)
		var roster: Array[FleetState] = []
		roster.assign(layer._fleets_by_region[raw])
		var entries: Array[Dictionary] = []
		for fleet: FleetState in roster:
			if fleet != null:
				entries.append(fleet.to_dict())
		fleets[region] = entries
	return {"next_hull": layer._next_hull, "fleets": fleets}


static func restore_fleets(layer: ShipLayer, data: Dictionary) -> bool:
	if layer == null:
		return false
	for ship: Ship in layer.ships:
		if is_instance_valid(ship):
			ship.queue_free()
	layer.ships.clear()
	layer.selected_ship = null
	layer.fleets = []
	layer._fleets_by_region.clear()
	layer._next_hull = maxi(int(data.get("next_hull", 1)), 1)
	var fleets: Dictionary = data.get("fleets", {})
	for raw: Variant in fleets.keys():
		var roster: Array[FleetState] = []
		if typeof(fleets[raw]) != TYPE_ARRAY:
			layer._fleets_by_region[int(raw)] = roster
			continue
		var entries: Array = fleets[raw]
		for entry: Variant in entries:
			if typeof(entry) == TYPE_DICTIONARY:
				roster.append(FleetState.from_dict(entry))
		layer._fleets_by_region[int(raw)] = roster
	return true


# --- armies ------------------------------------------------------------------


static func capture_armies(layer: ArmyLayer) -> Dictionary:
	var armies: Dictionary = {}
	for raw: Variant in layer._armies_by_region.keys():
		var region: int = int(raw)
		var roster: Array[ArmyState] = []
		roster.assign(layer._armies_by_region[raw])
		var entries: Array[Dictionary] = []
		for army: ArmyState in roster:
			if army != null:
				entries.append(army.to_dict())
		armies[region] = entries
	return {
		"next_army": layer._next_army,
		"next_regiment": layer._next_regiment,
		"armies": armies,
	}


static func restore_armies(layer: ArmyLayer, data: Dictionary) -> bool:
	if layer == null:
		return false
	layer._clear_markers()
	layer.armies.clear()
	layer.selected_army = null
	layer._armies_by_region.clear()
	layer._next_army = maxi(int(data.get("next_army", 1)), 1)
	layer._next_regiment = maxi(int(data.get("next_regiment", 1)), 1)
	var armies: Dictionary = data.get("armies", {})
	for raw: Variant in armies.keys():
		var roster: Array[ArmyState] = []
		if typeof(armies[raw]) != TYPE_ARRAY:
			layer._armies_by_region[int(raw)] = roster
			continue
		var entries: Array = armies[raw]
		for entry: Variant in entries:
			if typeof(entry) == TYPE_DICTIONARY:
				roster.append(ArmyState.from_dict(entry))
		layer._armies_by_region[int(raw)] = roster
	return true
