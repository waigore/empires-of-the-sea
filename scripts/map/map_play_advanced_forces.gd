class_name MapPlayAdvancedForces
extends RefCounted
## Musters the advanced-start Home Army roster and cargo hulls onto each Great
## Power's seat (wiki: advanced-starts § Tier tables). Session layer wiring
## only — tier counts live on AdvancedStart (REQ-P3-01).


## The tier's balanced regiment roster joins each Great Power's Home Army.
static func regiments(play: PlaySession, tier: String) -> void:
	var types: Array[String] = AdvancedStart.regiment_types(tier)
	if types.is_empty():
		return
	var armies: Array = play.army_layer.regions.value(0, [])
	play.army_layer.regions.set_region(0, armies)
	for faction: int in FactionCatalog.great_power_ids():
		var army: ArmyState = _home_army(armies, faction)
		if army == null:
			continue
		for type_id: String in types:
			var unit_id: String = "unit_%d" % play.army_layer.next_regiment
			play.army_layer.next_regiment += 1
			army.add_regiment(unit_id, type_id)


## Cargo hulls at each crown's own seat: the tier's galleon minimum, added to
## the squadron already in port or to a new one (wiki § Tier tables, Cargo ships).
static func ships(play: PlaySession, tier: String) -> int:
	var ships: int = AdvancedStart.cargo_ships(tier)
	var model: MapModel = play.world.region(0)
	if ships <= 0 or model == null:
		return 0
	var fleets: Array = play.ship_layer.regions.value(0, [])
	play.ship_layer.regions.set_region(0, fleets)
	var added: int = 0
	for faction: int in FactionCatalog.great_power_ids():
		var province: ProvinceState = _capital(model, faction)
		if province == null:
			continue
		var fleet: FleetState = _home_squadron(fleets, faction, province.id)
		if fleet == null:
			fleet = FleetState.in_port(fleets.size(), faction, province.id)
			fleets.append(fleet)
		var have: int = _galleons(fleet)
		for _index in maxi(ships - have, 0):
			var hull: String = "ship_%d" % play.ship_layer.next_hull
			play.ship_layer.next_hull += 1
			fleet.add_hull(hull, "galleon")
			added += 1
	return added


static func _home_army(armies: Array, faction: int) -> ArmyState:
	for raw: Variant in armies:
		var army: ArmyState = raw as ArmyState
		if army != null and army.owner == faction and army.is_home_army():
			return army
	return null


static func _home_squadron(
	fleets: Array, faction: int, province_id: int
) -> FleetState:
	for raw: Variant in fleets:
		var fleet: FleetState = raw as FleetState
		if fleet == null or fleet.owner != faction:
			continue
		if fleet.is_in_port() and fleet.province == province_id:
			return fleet
	return null


static func _galleons(fleet: FleetState) -> int:
	var count: int = 0
	for hull_id: String in fleet.hulls:
		if fleet.type_of(hull_id) == "galleon":
			count += 1
	return count


static func _capital(model: MapModel, faction: int) -> ProvinceState:
	for province: ProvinceState in model.provinces:
		if province.owner == faction and province.capital:
			return province
	return null
