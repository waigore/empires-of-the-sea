class_name FleetMissions
extends RefCounted
## Station orders for sea-going squadrons (wiki: ships-and-naval § Missions and
## Movement; DR-20261109-16). Pure rules: a station spends the fleet's move, is
## stored on the fleet, and the map/AI only emit the intent (REQ-P3-03).

const PATROL_FACTOR: float = 0.5
const BLOCKADE_FACTOR: float = 0.9


static func id_of(mission: int) -> String:
	match mission:
		FleetState.Mission.PATROL:
			return "patrol"
		FleetState.Mission.BLOCKADE:
			return "blockade"
		FleetState.Mission.DEFEND:
			return "defend"
		FleetState.Mission.BEACHHEAD:
			return "beachhead"
		FleetState.Mission.MOVE:
			return "move"
	return "none"


static func from_id(id: String) -> int:
	match id:
		"patrol":
			return FleetState.Mission.PATROL
		"blockade":
			return FleetState.Mission.BLOCKADE
		"defend":
			return FleetState.Mission.DEFEND
		"beachhead":
			return FleetState.Mission.BEACHHEAD
		"move":
			return FleetState.Mission.MOVE
	return FleetState.Mission.NONE


static func label(mission: int) -> String:
	match mission:
		FleetState.Mission.PATROL:
			return "Patrol"
		FleetState.Mission.BLOCKADE:
			return "Blockade"
		FleetState.Mission.DEFEND:
			return "Defend"
		FleetState.Mission.BEACHHEAD:
			return "Beachhead"
		FleetState.Mission.MOVE:
			return "Move"
	return "No station"


## A station that keeps the squadron in its zone for the turn.
static func is_stationary(mission: int) -> bool:
	return (
		mission == FleetState.Mission.PATROL
		or mission == FleetState.Mission.BLOCKADE
		or mission == FleetState.Mission.DEFEND
	)


## Dossier line for the current station; empty when the squadron is free.
static func status_note(
	model: MapModel, fleet: FleetState, hostile: Callable = Callable()
) -> String:
	if fleet == null:
		return ""
	match fleet.mission:
		FleetState.Mission.PATROL:
			return "On patrol — hostile fleets entering this zone may be intercepted."
		FleetState.Mission.BLOCKADE:
			# The rules stop honouring a blockade whose coast changed hands or
			# made peace; the dossier must not keep claiming the station.
			if not is_blockading(model, fleet, hostile):
				return "The blockade has lapsed — the coast is no longer a hostile shore."
			var place: String = "the enemy coast"
			if model != null and fleet.blockade_province >= 0:
				place = model.province_name(fleet.blockade_province)
			return "Blockading %s — hostile fleets entering this zone may be intercepted." % place
		FleetState.Mission.DEFEND:
			return "Holding station — the squadron fights only when the zone is contested."
	return ""


## Enemy provinces this squadron could blockade from its current zone.
static func blockade_targets(
	model: MapModel, fleet: FleetState, hostile: Callable = Callable()
) -> Array[int]:
	if fleet == null or not fleet.is_at_sea():
		return []
	return NavalTransport.hostile_coasts(model, fleet, hostile)


## True when the squadron is still on a valid blockade of a hostile coast.
static func is_blockading(
	model: MapModel, fleet: FleetState, hostile: Callable = Callable()
) -> bool:
	if fleet == null or model == null or fleet.mission != FleetState.Mission.BLOCKADE:
		return false
	var province_id: int = fleet.blockade_province
	if province_id < 0 or model.province_data(province_id) == null:
		return false
	var owner: int = model.province_owner(province_id)
	if owner == fleet.owner or not _hostile(hostile, fleet.owner, owner):
		return false
	return NavalMovement.provinces_by_zone(model, fleet.sea_zone).has(province_id)


## The strongest station a group of squadrons is holding: blockade beats patrol.
static func station_mission(
	model: MapModel, group: Array, hostile: Callable = Callable()
) -> int:
	var patrol: bool = false
	for fleet: FleetState in group:
		if fleet.mission == FleetState.Mission.BLOCKADE and is_blockading(model, fleet, hostile):
			return FleetState.Mission.BLOCKADE
		if fleet.mission == FleetState.Mission.PATROL:
			patrol = true
	if patrol:
		return FleetState.Mission.PATROL
	return FleetState.Mission.NONE


## Validates a station without mutating the fleet.
static func can_assign(
	model: MapModel,
	fleet: FleetState,
	mission: int,
	province_id: int = MapModel.NO_ID,
	hostile: Callable = Callable()
) -> Dictionary:
	if fleet == null or model == null:
		return _deny("There is no squadron to order.")
	if mission != FleetState.Mission.PATROL \
			and mission != FleetState.Mission.BLOCKADE \
			and mission != FleetState.Mission.DEFEND:
		return _deny("That is not a station a squadron can take.")
	if NavalMovement.is_home_fleet(model, fleet):
		return _deny("The home fleet cannot take a station; launch a squadron instead.")
	if not fleet.is_afloat():
		return _deny("A squadron with no hulls cannot take a station.")
	if not fleet.is_at_sea():
		return _deny("A squadron must be at sea to take a station.")
	if fleet.moved:
		return _deny("This fleet has already moved or taken a station this turn.")
	if fleet.mission == mission:
		if mission != FleetState.Mission.BLOCKADE:
			return _deny("The squadron already holds that station.")
		if province_id == fleet.blockade_province:
			return _deny("The squadron already blockades that coast.")
	if mission == FleetState.Mission.BLOCKADE:
		if province_id < 0 or model.province_data(province_id) == null:
			return _deny("Choose an enemy province to blockade.")
		var owner: int = model.province_owner(province_id)
		if owner == fleet.owner:
			return _deny("A blockade needs an enemy coast.")
		if owner == MapModel.NO_ID:
			return _deny("That coast belongs to no crown.")
		if not _hostile(hostile, fleet.owner, owner):
			return _deny("A blockade needs a declared war with %s." % FactionCatalog.name_of(owner))
		if not NavalMovement.provinces_by_zone(model, fleet.sea_zone).has(province_id):
			return _deny("That coast does not border the fleet's sea zone.")
	return _allow()


## Takes the station for this turn and reports the player-facing line.
static func assign(
	model: MapModel,
	fleet: FleetState,
	mission: int,
	province_id: int = MapModel.NO_ID,
	hostile: Callable = Callable()
) -> Dictionary:
	var check: Dictionary = can_assign(model, fleet, mission, province_id, hostile)
	if not bool(check.get("ok", false)):
		return check
	fleet.clear_beachhead()
	fleet.mission = mission
	fleet.blockade_province = (
		province_id if mission == FleetState.Mission.BLOCKADE else MapModel.NO_ID
	)
	fleet.moved = true
	return {
		"ok": true,
		"reason": "",
		"mission": mission,
		"message": _message(model, fleet),
	}


## Σ interceptRating over a side's hulls.
static func intercept_score(group: Array) -> float:
	var total: float = 0.0
	for fleet: FleetState in group:
		for hull_id: String in fleet.hulls:
			total += float(ShipStats.entry(fleet.type_of(hull_id)).get("intercept", 0))
	return total


## Σ fleeRating over a side's hulls.
static func flee_score(group: Array) -> float:
	var total: float = 0.0
	for fleet: FleetState in group:
		for hull_id: String in fleet.hulls:
			total += float(ShipStats.entry(fleet.type_of(hull_id)).get("flee", 0))
	return total


## Mean MV over a side's hulls, for the retreat speed advantage.
static func avg_speed(group: Array) -> float:
	var total: float = 0.0
	var hulls: int = 0
	for fleet: FleetState in group:
		for hull_id: String in fleet.hulls:
			total += float(ShipStats.entry(fleet.type_of(hull_id)).get("mv", 0))
			hulls += 1
	if hulls <= 0:
		return 0.0
	return total / float(hulls)


static func _message(model: MapModel, fleet: FleetState) -> String:
	match fleet.mission:
		FleetState.Mission.PATROL:
			return "The squadron takes up patrol in the %s." % model.sea_zone_name(fleet.sea_zone)
		FleetState.Mission.BLOCKADE:
			return "The squadron blockades %s." % model.province_name(fleet.blockade_province)
		FleetState.Mission.DEFEND:
			return "The squadron holds station in the %s." % model.sea_zone_name(fleet.sea_zone)
	return "The squadron stands down."


static func _hostile(hostile: Callable, a: int, b: int) -> bool:
	if a == b:
		return false
	if not hostile.is_valid():
		return true
	return bool(hostile.call(a, b))


static func _allow() -> Dictionary:
	return {"ok": true, "reason": ""}


static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
