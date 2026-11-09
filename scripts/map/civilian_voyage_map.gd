class_name CivilianVoyageMap
extends RefCounted
## Map plumbing for civilians aboard squadrons (DR-20261109-17). Rules live in
## CivilianVoyage; this only hides/shows their medallion and moves roster
## entries between regions when the fleet crosses a passage.

const TILE_SIZE: float = 22.0


## Takes the medallion off the map while the civilian sails.
static func hide(layer: CivilianLayer, unit: CivilianState) -> void:
	var marker: CivilianMarker = layer.marker_for(unit)
	if marker != null:
		marker.visible = false


## Puts the medallion back on the tile the civilian just landed on.
static func show_ashore(layer: CivilianLayer, unit: CivilianState) -> void:
	var marker: CivilianMarker = layer.marker_for(unit)
	if marker == null:
		return
	if unit.tile.x >= 0 and unit.tile.y >= 0:
		marker.position = MapGeo.tile_center(unit.tile.x, unit.tile.y, TILE_SIZE)
	marker.visible = not unit.is_embarked()


## Carries a passenger into the destination region's roster. The caller reloads
## that region afterwards, so no marker is built here.
static func move_to_region(
	layer: CivilianLayer, unit_id: int, to_region: int
) -> void:
	var unit: CivilianState = by_id(layer, unit_id)
	if unit == null:
		return
	var from_region: int = region_of(layer, unit)
	if from_region < 0 or from_region == to_region:
		return
	var source: Array[CivilianState] = roster(layer, from_region)
	source.erase(unit)
	layer.regions.set_region(from_region, source)
	if layer.model != null and from_region == layer.model.region_id:
		layer.units = source
	var destination: Array[CivilianState] = roster(layer, to_region)
	destination.append(unit)
	layer.regions.set_region(to_region, destination)


## A sunken squadron takes its passengers with it. `seats` maps every carried
## civilian to the live squadron that still lists it
## (`FleetRosters.carried_civilians`), so a seat renumbered by a passage or by
## a home-fleet merge is repaired here instead of drowning a colonist that never
## left the ship.
static func drop_lost(
	layer: CivilianLayer, seats: Dictionary
) -> Array[CivilianState]:
	var lost: Array[CivilianState] = []
	var on_screen: bool = false
	for index in layer.regions.region_ids():
		var members: Array[CivilianState] = roster(layer, index)
		var changed: bool = false
		for cursor in range(members.size() - 1, -1, -1):
			var unit: CivilianState = members[cursor]
			if unit == null or not unit.is_embarked():
				continue
			if seats.has(unit.id):
				unit.embarked_fleet = int(seats[unit.id])
				continue
			lost.append(unit)
			members.remove_at(cursor)
			changed = true
		if not changed:
			continue
		layer.regions.set_region(index, members)
		if layer.model != null and index == layer.model.region_id:
			layer.units = members
			on_screen = true
	if on_screen:
		var none: Array[String] = []
		layer.spawn(layer.model, -1, -1, none, false)
	return lost


## Civilian by instance id across the shown region and every stored roster.
static func by_id(layer: CivilianLayer, unit_id: int) -> CivilianState:
	if layer == null or unit_id < 0:
		return null
	for unit: CivilianState in layer.units:
		if unit != null and unit.id == unit_id:
			return unit
	for index in layer.regions.region_ids():
		for unit: CivilianState in roster(layer, index):
			if unit != null and unit.id == unit_id:
				return unit
	return null


## Region a civilian currently belongs to, or -1.
static func region_of(layer: CivilianLayer, unit: CivilianState) -> int:
	if layer == null or unit == null:
		return -1
	if layer.model != null and layer.units.has(unit):
		return layer.model.region_id
	for index in layer.regions.region_ids():
		if roster(layer, index).has(unit):
			return index
	return -1


static func roster(layer: CivilianLayer, index: int) -> Array[CivilianState]:
	if layer.model != null and index == layer.model.region_id:
		return layer.units
	var members: Array[CivilianState] = []
	members.assign(layer.regions.value(index, []))
	return members
