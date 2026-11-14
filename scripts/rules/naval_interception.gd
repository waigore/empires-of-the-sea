class_name NavalInterception
extends RefCounted
## Patrol and blockade interception (wiki: ships-and-naval § Naval Interception
## Probability and § Missions and Movement). Pure rules and a deterministic
## roll keyed by seed, turn, zone and owners so identical inputs reproduce
## (REQ-P2-04, REQ-P3-03).

const MIN_CHANCE: float = 0.05
const MAX_CHANCE: float = 0.85
## Privateering Companies multiplies the intercepting crown's interceptRating
## before the documented clamps, on both movement interception and trade raids
## (wiki: ships-and-naval § Naval Interception Probability,
## § Trade and Transport Interception).
const PRIVATEERING_TECH: String = "privateering_companies"
const PRIVATEERING_BONUS: float = 1.25


## clamp(missionFactor × Σintercept / (Σintercept + Σflee), 0.05, 0.85).
## `has_tech` is the crown-tech query (owner, tech id) -> bool; only the
## intercepting owner's Privateering Companies counts.
static func chance(
	interceptors: Array, targets: Array, mission: int, has_tech: Callable = Callable()
) -> float:
	if interceptors.is_empty() or targets.is_empty():
		return 0.0
	var intercept: float = FleetMissions.intercept_score(interceptors)
	if privateers(interceptors, has_tech):
		intercept *= PRIVATEERING_BONUS
	var flee: float = FleetMissions.flee_score(targets)
	var total: float = intercept + flee
	if total <= 0.0:
		return MIN_CHANCE
	var factor: float = (
		FleetMissions.BLOCKADE_FACTOR
		if mission == FleetState.Mission.BLOCKADE
		else FleetMissions.PATROL_FACTOR
	)
	return clampf(factor * intercept / total, MIN_CHANCE, MAX_CHANCE)


## Stable 0..1 roll: the same seed, turn, zone and owners always roll alike.
## `salt` (default 1) decorrelates two draws made on the same key — cargo and a
## hull in one raid — so one unlucky number never decides both (DR-20261111-17).
static func roll(
	seed_value: int,
	turn: int,
	zone: int,
	first_owner: int,
	second_owner: int,
	salt: int = 1
) -> float:
	var key: int = (
		seed_value * 73856093 * salt
		+ turn * 19349663
		+ zone * 83492791
		+ first_owner * 2654435761
		+ second_owner * 40503
	)
	return float(posmod(key, 10000)) / 10000.0


## One interception attempt. A negative `roll_value` uses the stable roll.
static func attempt(
	zone: int,
	interceptors: Array,
	targets: Array,
	mission: int,
	seed_value: int = 0,
	turn: int = 0,
	roll_value: float = -1.0,
	has_tech: Callable = Callable()
) -> Dictionary:
	if interceptors.is_empty() or targets.is_empty():
		return {"ok": false, "chance": 0.0, "roll": 1.0, "mission": mission}
	var found: float = chance(interceptors, targets, mission, has_tech)
	var rolled: float = roll_value
	if rolled < 0.0:
		rolled = roll(
			seed_value, turn, zone,
			_owner(interceptors), _owner(targets)
		)
	return {
		"ok": rolled < found,
		"chance": found,
		"roll": rolled,
		"mission": mission,
	}


## Initiative for a contested zone: a patrol or blockade that intercepts an
## enemy becomes the attacker (wiki: ships-and-naval § Acceptance Criteria).
static func attacker_owner(
	zone: int,
	sides: Dictionary,
	hostile: Callable = Callable(),
	context: Dictionary = {}
) -> Dictionary:
	var owners: Array[int] = []
	for raw: Variant in sides.keys():
		owners.append(int(raw))
	owners.sort()
	if owners.is_empty():
		return {"owner": MapModel.NO_ID, "intercepted": false, "chance": 0.0}
	var model: MapModel = context.get("model") as MapModel
	var seed_value: int = int(context.get("seed", 0))
	var turn: int = int(context.get("turn", 0))
	var forced: float = float(context.get("interception_roll", -1.0))
	var has_tech: Callable = context.get("has_tech", Callable())
	var patrols: Array[Dictionary] = []
	for owner: int in owners:
		var group: Array = sides[owner] as Array
		var mission: int = FleetMissions.station_mission(model, group, hostile)
		if mission == FleetState.Mission.NONE:
			continue
		# Only the squadrons holding the station roll: a Defend squadron or one
		# merely passing through the zone is not part of the group
		# (DR-20261109-16).
		var holders: Array = _station_holders(model, group, hostile)
		if holders.is_empty():
			continue
		var targets: Array = []
		for other: int in owners:
			if other == owner or not Hostility.between(hostile, owner, other):
				continue
			for fleet: FleetState in sides[other] as Array:
				if fleet.is_at_sea() and fleet.is_afloat():
					targets.append(fleet)
		if targets.is_empty():
			continue
		var found: Dictionary = attempt(
			zone, holders, targets, mission, seed_value, turn, forced, has_tech
		)
		if bool(found.get("ok", false)):
			return {
				"owner": owner,
				"intercepted": true,
				"chance": float(found["chance"]),
				"mission": mission,
			}
		patrols.append({"owner": owner, "chance": float(found["chance"])})
	# No interception: the squadron that entered the zone attacks, else the
	# lowest owner id takes the initiative.
	var movers: Array[int] = []
	for owner: int in owners:
		for fleet: FleetState in sides[owner] as Array:
			if fleet.moved and not FleetMissions.is_stationary(fleet.mission):
				movers.append(owner)
				break
	movers.sort()
	var attacker: int = owners[0]
	if not movers.is_empty():
		attacker = movers[0]
	var best_chance: float = 0.0
	for row: Dictionary in patrols:
		best_chance = maxf(best_chance, float(row["chance"]))
	return {
		"owner": attacker,
		"intercepted": false,
		"chance": best_chance,
		"mission": FleetState.Mission.NONE,
	}


## The squadrons actually holding a station this turn: Patrol, or a blockade
## that still stands. Everything else in the zone is a bystander for the roll
## (DR-20261109-16: "each Patrol/Blockade group attempts interception").
static func _station_holders(
	model: MapModel, group: Array, hostile: Callable
) -> Array:
	var holders: Array = []
	for fleet: FleetState in group:
		if fleet.mission == FleetState.Mission.PATROL:
			holders.append(fleet)
		elif fleet.mission == FleetState.Mission.BLOCKADE \
				and FleetMissions.is_blockading(model, fleet, hostile):
			holders.append(fleet)
	return holders


## True when the intercepting crown holds Privateering Companies. The tech is
## read through the caller's query so rules never reach into a ledger
## (REQ-P2-03, REQ-P3-03).
static func privateers(group: Array, has_tech: Callable) -> bool:
	if group.is_empty() or not has_tech.is_valid():
		return false
	return bool(has_tech.call(_owner(group), PRIVATEERING_TECH))


static func _owner(group: Array) -> int:
	for fleet: FleetState in group:
		return fleet.owner
	return 0
