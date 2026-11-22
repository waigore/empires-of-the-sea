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
## The fight it picks is [AiNavalFight], the water a station order crosses is
## [AiNavalStation], and what a squadron is or where it can reach is
## [AiSquadronReads]: no read is written twice here (REQ-P3-01).
##
## The footing's naval slot (`navy.missions`, DR-20261117-01) is the caller's
## read: an **overstretched** court opens no new commerce station — a squadron
## with no fight to pick sails home instead of working a hostile coast — while a
## station already posted keeps its post and a court at one front raids as
## published.

const KIND_PURSUE: String = AiNavalFight.KIND_PURSUE
const KIND_SORTIE: String = AiNavalFight.KIND_SORTIE
## The station's own two sails; [AiNavalStation] owns their water and names them
## here so a caller keeps one vocabulary.
const KIND_HOME: String = AiNavalStation.KIND_HOME
const KIND_RAID: String = AiNavalStation.KIND_RAID
const KIND_CONVOY: String = AiNavalFight.KIND_CONVOY
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
	var defends_seat: bool = _defends_seat(model, fleets, fleet, hostile)
	if trade_garrison(model, fleets, fleet) and not defends_seat:
		# The holds come home first: a court with none in port at its seat
		# buys no build input and ships no colonist, whatever the war wants
		# (wiki: ships-and-naval § Cargo holds and capacity; issue #530).
		var home: Dictionary = AiNavalStation.home_order(model, fleet, owner, charts, true)
		if not home.is_empty():
			home["reason"] = REASON_TRADE
		return home
	var fight: Dictionary = AiNavalFight.best_target(
		config, model, fleets, fleet, hostile, charts, defends_seat
	)
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


## Kept for callers that read a squadron's charted water through the planner.
static func charts_water(
	charts: CourtCharts, faction: int, region: int, zone: int
) -> bool:
	return AiSquadronReads.charts_water(charts, faction, region, zone)
