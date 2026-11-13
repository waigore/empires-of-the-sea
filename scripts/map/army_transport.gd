class_name ArmyTransport
extends RefCounted
## Map-side transport plumbing for ArmyLayer: board, land, follow a passage and
## drown with a sunk squadron (wiki: ships-and-naval § Naval transport;
## DR-20261109-08). The rules live in NavalTransport; this only moves the
## roster entry and its marker between regions.


## Boards a field army on a squadron in port; the marker leaves the map.
static func embark(layer: ArmyLayer, army: ArmyState, fleet: FleetState) -> Dictionary:
	var result: Dictionary = NavalTransport.embark(layer.model, army, fleet)
	if not bool(result.get("ok", false)):
		return result
	layer.remove_marker(army)
	return result


## Lands the army its fleet carries on an owned coast or, with a ready
## beachhead, on the hostile coast it marked.
static func disembark(
	layer: ArmyLayer,
	fleet: FleetState,
	province_id: int,
	turn: int = 0,
	hostile: Callable = Callable()
) -> Dictionary:
	if fleet == null:
		return {"ok": false, "reason": "No fleet is selected."}
	var army: ArmyState = army_by_id(layer, fleet.embarked_army)
	var result: Dictionary = NavalTransport.disembark(
		layer.model, army, fleet, province_id, turn, hostile
	)
	if not bool(result.get("ok", false)):
		return result
	if layer.armies.has(army):
		layer.add_marker(army)
	return result


## Finds an army in the shown region or in any stored region roster.
static func army_by_id(layer: ArmyLayer, army_id: int) -> ArmyState:
	if army_id < 0:
		return null
	for army: ArmyState in layer.armies:
		if army != null and army.id == army_id:
			return army
	for index in layer.regions.region_ids():
		for army: ArmyState in roster(layer, index):
			if army != null and army.id == army_id:
				return army
	return null


## Carries an embarked army across a passage: the roster follows the fleet.
static func move_to_region(layer: ArmyLayer, army_id: int, to_region: int) -> void:
	var army: ArmyState = army_by_id(layer, army_id)
	if army == null or not army.is_embarked():
		return
	var from_region: int = region_of(layer, army)
	if from_region < 0 or from_region == to_region:
		return
	remove_from(layer, army, from_region)
	if layer.model != null and to_region == layer.model.region_id:
		layer.armies.append(army)
		layer.add_marker(army)
		layer.regions.set_region(to_region, layer.armies)
		return
	var destination: Array[ArmyState] = roster(layer, to_region)
	destination.append(army)
	layer.regions.set_region(to_region, destination)


## A sunken squadron takes its embarked army with it. `seats` maps every carried
## army to the live squadron that lists it (`FleetRosters.carried_armies`), so a
## seat renumbered by a passage or by a home-fleet merge is repaired here.
static func drop_lost(layer: ArmyLayer, seats: Dictionary) -> Array[ArmyState]:
	var lost: Array[ArmyState] = []
	for index in layer.regions.region_ids():
		var members: Array[ArmyState] = roster(layer, index)
		var changed: bool = false
		for cursor in range(members.size() - 1, -1, -1):
			var army: ArmyState = members[cursor]
			if army == null or not army.is_embarked():
				continue
			if seats.has(army.id):
				army.embarked_fleet = int(seats[army.id])
				continue
			lost.append(army)
			members.remove_at(cursor)
			changed = true
		if changed:
			layer.regions.set_region(index, members)
			if layer.model != null and index == layer.model.region_id:
				layer.armies = members
				layer.prune_markers()
	return lost


## Puts a surplus army ashore when two squadrons merge and only one can stay
## aboard (wiki: ships-and-naval § Naval transport — a squadron lands its army
## on its port province). The port is the crown's own, so no beachhead is
## needed; the landing spends the army's march.
static func put_ashore(layer: ArmyLayer, army_id: int, province_id: int) -> Dictionary:
	var army: ArmyState = army_by_id(layer, army_id)
	if army == null:
		return {"ok": false, "reason": "No army to land."}
	if layer.model == null or layer.model.province_owner(province_id) != army.owner:
		return {"ok": false, "reason": "That port is not ours."}
	army.province = province_id
	army.embarked_fleet = -1
	army.moved = true
	if layer.armies.has(army):
		layer.add_marker(army)
	return {"ok": true, "reason": "", "army": army}


static func region_of(layer: ArmyLayer, army: ArmyState) -> int:
	if layer.model != null and layer.armies.has(army):
		return layer.model.region_id
	for index in layer.regions.region_ids():
		if roster(layer, index).has(army):
			return index
	return -1


static func remove_from(layer: ArmyLayer, army: ArmyState, index: int) -> void:
	if layer.model != null and index == layer.model.region_id:
		layer.armies.erase(army)
		layer.remove_marker(army)
		return
	var members: Array[ArmyState] = roster(layer, index)
	members.erase(army)
	layer.regions.set_region(index, members)


static func roster(layer: ArmyLayer, index: int) -> Array[ArmyState]:
	var members: Array[ArmyState] = []
	members.assign(layer.regions.value(index, []))
	return members
