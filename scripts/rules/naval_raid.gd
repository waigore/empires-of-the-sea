class_name NavalRaid
extends RefCounted
## Trade and transport raiding by patrol/blockade squadrons (wiki:
## ships-and-naval § Trade and Transport Interception). Pure rules: the home
## fleet's imports this turn are the cargo at risk; escorts cut the chance and
## a successful raid skims a fraction of every delivered commodity.
##
## Current product ships cargo raids only. Sinking civilian/home-fleet hulls is
## deferred with the rest of the civilian-ship model (DR-20261109-16).

const BLOCKADE_BONUS: float = 1.25
const MIN_EFFICIENCY: float = 0.3
const MAX_EFFICIENCY: float = 0.7


## One raider group tries the home fleet's cargo. `roll_value` is for tests; a
## negative value uses the deterministic campaign roll. `has_tech` is the
## crown-tech query: a raider holding Privateering Companies raids better
## (wiki: ships-and-naval § Trade and Transport Interception).
static func resolve(
	model: MapModel,
	fleets: Array,
	victim: int,
	home: FleetState,
	imports: Dictionary,
	hostile: Callable = Callable(),
	seed_value: int = 0,
	turn: int = 0,
	roll_value: float = -1.0,
	has_tech: Callable = Callable()
) -> Dictionary:
	if model == null or home == null or imports.is_empty():
		return {"ok": false, "reason": "no cargo at sea"}
	var relevant: Array[int] = _relevant_zones(model, victim)
	var groups: Dictionary = _raider_groups(model, fleets, victim, relevant, hostile)
	var owners: Array[int] = []
	for raw: Variant in groups.keys():
		owners.append(int(raw))
	owners.sort()
	var best_chance: float = 0.0
	for owner: int in owners:
		var group: Array = groups[owner] as Array
		var mission: int = FleetMissions.station_mission(model, group, hostile)
		if mission == FleetState.Mission.NONE:
			continue
		var escort: float = _escort_factor(home)
		# The trade-raid formula uses a common base chance times the blockade
		# bonus; the movement table's own mission factor would double-count it.
		var base: float = NavalInterception.chance(
			group, [home], FleetState.Mission.PATROL, has_tech
		)
		var bonus: float = (
			BLOCKADE_BONUS if mission == FleetState.Mission.BLOCKADE else 1.0
		)
		var found: float = clampf(
			base * bonus * (1.0 - escort),
			NavalInterception.MIN_CHANCE,
			NavalInterception.MAX_CHANCE
		)
		best_chance = maxf(best_chance, found)
		var rolled: float = roll_value
		if rolled < 0.0:
			rolled = NavalInterception.roll(
				seed_value, turn, int(group[0].sea_zone), owner, 77
			)
		if rolled >= found:
			continue
		var raider_strength: float = 0.0
		for fleet: FleetState in group:
			for hull_id: String in fleet.hulls:
				raider_strength += float(
					ShipStats.entry(fleet.type_of(hull_id)).get("hull", 0)
				)
		var defender_strength: float = _hull_strength(home)
		var efficiency: float = clampf(
			MIN_EFFICIENCY
			+ (MAX_EFFICIENCY - MIN_EFFICIENCY)
			* raider_strength / maxf(raider_strength + defender_strength, 0.001),
			MIN_EFFICIENCY,
			MAX_EFFICIENCY
		)
		var losses: Dictionary = _losses(imports, efficiency)
		var total: int = 0
		for raw_id: Variant in losses.keys():
			total += int(losses[raw_id])
		return {
			"ok": total > 0,
			"chance": found,
			"roll": rolled,
			"efficiency": efficiency,
			"raider": owner,
			"zone": int(group[0].sea_zone),
			"losses": losses,
			"lost_total": total,
		}
	return {"ok": false, "chance": best_chance, "losses": {}, "lost_total": 0}


## Skims floor(total × efficiency) units, at least one when any cargo is at sea,
## and spreads the loss across the commodities.
static func _losses(imports: Dictionary, efficiency: float) -> Dictionary:
	var ids: Array[String] = []
	var total_qty: int = 0
	for raw_id: Variant in imports.keys():
		ids.append(String(raw_id))
		total_qty += maxi(int(imports[raw_id]), 0)
	ids.sort()
	if total_qty <= 0:
		return {}
	var target: int = maxi(1, int(floor(float(total_qty) * efficiency)))
	var losses: Dictionary = {}
	var assigned: int = 0
	for id: String in ids:
		var quantity: int = maxi(int(imports[id]), 0)
		var take: int = mini(int(floor(float(quantity) * efficiency)), quantity)
		losses[id] = take
		assigned += take
	var remainder: int = target - assigned
	while remainder > 0:
		var pick: String = ""
		var room: int = 0
		for id: String in ids:
			var left: int = maxi(int(imports[id]), 0) - int(losses.get(id, 0))
			if left > room:
				room = left
				pick = id
		if pick.is_empty():
			break
		losses[pick] = int(losses[pick]) + 1
		remainder -= 1
	return losses


## Every sea zone bordering a coast the victim still holds.
static func _relevant_zones(model: MapModel, victim: int) -> Array[int]:
	var zones: Array[int] = []
	for province: ProvinceState in model.provinces:
		if province.owner != victim:
			continue
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			if not zones.has(zone):
				zones.append(zone)
	zones.sort()
	return zones


## At-sea patrol/blockade groups of hostile crowns inside the victim's waters.
static func _raider_groups(
	model: MapModel,
	fleets: Array,
	victim: int,
	relevant: Array[int],
	hostile: Callable
) -> Dictionary:
	var groups: Dictionary = {}
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner == victim or not fleet.is_at_sea():
			continue
		if not fleet.is_afloat() or not relevant.has(fleet.sea_zone):
			continue
		if not _hostile(hostile, fleet.owner, victim):
			continue
		if fleet.mission != FleetState.Mission.PATROL \
				and fleet.mission != FleetState.Mission.BLOCKADE:
			continue
		if fleet.mission == FleetState.Mission.BLOCKADE \
				and not FleetMissions.is_blockading(model, fleet, hostile):
			continue
		if not groups.has(fleet.owner):
			groups[fleet.owner] = []
		var group: Array = groups[fleet.owner]
		group.append(fleet)
	return groups


static func _escort_factor(home: FleetState) -> float:
	var cargo: float = 0.0
	var escort: float = 0.0
	for hull_id: String in home.hulls:
		var type_id: String = home.type_of(hull_id)
		var hull: float = float(ShipStats.entry(type_id).get("hull", 0))
		if ShipStats.is_warship(type_id):
			escort += hull
		else:
			cargo += hull
	if cargo <= 0.0:
		return 0.0
	return minf(0.5, escort / cargo * 0.3)


static func _hull_strength(home: FleetState) -> float:
	var total: float = 0.0
	for hull_id: String in home.hulls:
		total += float(ShipStats.entry(home.type_of(hull_id)).get("hull", 0))
	return total


static func _hostile(hostile: Callable, a: int, b: int) -> bool:
	if a == b:
		return false
	if not hostile.is_valid():
		return true
	return bool(hostile.call(a, b))
