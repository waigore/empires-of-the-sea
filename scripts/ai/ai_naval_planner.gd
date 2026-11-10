class_name AiNavalPlanner
extends RefCounted
## Full-AI naval policy (docs/ai.md, wiki: ai-architecture § Naval policy).
## A court at war puts its sea-going squadrons onto the nearest hostile squadron
## it can match — a sortie out of an adjacent port, or a one-zone pursuit — and
## otherwise holds station, which is the wiki's Defend mission. A court at peace
## has nothing to sit on: every unengaged squadron sails home one legal step a
## turn and docks at the crown's own harbour, so its holds, its yard and its
## harbour roster are where the rules can use them (DR-20261110-30). Pure rules:
## state in, orders out; the map layer applies them through NavalMovement so the
## AI never invents an outcome (REQ-P2-03, REQ-P3-03).

const KIND_PURSUE: String = "pursue"
const KIND_SORTIE: String = "sortie"
const KIND_HOME: String = "home"


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
	var hostile: Dictionary = _hostile_owners(state, config.faction)
	for fleet: FleetState in _squadrons(fleets, config.faction):
		# At war a squadron hunts what it can match and holds station otherwise;
		# at peace it has no station to keep, so it sails home (DR-20261110-30).
		var order: Dictionary = (
			_best_target(config, model, fleets, fleet, hostile, charts)
			if not hostile.is_empty()
			else _home_order(model, fleet, config.faction, charts)
		)
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
		return {"kind": KIND_HOME, "dock": true, "province": port, "zone": MapModel.NO_ID}
	var goals: Array[int] = NavalMovement.province_sea_zones(model, port)
	var step: int = AiSeaRoute.sail_toward(model, fleet, goals)
	if step < 0 or not charts_water(charts, owner, model.region_id, step):
		return {}
	return {"kind": KIND_HOME, "dock": false, "province": MapModel.NO_ID, "zone": step}


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
	for zone: int in NavalMovement.destination_zones(model, fleet):
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


## Factions this court is at war with, as a membership set.
static func _hostile_owners(state: DiplomacyState, owner: int) -> Dictionary:
	var hostile: Dictionary = {}
	for record: DiplomacyRelation in state.relations_of(owner):
		if record.at_war:
			hostile[record.other(owner)] = true
	return hostile


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
