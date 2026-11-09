class_name FleetMuster
extends RefCounted
## Builds one region's opening squadrons: who owns each fleet, where it starts
## and which hulls it carries. ShipLayer keeps markers, orders and battles;
## this pure mustering step stays free of nodes (REQ-P3-03) and small enough to
## test on its own (REQ-P3-01).

const PLAYER_FLEETS: int = 3
## Starting squadrons, cycling by fleet index (wiki: ships-and-naval roster).
## The player's three squadrons start small so naval food upkeep
## (2 per ship per turn) fits the opening stockpile.
const HULL_SETS: Array[Array] = [
	["carrack"],
	["sloop"],
	["fluyte"],
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
	for index in count:
		var owner: int = _owner_for_index(index, count, player_present, player)
		var fleet: FleetState = _make_fleet(model, index, owner, player_capital, player)
		_assign_hulls(fleet, index)
		fleets.append(fleet)
	return fleets


## Fleets belong to Great Powers only; the player owns squadrons where it holds land.
static func _owner_for_index(
	index: int, count: int, player_present: bool, player: int
) -> int:
	var powers: Array[int] = FactionCatalog.great_power_ids()
	var player_count: int = mini(PLAYER_FLEETS, count) if player_present else 0
	if index < player_count:
		return player
	var rivals: Array[int] = []
	for power: int in powers:
		if power != player:
			rivals.append(power)
	if rivals.is_empty():
		return player
	return rivals[(index - player_count) % rivals.size()]


func _make_fleet(
	model: MapModel, id: int, owner: int, player_capital: int, player: int
) -> FleetState:
	if owner == player and player_capital >= 0 and id == 2:
		# The home fleet: moored at the crown's seat, its merchant hulls carry
		# the opening trade cargo (wiki: ships-and-naval § Home Fleet).
		if NavalMovement.has_harbour(model, player_capital):
			return FleetState.in_port(id, owner, player_capital)
	var zones: Array[int] = _coastal_zones(model, owner)
	if zones.is_empty():
		for zone: SeaZoneState in model.sea_zones:
			zones.append(zone.id)
	if zones.is_empty():
		return FleetState.at_sea(id, owner, 0)
	var zone: int = zones[rng.randi_range(0, zones.size() - 1)]
	return FleetState.at_sea(id, owner, zone)


## Gives the fleet a deterministic starting squadron of typed hull instances.
func _assign_hulls(fleet: FleetState, index: int) -> void:
	var types: Array = HULL_SETS[index % HULL_SETS.size()]
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

