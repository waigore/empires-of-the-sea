class_name AiNavalFight
extends RefCounted
## Which fight a squadron takes this turn: the weakest reachable hostile squadron
## it can match, or none — the court declines. Ports sortie, sea squadrons
## pursue; both enter exactly one adjacent zone (NavalMovement owns legality)
## (wiki: ai-architecture § Naval policy — "weakest hostile squadron it can
## reach"). [AiNavalPlanner] decides whether to hunt; this module reads the water
## and prices the fight through [AiSquadronReads] (REQ-P3-01). Pure rules: state
## in, one order out; the map layer applies it (REQ-P2-03, REQ-P3-03).

## A port warship leaves the harbour to fight beside it.
const KIND_SORTIE: String = "sortie"
## A sea-going squadron closes on a hostile in water it can enter.
const KIND_PURSUE: String = "pursue"
## A merchant hull that leaves port sails a convoy, not a war sortie (wiki:
## ships-and-naval § Ship Types; issue #1258): the trace must name the move so a
## port fleet reads as what its hulls are.
const KIND_CONVOY: String = "convoy"


## Weakest reachable hostile squadron this turn, or empty when every reachable
## one is a fight the court declines. `defends_seat` is the caller's read of the
## berth guard: it lets a port convoy answer the hostile beside its harbour,
## which is the only fight a merchant hull joins (issue #1258).
static func best_target(
	config: AiConfig,
	model: MapModel,
	fleets: Array,
	fleet: FleetState,
	hostile: Dictionary,
	charts: CourtCharts,
	defends_seat: bool
) -> Dictionary:
	# The hull picks the leg (issue #1258): a warship hunts as published, while
	# a convoy hull joins no war hunt — it fights only for its own harbour, the
	# hostile beside its berth, and otherwise leaves the leg to the trade rules
	# (wiki: ai-architecture § Naval policy — defence first, ships-and-naval
	# § Ship Types).
	if not AiSquadronReads.has_warship(fleet) and not defends_seat:
		return {}
	var kind: String = kind_for(fleet)
	var own: float = NavalCombat.side_strength([fleet])
	var best: Dictionary = {}
	var best_threat: float = 0.0
	for zone: int in AiSquadronReads.destinations(model, fleet):
		# A court hunts only in water its own chart holds; a hull it has never
		# charted is not a target (REQ-P2-03).
		if not AiSquadronReads.charts_water(charts, config.faction, model.region_id, zone):
			continue
		var threat: float = AiSquadronReads.hostile_strength(fleets, zone, hostile)
		if threat <= 0.0 or not can_engage(config, own, threat):
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
static func kind_for(fleet: FleetState) -> String:
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
static func can_engage(config: AiConfig, own: float, threat: float) -> bool:
	var margin: float = float(config.parameter("naval.caution_margin_pct"))
	return threat * 100.0 <= own * margin
