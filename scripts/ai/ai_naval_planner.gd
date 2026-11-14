class_name AiNavalPlanner
extends RefCounted
## Full-AI naval policy (docs/ai.md, wiki: ai-architecture § Naval policy).
## A court at war puts its sea-going squadrons onto the nearest hostile squadron
## it can match — a sortie out of an adjacent port, or a one-zone pursuit — and
## failing that sends its warships to work the enemy's trade, blockading a coast
## where the raid takes cargo and merchant hulls (DR-20261111-17). A court at
## peace has nothing to sit on: every unengaged squadron sails home one legal
## step a turn and docks at the crown's own harbour, so its holds, its yard and
## its harbour roster are where the rules can use them (DR-20261110-30). Pure
## rules: state in, orders out; the map layer applies them through NavalMovement
## so the AI never invents an outcome (REQ-P2-03, REQ-P3-03).

const KIND_PURSUE: String = "pursue"
const KIND_SORTIE: String = "sortie"
const KIND_HOME: String = "home"
## A warship with no squadron to fight sails for a hostile coast to raid its
## trade (DR-20261111-17): the move is the first leg of that station.
const KIND_RAID: String = "raid"


## One order per sea-going squadron: the zone to enter and the strength it means
## to face. `candidates` mirrors `orders` for the turn trace. `charts` is the
## courts' charts: a rival hunts only in water its own chart holds, and a hull
## it has never charted is not a target (wiki: fog-and-exploration § Visibility
## Levels, ai-architecture § Naval policy; DR-20261110-21). A null chart keeps
## the every-zone behaviour the fixtures use.
static func orders(
	config: AiConfig,
	state: DiplomacyState,
	model: MapModel,
	fleets: Array,
	charts: CourtCharts = null
) -> Dictionary:
	var planned: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or state == null or model == null:
		return {"orders": planned, "candidates": candidates}
	var hostile: Dictionary = Hostility.owners(state, config.faction)
	for fleet: FleetState in _squadrons(fleets, config.faction):
		# At war a squadron hunts what it can match, then works the enemy's
		# trade; at peace it has no station to keep, so it sails home
		# (DR-20261110-30, DR-20261111-17).
		var order: Dictionary = {}
		if not hostile.is_empty():
			order = _best_target(config, model, fleets, fleet, hostile, charts)
			if order.is_empty():
				order = _raid_order(
					model, fleets, fleet, config.faction, hostile, charts
				)
			# `_raid_order` answers `hold` for a warship already on a hostile
			# coast: the station pass works it, and it must not sail home.
			if bool(order.get("hold", false)):
				order = {}
			elif order.is_empty():
				# Nowhere to fight and no trade to work: bring the hulls home,
				# where holds and escorts are worth something (DR-20261110-30).
				order = _home_order(model, fleet, config.faction, charts)
		else:
			order = _home_order(model, fleet, config.faction, charts)
		if order.is_empty():
			continue
		order["fleet_id"] = fleet.id
		candidates.append(order.duplicate())
		planned.append(order)
	return {"orders": planned, "candidates": candidates}


## The harbour a court calls home: its seat when the seat is still its own and
## has a harbour, else the lowest-id own harbour. -1 when the crown holds no
## harbour at all (an inland capital with no coast), so nothing can dock.
static func home_port(model: MapModel, owner: int) -> int:
	if model == null:
		return -1
	var seat: int = WorldBootstrap.capital_province(model, owner)
	if seat >= 0 and NavalMovement.has_harbour(model, seat):
		return seat
	for province: ProvinceState in model.provinces:
		if province == null or model.province_owner(province.id) != owner:
			continue
		if NavalMovement.has_harbour(model, province.id):
			return province.id
	return -1


## One step home for an unengaged squadron: dock when the home harbour borders
## its zone, else the next charted zone on the sea path. A squadron on a station
## (patrol, blockade, beachhead) or carrying an expedition keeps its post.
static func _home_order(
	model: MapModel, fleet: FleetState, owner: int, charts: CourtCharts
) -> Dictionary:
	if fleet.is_in_port() or _stationed(fleet):
		return {}
	var port: int = home_port(model, owner)
	if port < 0:
		return {}
	if NavalMovement.dockable_provinces(model, fleet).has(port):
		return {
			"kind": KIND_HOME,
			"dock": true,
			"province": port,
			"zone": MapModel.NO_ID,
			"threat": 0,
		}
	var goals: Array[int] = NavalMovement.province_sea_zones(model, port)
	var step: int = AiSeaRoute.sail_toward(model, fleet, goals)
	if step < 0 or not charts_water(charts, owner, model.region_id, step):
		return {}
	return {
		"kind": KIND_HOME,
		"dock": false,
		"province": MapModel.NO_ID,
		"zone": step,
		"threat": 0,
	}


## A squadron with orders of its own does not run for home: a station spends its
## turn where it is, and an expedition's hulls belong to the invasion planner.
static func _stationed(fleet: FleetState) -> bool:
	if fleet.has_beachhead():
		return true
	if not fleet.embarked_civilians.is_empty():
		return true
	return fleet.mission != FleetState.Mission.NONE and fleet.mission != FleetState.Mission.DEFEND


## True when this court's chart holds the sea zone; a null chart (a fixture)
## answers yes, so the published policy is what every other test reads.
static func charts_water(
	charts: CourtCharts, faction: int, region: int, zone: int
) -> bool:
	if charts == null:
		return true
	return charts.knows_zone(faction, region, zone)


## Sea zones this squadron could enter this turn. A home squadron sorties out of
## the seat's port — ships leave the home fleet when they receive a naval move
## order (FleetSortie, DR-20261109-17) — so its reach is the water beside the
## capital; a sea-going squadron reads NavalMovement's own list.
static func _destinations(model: MapModel, fleet: FleetState) -> Array[int]:
	if NavalMovement.is_home_fleet(model, fleet):
		return FleetSortie.zones(model, fleet)
	return NavalMovement.destination_zones(model, fleet)


## True when a hostile hull is afloat in water this squadron could enter.
static func _hostile_beside(
	model: MapModel, fleets: Array, fleet: FleetState, hostile: Dictionary
) -> bool:
	for zone: int in _destinations(model, fleet):
		if _hostile_strength(fleets, zone, hostile) > 0.0:
			return true
	return false


## Weakest reachable hostile squadron this turn, or empty when every reachable
## one is a fight the court declines. Anchored ports sortie, sea squadrons
## pursue; both enter exactly one adjacent zone (NavalMovement owns legality).
static func _best_target(
	config: AiConfig,
	model: MapModel,
	fleets: Array,
	fleet: FleetState,
	hostile: Dictionary,
	charts: CourtCharts = null
) -> Dictionary:
	var own: float = NavalCombat.side_strength([fleet])
	var kind: String = KIND_SORTIE if fleet.is_in_port() else KIND_PURSUE
	var best: Dictionary = {}
	var best_threat: float = 0.0
	for zone: int in _destinations(model, fleet):
		# A court hunts only in water its own chart holds; a hull it has never
		# charted is not a target (REQ-P2-03).
		if not charts_water(charts, config.faction, model.region_id, zone):
			continue
		var threat: float = _hostile_strength(fleets, zone, hostile)
		if threat <= 0.0 or not _can_engage(config, own, threat):
			continue
		# Compare the true side strength: rounding first would let a stronger
		# squadron win only because its zone id sorts lower (wiki: ai-architecture
		# § Naval policy — "weakest hostile squadron it can reach").
		if best.is_empty() or threat < best_threat:
			best = {"zone": zone, "kind": kind, "threat": int(ceil(threat))}
			best_threat = threat
		elif is_equal_approx(threat, best_threat) and zone < int(best["zone"]):
			best = {"zone": zone, "kind": kind, "threat": int(ceil(threat))}
	return best


## A warship with no squadron to fight works the enemy's trade: one legal step
## toward a hostile coast, where the station pass posts a blockade and the raid
## takes cargo and merchant hulls (DR-20261111-17). A home squadron sorties out
## of the seat to do it (DR-20261109-17), but only when the water beside the port
## is clear: a fight it declines is still a threat to its own harbour, so it
## keeps the seat instead. A coast whose seat holds a laden merchant squadron is
## worth the farther trip; a merchant-only squadron stays out of it, and a
## warship already on a hostile coast holds for its station instead of sailing
## away.
static func _raid_order(
	model: MapModel,
	fleets: Array,
	fleet: FleetState,
	faction: int,
	hostile: Dictionary,
	charts: CourtCharts
) -> Dictionary:
	if _has_warship(fleet) == false:
		return {}
	if NavalMovement.is_home_fleet(model, fleet) and _hostile_beside(
		model, fleets, fleet, hostile
	):
		return {"hold": true}
	var laden: Array[int] = []
	var coasts: Array[int] = []
	_trade_goals(model, fleets, faction, hostile, charts, laden, coasts)
	if laden.has(fleet.sea_zone):
		return {"hold": true}
	var step: int = _step_for(model, fleet, laden)
	if step < 0:
		step = _step_for(model, fleet, coasts)
	if step < 0:
		return {"hold": true} if coasts.has(fleet.sea_zone) else {}
	if not charts_water(charts, faction, model.region_id, step):
		return {}
	return {"kind": KIND_RAID, "zone": step, "threat": 0}


## Charted sea zones beside a hostile coast, split into the coasts whose seat
## holds merchant tonnage (`laden`) and every other hostile shore (`coasts`).
static func _trade_goals(
	model: MapModel,
	fleets: Array,
	faction: int,
	hostile: Dictionary,
	charts: CourtCharts,
	laden: Array[int],
	coasts: Array[int]
) -> void:
	for province: ProvinceState in model.provinces:
		if province == null:
			continue
		var owner: int = model.province_owner(province.id)
		if owner == faction or not hostile.has(owner):
			continue
		var rich: bool = _home_holds(fleets, owner, province.id)
		for zone: int in NavalMovement.province_sea_zones(model, province.id):
			if not charts_water(charts, faction, model.region_id, zone):
				continue
			var bucket: Array[int] = laden if rich else coasts
			if not bucket.has(zone):
				bucket.append(zone)


## True when `owner` keeps a merchant squadron in port at `province`, the laden
## home fleet a raid can actually strip of cargo and hulls.
static func _home_holds(fleets: Array, owner: int, province: int) -> bool:
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or not fleet.is_in_port():
			continue
		if fleet.province == province and TradeCargo.fleet_holds(fleet) > 0:
			return true
	return false


## First leg toward the nearest goal, or -1 when already there or unreachable.
static func _step_for(model: MapModel, fleet: FleetState, goals: Array[int]) -> int:
	if goals.is_empty() or goals.has(fleet.sea_zone):
		return -1
	return AiSeaRoute.sail_toward(model, fleet, goals)


## A commerce raider needs a warship: a merchant squadron is cargo, not a
## predator (wiki: ships-and-naval § Ship Types).
static func _has_warship(fleet: FleetState) -> bool:
	for hull_id: String in fleet.hulls:
		if ShipStats.is_warship(fleet.type_of(hull_id)):
			return true
	return false


## The caution knob keeps a rival from feeding a squadron to a far stronger
## fleet; it never changes what the combat rules then decide.
static func _can_engage(config: AiConfig, own: float, threat: float) -> bool:
	var margin: float = float(config.parameter("naval.caution_margin_pct"))
	return threat * 100.0 <= own * margin


## Every hostile hull afloat in one zone, as combined side strength.
static func _hostile_strength(fleets: Array, zone: int, hostile: Dictionary) -> float:
	var present: Array = []
	for fleet: FleetState in fleets:
		if fleet == null or not fleet.is_at_sea() or not fleet.is_afloat():
			continue
		if fleet.sea_zone != zone or not hostile.has(fleet.owner):
			continue
		present.append(fleet)
	if present.is_empty():
		return 0.0
	return NavalCombat.side_strength(present)


## Own squadrons that can still sail: afloat, un-moved, in id order. A squadron
## carrying an expedition army keeps its course — AiInvasionPlanner steers it
## (wiki: ai-architecture § Overseas invasions).
static func _squadrons(fleets: Array, owner: int) -> Array[FleetState]:
	var own: Array[FleetState] = []
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or fleet.moved or not fleet.is_afloat():
			continue
		if fleet.embarked_army >= 0:
			continue
		own.append(fleet)
	own.sort_custom(func(a: FleetState, b: FleetState) -> bool: return a.id < b.id)
	return own
