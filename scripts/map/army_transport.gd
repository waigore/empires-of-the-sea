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
		publish(layer)
		return
	var destination: Array[ArmyState] = roster(layer, to_region)
	destination.append(army)
	store(layer, to_region, destination)


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
			store(layer, index, members)
			if layer.model != null and index == layer.model.region_id:
				layer.prune_markers()
	return lost


## The deck every squadron keeps once the turn's hulls have left her. One hull
## carries one regiment or one colonist (wiki: ships-and-naval § Naval transport,
## § Civilian passengers), so a hull sunk in a battle or by a raid takes her
## passenger with her: the men a shorter deck cannot hold go down rather than
## ride it. An army the sea empties loses its place on the roster with the men
## ([method NavalDeck.trim_aboard]). Returns one row per squadron that lost
## someone — {fleet, owner, army, regiments[], civilians[]} — for the crown's news
## and the observer's trace.
static func reconcile_aboard(layer: ArmyLayer, fleets: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if layer == null:
		return rows
	var emptied: Array[ArmyState] = []
	for raw: Variant in fleets:
		var fleet: FleetState = raw
		if fleet == null:
			continue
		if fleet.embarked_army < 0 and not fleet.carries_civilians():
			continue
		var army: ArmyState = army_by_id(layer, fleet.embarked_army)
		var drowned: Dictionary = NavalDeck.trim_aboard(fleet, army)
		var men: Array = drowned["regiments"]
		var colonists: Array = drowned["civilians"]
		if men.is_empty() and colonists.is_empty():
			continue
		rows.append({
			"fleet": fleet.id,
			"owner": fleet.owner,
			"army": -1 if army == null else army.id,
			"regiments": men.duplicate(),
			"civilians": colonists.duplicate(),
		})
		if army != null and army.is_empty():
			emptied.append(army)
	if not emptied.is_empty():
		_strike(layer, emptied)
	return rows


## Takes an emptied standard off every roster the layer keeps, and its marker
## with it: an army with no regiments retires (wiki: military-armies § Dismissing
## regiments — an embarked army that retires leaves the deck with the field).
static func _strike(layer: ArmyLayer, emptied: Array[ArmyState]) -> void:
	for index in layer.regions.region_ids():
		var members: Array[ArmyState] = roster(layer, index)
		var kept: Array[ArmyState] = []
		for army: ArmyState in members:
			if army == null or not emptied.has(army):
				kept.append(army)
		if kept.size() == members.size():
			continue
		store(layer, index, kept)
		if layer.model != null and index == layer.model.region_id:
			layer.prune_markers()


## Re-seats the army a squadron carries on the squadron that now holds her hulls.
## A merge strikes the old command off the roster, so an army left pointing at her
## names a squadron no chart holds: the muster roll then loses the water she
## stands in and its own press finds no marker (wiki: military-armies § The muster
## roll — an embarked army stands under the squadron that carries it). The
## squadron's own roster is the gate for landing, so this is the book, not the
## rule.
static func seat_carried(layer: ArmyLayer, fleet: FleetState) -> void:
	if layer == null or fleet == null or fleet.embarked_army < 0:
		return
	var army: ArmyState = army_by_id(layer, fleet.embarked_army)
	if army != null and army.embarked_fleet != fleet.id:
		army.embarked_fleet = fleet.id


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


## Writes one region's roster to the chart's table and, when that region is the
## chart on screen, hands the very same list to the layer. Every pass that
## mutates a muster stores it here: a copy left in the table and a live list on
## the chart are two musters, and the save, the readings and the other chart's
## passes would each read a different one (wiki: campaign-persistence — a save
## holds armies and regiments; military-armies § Split and combine).
static func store(layer: ArmyLayer, region: int, stored: Array[ArmyState]) -> void:
	if layer == null:
		return
	layer.regions.set_region(region, stored)
	if layer.model != null and region == layer.model.region_id:
		layer.armies = stored


## Publishes the on-screen list back to its chart: every order that adds,
## retires or detaches a standard ends here, so the roster a save copies is the
## one the crown's own detach wrote.
static func publish(layer: ArmyLayer) -> void:
	if layer == null or layer.model == null:
		return
	store(layer, layer.model.region_id, layer.armies)


static func remove_from(layer: ArmyLayer, army: ArmyState, index: int) -> void:
	if layer.model != null and index == layer.model.region_id:
		layer.armies.erase(army)
		layer.remove_marker(army)
		publish(layer)
		return
	var members: Array[ArmyState] = roster(layer, index)
	members.erase(army)
	store(layer, index, members)


static func roster(layer: ArmyLayer, index: int) -> Array[ArmyState]:
	var members: Array[ArmyState] = []
	members.assign(layer.regions.value(index, []))
	return members
