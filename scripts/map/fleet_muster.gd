class_name FleetMuster
extends RefCounted
## Builds one region's opening squadrons: one command per Great Power, moored in
## its home port at its capital when the power holds a seat on this chart and
## carrying every hull that power starts with (wiki: ships-and-naval
## § Home Fleet; issue #1043). ShipLayer keeps markers, orders and battles; this
## pure mustering step stays free of nodes (REQ-P3-03) and small enough to test
## on its own (REQ-P3-01).

## One home fleet per Great Power: every opening hull rides in it, so the
## opening musters no sea-going squadron (issue #1043).
const PLAYER_FLEETS: int = 1
## The crown's opening hulls in one home fleet: one warship, one sloop, and the
## merchant hull whose holds open the first trade (wiki: ships-and-naval
## § Home Fleet).
const PLAYER_HULLS: Array[String] = ["carrack", "sloop", "fluyte"]
## A rival's opening hulls, cycling by power order (wiki: ships-and-naval
## roster). They ride that rival's one home fleet, never separate squadrons.
const RIVAL_HULLS: Array[Array] = [
	["galleon", "carrack", "fluyte"],
	["sloop", "carrack"],
	["carrack", "carrack"],
	["frigate", "carrack"],
	["fluyte", "fluyte"],
]

## Hull ids stay unique for the life of the save; the layer hands its cursor
## in and takes the advanced value back (wiki: ships-and-naval § Ship instances).
var next_hull: int = 1
var rng := RandomNumberGenerator.new()


func build(
	model: MapModel,
	count: int,
	player_capital: int,
	player_present: bool,
	player: int
) -> Array[FleetState]:
	var fleets: Array[FleetState] = []
	var powers: Array[int] = FactionCatalog.great_power_ids()
	var rival_index: int = 0
	for index in mini(count, powers.size()):
		var owner: int = powers[index]
		if owner == player and not player_present:
			continue
		var capital: int = _capital(model, owner, player_capital, player)
		var fleet: FleetState = _make_fleet(model, index, owner, capital)
		_assign_hulls(fleet, _hulls_for(owner, player, rival_index))
		if owner != player:
			rival_index += 1
		fleets.append(fleet)
	# Every Great Power that seats a squadron keeps at least one fighting hull
	# so a lost warship can be rebuilt from craft already flown (issue #484).
	_ensure_warship(fleets, model, player_present, player)
	return fleets


## The power's seat on this chart, or [constant MapModel.NO_ID] when it holds
## none (the New World at game start): a home fleet needs a capital to moor in.
func _capital(model: MapModel, owner: int, player_capital: int, player: int) -> int:
	var capital: int = WorldBootstrap.capital_province(model, owner)
	if owner == player and capital == MapModel.NO_ID:
		capital = player_capital
	if capital < 0 or not NavalMovement.has_harbour(model, capital):
		return MapModel.NO_ID
	return capital


## The opening hull types of one power: the crown's fixed set, rivals cycling
## their own (issue #1043).
func _hulls_for(owner: int, player: int, rival_index: int) -> Array[String]:
	if owner == player:
		return PLAYER_HULLS.duplicate()
	var types: Array[String] = []
	types.assign(RIVAL_HULLS[rival_index % RIVAL_HULLS.size()])
	return types


## Adds a sloop to the first squadron of any owner that still has only merchants,
## or founds a new coastal squadron for a Great Power that drew no slot. Skips
## the player when they hold no land here — the crown's Old World craft still
## remembers the hull for rebuilds.
func _ensure_warship(
	fleets: Array[FleetState], model: MapModel, player_present: bool, player: int
) -> void:
	var has_warship: Dictionary = {}
	var next_id: int = 0
	for fleet: FleetState in fleets:
		if fleet == null:
			continue
		next_id = maxi(next_id, fleet.id + 1)
		if bool(has_warship.get(fleet.owner, false)):
			continue
		for hull_id: String in fleet.hulls:
			if ShipStats.is_warship(fleet.type_of(hull_id)):
				has_warship[fleet.owner] = true
				break
	for fleet: FleetState in fleets:
		if fleet == null or bool(has_warship.get(fleet.owner, false)):
			continue
		var hull_id: String = "ship_%d" % next_hull
		next_hull += 1
		fleet.add_hull(hull_id, "sloop")
		has_warship[fleet.owner] = true
	for power: int in FactionCatalog.great_power_ids():
		if bool(has_warship.get(power, false)):
			continue
		if not player_present and power == player:
			continue
		# Only a power with a seat on this chart gets a home fleet; a chart
		# without one musters none of its squadrons (issue #1043).
		var seat: int = WorldBootstrap.capital_province(model, power)
		if seat < 0:
			continue
		var fleet: FleetState = _make_fleet(model, next_id, power, seat)
		next_id += 1
		fleet.set_hulls([], {})
		var hull_id: String = "ship_%d" % next_hull
		next_hull += 1
		fleet.add_hull(hull_id, "sloop")
		fleets.append(fleet)
		has_warship[power] = true


func _make_fleet(model: MapModel, id: int, owner: int, capital: int) -> FleetState:
	if capital >= 0:
		# The home fleet: moored at the power's seat, its merchant hulls carry
		# the opening trade cargo (wiki: ships-and-naval § Home Fleet).
		return FleetState.in_port(id, owner, capital)
	var zones: Array[int] = _coastal_zones(model, owner)
	if zones.is_empty():
		for zone: SeaZoneState in model.sea_zones:
			zones.append(zone.id)
	if zones.is_empty():
		return FleetState.at_sea(id, owner, 0)
	var zone: int = zones[rng.randi_range(0, zones.size() - 1)]
	return FleetState.at_sea(id, owner, zone)


## Gives the fleet a deterministic starting squadron of typed hull instances.
func _assign_hulls(fleet: FleetState, types: Array[String]) -> void:
	var hull_ids: Array[String] = []
	var hull_types: Dictionary = {}
	for type_id: String in types:
		var hull_id: String = "ship_%d" % next_hull
		next_hull += 1
		hull_ids.append(hull_id)
		hull_types[hull_id] = type_id
	fleet.set_hulls(hull_ids, hull_types)


func _coastal_zones(model: MapModel, owner: int) -> Array[int]:
	var zones: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner != owner:
			continue
		var province_id: int = province.id
		for zone: int in NavalMovement.province_sea_zones(model, province_id):
			if not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones