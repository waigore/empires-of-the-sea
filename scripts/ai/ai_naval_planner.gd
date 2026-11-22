class_name AiNavalPlanner
extends RefCounted
## Full-AI naval policy (docs/ai.md, wiki: ai-architecture § Naval policy).
## A court at war puts its sea-going warships onto the nearest hostile squadron
## they can match — a sortie out of an adjacent port, or a one-zone pursuit — and
## failing that sends its warships to work the enemy's trade, blockading a coast
## where the raid takes cargo and merchant hulls (DR-20261111-17). A court at
## peace has nothing to sit on: every unengaged squadron sails home one legal
## step a turn and docks at the crown's own harbour, so its holds, its yard and
## its harbour roster are where the rules can use them (DR-20261110-30). A
## merchant hull — a convoy — can pick no fight and works no coast: the trace
## names its one sail, home or berth-guard, so a port fleet reads as what its
## hulls are (ships-and-naval § Ship Types; issue #1258). Pure rules: state in,
## orders out; the map layer applies them through NavalMovement so the AI never
## invents an outcome (REQ-P2-03, REQ-P3-03).
##
## This module owns the turn's policy — who hunts, who holds and who comes home.
## The water a station order crosses belongs to [AiNavalStation], and what a
## squadron is or where it can reach belongs to [AiSquadronReads]; neither is
## read twice here (REQ-P3-01).
##
## The footing's naval slot (`navy.missions`, DR-20261117-01) is the caller's
## read: an **overstretched** court opens no new commerce station — a squadron
## with no fight to pick sails home instead of working a hostile coast — while a
## station already posted keeps its post and a court at one front raids as
## published.

const KIND_PURSUE: String = "pursue"
const KIND_SORTIE: String = "sortie"
const KIND_HOME: String = "home"
## A warship with no squadron to fight sails for a hostile coast to raid its
## trade (DR-20261111-17): the move is the first leg of that station.
const KIND_RAID: String = "raid"
## A merchant hull that leaves port sails a convoy, not a war sortie (wiki:
## ships-and-naval § Ship Types; issue #1258): the trace must name the move so
## a port fleet reads as what its hulls are.
const KIND_CONVOY: String = "convoy"
## Why a squadron gives up its station and makes for home: it carries the holds
## its court keeps its imports with, and the court has none in port at its seat
## (wiki: ships-and-naval § Cargo holds and capacity; issue #530).
const REASON_TRADE: String = "trade"
## Why a squadron opens no commerce station: the court fights two Great Powers
## and keeps its hulls on its own water (DR-20261117-01).
const REASON_FRONTS: String = "overstretched: no new raid"


## One order per sea-going squadron: the zone to enter and the strength it means
## to face. `candidates` mirrors `orders` for the turn trace. `charts` is the
## courts' charts: a rival hunts only in water its own chart holds, and a hull
## it has never charted is not a target (wiki: fog-and-exploration § Visibility
## Levels, ai-architecture § Naval policy; DR-20261110-21). A null chart keeps
## the every-zone behaviour the fixtures use. `phase` is the court's war footing
## as the dispatch reads it: an overstretched court opens no new commerce station
## (DR-20261117-01), and an unknown footing plays the published policy.
static func orders(
	config: AiConfig,
	state: DiplomacyState,
	model: MapModel,
	fleets: Array,
	charts: CourtCharts = null,
	phase: String = AiPhasePlanner.PHASE_UNKNOWN
) -> Dictionary:
	var planned: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	if config == null or state == null or model == null:
		return {"orders": planned, "candidates": candidates}
	var hostile: Dictionary = Hostility.owners(state, config.faction)
	# The footing's naval slot: an overstretched court opens no new commerce
	# station and keeps its hulls on its own water (DR-20261117-01).
	var raids: bool = AiPhasePlanner.opens(phase, AiPhasePlanner.SLOT_NAVAL)
	for fleet: FleetState in AiSquadronReads.sailing(fleets, config.faction):
		# At war a squadron hunts what it can match, then works the enemy's
		# trade; at peace it has no station to keep, so it sails home
		# (DR-20261110-30, DR-20261111-17).
		var order: Dictionary = _order_for(
			config, model, fleets, fleet, hostile, charts, raids
		)
		if order.is_empty():
			continue
		order["fleet_id"] = fleet.id
		candidates.append(order.duplicate())
		planned.append(order)
	return {"orders": planned, "candidates": candidates}


## The turn's one sail for a squadron that is still free to move.
static func _order_for(
	config: AiConfig,
	model: MapModel,
	fleets: Array,
	fleet: FleetState,
	hostile: Dictionary,
	charts: CourtCharts,
	raids: bool
) -> Dictionary:
	var owner: int = config.faction
	if hostile.is_empty():
		return AiNavalStation.home_order(model, fleet, owner, charts)
	if trade_garrison(model, fleets, fleet) \
			and not _defends_seat(model, fleets, fleet, hostile):
		# The holds come home first: a court with none in port at its seat
		# buys no build input and ships no colonist, whatever the war wants
		# (wiki: ships-and-naval § Cargo holds and capacity; issue #530).
		var home: Dictionary = AiNavalStation.home_order(model, fleet, owner, charts, true)
		if not home.is_empty():
			home["reason"] = REASON_TRADE
		return home
	var fight: Dictionary = _best_target(config, model, fleets, fleet, hostile, charts)
	if not fight.is_empty():
		return fight
	if not raids or not AiSquadronReads.has_warship(fleet):
		# An overstretched court opens no new station at all, and the trace
		# names the raid it withheld (DR-20261117-01).
		return _home_from_war(model, fleet, owner, charts, not raids)
	var raid: Dictionary = AiNavalStation.raid_order(
		model, fleets, fleet, owner, hostile, charts
	)
	# Already on a hostile coast: the station pass works it, and it must not
	# sail home.
	if bool(raid.get("hold", false)):
		return {}
	if not raid.is_empty():
		return raid
	# Nowhere to fight and no trade to work: bring the hulls home, where holds
	# and escorts are worth something (DR-20261110-30).
	return _home_from_war(model, fleet, owner, charts, false)


## The homeward leg a war left a squadron with; an overstretched court names the
## raid its footing withheld instead of working it (DR-20261117-01).
static func _home_from_war(
	model: MapModel, fleet: FleetState, owner: int, charts: CourtCharts, fronts: bool
) -> Dictionary:
	var home: Dictionary = AiNavalStation.home_order(model, fleet, owner, charts)
	if not home.is_empty() and fronts:
		home["reason"] = REASON_FRONTS
	return home


## Holds the crown keeps in port at its seat, ignoring one squadron by id so a
## caller can ask what the court would still have ashore without it.
static func holds_ashore(
	model: MapModel, fleets: Array, owner: int, except_id: int = -1
) -> int:
	var port: int = NavalMovement.seat_harbour(model, owner)
	if port < 0:
		return 0
	var total: int = 0
	for fleet: FleetState in fleets:
		if fleet == null or fleet.owner != owner or fleet.id == except_id:
			continue
		if fleet.is_in_port() and fleet.province == port:
			total += TradeCargo.fleet_holds(fleet)
	return total


## True when this squadron carries the holds its court has nowhere else: without
## it at the seat the court imports nothing, so it sails home rather than hunt,
## raid or keep a station (wiki: ships-and-naval § Home Fleet, § Ship Types;
## issue #530). Expeditions answer false, and so does a crown with no harbour
## at its seat: no sail can help it.
static func trade_garrison(model: MapModel, fleets: Array, fleet: FleetState) -> bool:
	if fleet == null or TradeCargo.fleet_holds(fleet) <= 0:
		return false
	if fleet.has_beachhead() or not fleet.embarked_civilians.is_empty():
		return false
	if NavalMovement.seat_harbour(model, fleet.owner) < 0:
		return false
	return holds_ashore(model, fleets, fleet.owner, fleet.id) <= 0


## True when the squadron is the seat's own guard with a hostile squadron in the
## water beside it: defence outranks the trade, so the hold policy stands aside
## (wiki: ai-architecture § Naval policy — defence first; issue #530).
static func _defends_seat(
	model: MapModel, fleets: Array, fleet: FleetState, hostile: Dictionary
) -> bool:
	return fleet.is_in_port() and AiSquadronReads.hostile_beside(
		model, fleets, fleet, hostile
	)


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
	# The hull picks the leg (issue #1258): a warship hunts as published, while
	# a convoy hull joins no war hunt — it fights only for its own harbour, the
	# hostile beside its berth, and otherwise leaves the leg to the trade rules
	# (wiki: ai-architecture § Naval policy — defence first, ships-and-naval
	# § Ship Types).
	if not AiSquadronReads.has_warship(fleet) and not _defends_seat(
		model, fleets, fleet, hostile
	):
		return {}
	var kind: String = _fight_kind(fleet)
	var own: float = NavalCombat.side_strength([fleet])
	var best: Dictionary = {}
	var best_threat: float = 0.0
	for zone: int in AiSquadronReads.destinations(model, fleet):
		# A court hunts only in water its own chart holds; a hull it has never
		# charted is not a target (REQ-P2-03).
		if not AiSquadronReads.charts_water(charts, config.faction, model.region_id, zone):
			continue
		var threat: float = AiSquadronReads.hostile_strength(fleets, zone, hostile)
		if threat <= 0.0 or not _can_engage(config, own, threat):
			continue
		# Compare the true side strength: rounding first would let a stronger
		# squadron win only because its zone id sorts lower (wiki: ai-architecture
		# § Naval policy — "weakest hostile squadron it can reach").
		if best.is_empty() or _ahead(zone, threat, best, best_threat):
			best = {"zone": zone, "kind": kind, "threat": int(ceil(threat))}
			best_threat = threat
	return best


## The trace's name for this hull's fight: a port warship sorties, a port convoy
## answers its own berth, a sea squadron pursues (issue #1258).
static func _fight_kind(fleet: FleetState) -> String:
	if fleet.is_in_port():
		return KIND_SORTIE if AiSquadronReads.has_warship(fleet) else KIND_CONVOY
	return KIND_PURSUE


## True when this zone's squadron is the weaker one, or its equal on the lower
## zone id.
static func _ahead(zone: int, threat: float, best: Dictionary, best_threat: float) -> bool:
	if not is_equal_approx(threat, best_threat):
		return threat < best_threat
	return zone < int(best["zone"])


## The caution knob keeps a rival from feeding a squadron to a far stronger
## fleet; it never changes what the combat rules then decide.
static func _can_engage(config: AiConfig, own: float, threat: float) -> bool:
	var margin: float = float(config.parameter("naval.caution_margin_pct"))
	return threat * 100.0 <= own * margin


## Kept for callers that read a squadron's charted water through the planner.
static func charts_water(
	charts: CourtCharts, faction: int, region: int, zone: int
) -> bool:
	return AiSquadronReads.charts_water(charts, faction, region, zone)
