class_name AiNavalPlanner
extends RefCounted
## Full-AI naval policy (docs/ai.md). A rival squadron engages a hostile fleet
## it can beat, threatens the best hostile coast, puts into a friendly harbour
## when a stronger fleet shares its zone, or cruises back to its own waters at
## peace. Pure rules: state in, orders out; the map layer applies them through
## NavalMovement so the AI never invents an outcome (REQ-P2-03, REQ-P3-03).

const KIND_ENGAGE: String = "engage"
const KIND_THREATEN: String = "threaten"
const KIND_DEFEND: String = "defend"
const KIND_STAGE: String = "stage"
const KIND_RETREAT: String = "retreat"

## Score weights and the battle margin live in AiParameterRegistry ("naval.*"),
## so a profile tunes the sea policy without code edits.


## One legal move per sea-going squadron, highest score wins. The home fleet
## (in port at the seat) and squadrons that already sailed stay put.
static func orders(
	config: AiConfig,
	state: DiplomacyState,
	model: MapModel,
	fleets: Array[FleetState]
) -> Dictionary:
	var orders: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or state == null or model == null:
		return {"orders": orders, "candidates": candidates}
	var owner: int = config.faction
	var hostile: Dictionary = _hostile_owners(state, owner)
	var seat: int = CapitalLoss.seat_of(model, owner)
	var coasts: Dictionary = _zone_coasts(model)
	var distances: Dictionary = _zone_distances(model, coasts, owner, hostile)
	for fleet: FleetState in _squadrons(fleets, owner, seat):
		var current: int = _distance_of(model, fleet, distances)
		var best: Dictionary = _best_order(
			config, model, fleet, fleets, hostile, seat, coasts, distances, current
		)
		if best.is_empty():
			continue
		var entry: Dictionary = {
			"fleet_id": fleet.id,
			"destination": int(best["destination"]),
			"zone": int(best.get("zone", MapModel.NO_ID)),
			"province": int(best.get("province", MapModel.NO_ID)),
			"kind": String(best["kind"]),
			"score": int(best["score"]),
		}
		candidates.append(entry)
		orders.append(entry.duplicate())
	return {"orders": orders, "candidates": candidates}


## Highest-scoring legal destination for one squadron. A fleet that shares its
## zone with a stronger fleet flees instead of sailing on.
static func _best_order(
	config: AiConfig,
	model: MapModel,
	fleet: FleetState,
	fleets: Array[FleetState],
	hostile: Dictionary,
	seat: int,
	coasts: Dictionary,
	distances: Dictionary,
	current: int
) -> Dictionary:
	var margin: int = config.parameter("naval.attack_margin_pct")
	if fleet.is_at_sea() and not _hostile_fleets(
		fleets, fleet.sea_zone, fleet.owner, hostile
	).is_empty():
		if not _can_beat(fleet, fleets, fleet.sea_zone, hostile, margin):
			var escape: Dictionary = _retreat(model, fleet, fleets, hostile, seat)
			if not escape.is_empty():
				return escape
			return {}
	var best: Dictionary = {}
	for zone: int in NavalMovement.destination_zones(model, fleet):
		var scored: Dictionary = _zone_score(
			config, model, fleet, fleets, zone, hostile, coasts, distances, current
		)
		if scored.is_empty():
			continue
		scored["destination"] = FleetState.Location.AT_SEA
		scored["zone"] = zone
		scored["province"] = MapModel.NO_ID
		if best.is_empty() or int(scored["score"]) > int(best["score"]):
			best = scored
		elif int(scored["score"]) == int(best["score"]) and zone < int(best["zone"]):
			best = scored
	return best


## Under a stronger fleet: dock at a friendly harbour (never the home-fleet
## seat, which a sea-going squadron may not join yet) or slip into an adjacent
## zone no hostile fleet holds.
static func _retreat(
	model: MapModel,
	fleet: FleetState,
	fleets: Array[FleetState],
	hostile: Dictionary,
	seat: int
) -> Dictionary:
	for province: int in NavalMovement.dockable_provinces(model, fleet):
		if province == seat:
			continue
		return {
			"destination": FleetState.Location.IN_PORT,
			"zone": MapModel.NO_ID,
			"province": province,
			"kind": KIND_RETREAT,
			"score": 1,
		}
	for zone: int in NavalMovement.destination_zones(model, fleet):
		if not _hostile_fleets(fleets, zone, fleet.owner, hostile).is_empty():
			continue
		return {
			"destination": FleetState.Location.AT_SEA,
			"zone": zone,
			"province": MapModel.NO_ID,
			"kind": KIND_RETREAT,
			"score": 1,
		}
	return {}


## What one destination zone is worth: a winnable battle, an enemy coast, a
## guard station that closes the distance, or a leg home.
static func _zone_score(
	config: AiConfig,
	model: MapModel,
	fleet: FleetState,
	fleets: Array[FleetState],
	zone: int,
	hostile: Dictionary,
	coasts: Dictionary,
	distances: Dictionary,
	current: int
) -> Dictionary:
	var margin: int = config.parameter("naval.attack_margin_pct")
	var enemy: Array = _hostile_fleets(fleets, zone, fleet.owner, hostile)
	if not enemy.is_empty():
		if not _can_beat(fleet, fleets, zone, hostile, margin):
			return {}
		return {
			"kind": KIND_ENGAGE,
			"score": (
				config.parameter("naval.engage_weight")
				+ int(round(NavalCombat.side_strength(enemy)))
			),
		}
	var threat: int = 0
	var guard: int = 0
	if not hostile.is_empty():
		for raw: Variant in coasts.get(zone, []):
			var province: int = int(raw)
			var province_owner: int = model.province_owner(province)
			if province_owner == fleet.owner:
				guard += _province_score(config, model, province)
			elif hostile.has(province_owner):
				threat += _province_score(config, model, province)
	if threat > 0:
		return {
			"kind": KIND_THREATEN,
			"score": config.parameter("naval.threat_weight") + threat,
		}
	var distance: int = int(distances.get(zone, 999))
	if distance >= current:
		return {}
	if guard > 0:
		return {
			"kind": KIND_DEFEND,
			"score": config.parameter("naval.defence_weight") + guard,
		}
	if distance >= 999:
		return {}
	return {
		"kind": KIND_STAGE,
		"score": -distance * config.parameter("naval.stage_distance_weight"),
	}


## Coastal value: population first, then a seat and a resource tile.
static func _province_score(config: AiConfig, model: MapModel, province: int) -> int:
	var data: ProvinceState = model.province_data(province)
	if data == null:
		return 0
	var score: int = (1 + data.population) * config.parameter("naval.province_weight")
	if data.capital:
		score += config.parameter("naval.capital_weight")
	if data.has_resource_tile():
		score += config.parameter("naval.resource_weight")
	return score


## Own side strength in the zone includes the fleet itself when it is still in
## port, so an undock is judged by the battle it would join.
static func _can_beat(
	fleet: FleetState,
	fleets: Array[FleetState],
	zone: int,
	hostile: Dictionary,
	margin: int
) -> bool:
	var enemy: Array = _hostile_fleets(fleets, zone, fleet.owner, hostile)
	if enemy.is_empty():
		return true
	var mine: float = NavalCombat.side_strength(_friendly_fleets(fleets, zone, fleet))
	var theirs: float = NavalCombat.side_strength(enemy)
	return mine * 100.0 >= theirs * float(margin)


## Factions this court is at war with, as a membership set.
static func _hostile_owners(state: DiplomacyState, owner: int) -> Dictionary:
	var hostile: Dictionary = {}
	for record: DiplomacyRelation in state.relations_of(owner):
		if record.at_war:
			hostile[record.other(owner)] = true
	return hostile


## Squadrons that may still sail: own, afloat, unmoved, and not the home fleet
## parked at the seat (wiki: ships-and-naval § Home Fleet).
static func _squadrons(
	fleets: Array[FleetState], owner: int, seat: int
) -> Array[FleetState]:
	var result: Array[FleetState] = []
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or not fleet.is_afloat():
			continue
		if fleet.moved:
			continue
		if fleet.is_in_port() and fleet.province == seat:
			continue
		result.append(fleet)
	result.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)
	return result


## Hostile fleets at sea in one zone; fleets in port never fight.
static func _hostile_fleets(
	fleets: Array[FleetState], zone: int, owner: int, hostile: Dictionary
) -> Array:
	var side: Array = []
	for other: FleetState in fleets:
		if other == null or other.owner == owner or not other.is_afloat():
			continue
		if not other.is_at_sea() or other.sea_zone != zone:
			continue
		if hostile.has(other.owner):
			side.append(other)
	return side


## Friendly hulls that would share the battle: same owner, at sea in the zone,
## plus this fleet even when it is still in port.
static func _friendly_fleets(
	fleets: Array[FleetState], zone: int, fleet: FleetState
) -> Array:
	var side: Array = []
	var included: bool = false
	for other: FleetState in fleets:
		if other == null or other.owner != fleet.owner or not other.is_afloat():
			continue
		if other.id == fleet.id:
			included = true
			side.append(other)
			continue
		if other.is_at_sea() and other.sea_zone == zone:
			side.append(other)
	if not included and fleet.is_afloat():
		side.append(fleet)
	return side


## Province ids touching each sea zone, built once per planner pass so the
## per-fleet scoring never rescans every province.
static func _zone_coasts(model: MapModel) -> Dictionary:
	var coasts: Dictionary = {}
	for province: ProvinceState in model.provinces:
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			var touched: Array = coasts.get(zone, [])
			touched.append(province.id)
			coasts[zone] = touched
	return coasts


## Sea-zone steps to the nearest prize: hostile coasts at war, own coasts at
## peace. Unreachable water stays absent (distance 999).
static func _zone_distances(
	model: MapModel, coasts: Dictionary, owner: int, hostile: Dictionary
) -> Dictionary:
	var distances: Dictionary = {}
	var queue: Array[int] = []
	for raw: Variant in coasts.keys():
		var zone: int = int(raw)
		for province_raw: Variant in coasts[raw]:
			var province_owner: int = model.province_owner(int(province_raw))
			var wanted: bool = (
				province_owner == owner if hostile.is_empty() else hostile.has(province_owner)
			)
			if not wanted:
				continue
			distances[zone] = 0
			queue.append(zone)
			break
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor: int in MapGeo.sea_zone_neighbors(model, current):
			if distances.has(neighbor):
				continue
			distances[neighbor] = int(distances[current]) + 1
			queue.append(neighbor)
	return distances


static func _distance_of(
	model: MapModel, fleet: FleetState, distances: Dictionary
) -> int:
	if fleet.is_at_sea():
		return int(distances.get(fleet.sea_zone, 999))
	var best: int = 999
	for zone: int in NavalMovement.province_sea_zones(model, fleet.province):
		best = mini(best, int(distances.get(zone, 999)))
	return best
