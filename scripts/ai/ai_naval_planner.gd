class_name AiNavalPlanner
extends RefCounted
## Full-AI naval policy (docs/ai.md, wiki: ai-architecture § Naval policy).
## A court at war puts its sea-going squadrons onto the nearest hostile squadron
## it can match — a sortie out of an adjacent port, or a one-zone pursuit — and
## otherwise holds station, which is the wiki's Defend mission. Pure rules:
## state in, orders out; the map layer applies them through NavalMovement so the
## AI never invents an outcome (REQ-P2-03, REQ-P3-03).

const KIND_PURSUE: String = "pursue"
const KIND_SORTIE: String = "sortie"


## One order per sea-going squadron: the zone to enter and the strength it means
## to face. `candidates` mirrors `orders` for the turn trace. `charts` is the
## court's own fog — it never hunts into water it has not charted, and a null
## chart is the fixture reading (DR-20261110-21).
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
	if hostile.is_empty():
		return {"orders": planned, "candidates": candidates}
	for fleet: FleetState in _squadrons(fleets, config.faction):
		var best: Dictionary = _best_target(config, model, fleets, fleet, hostile, charts)
		if best.is_empty():
			continue
		var entry: Dictionary = {
			"fleet_id": fleet.id,
			"zone": int(best["zone"]),
			"kind": String(best["kind"]),
			"threat": int(best["threat"]),
		}
		candidates.append(entry)
		planned.append(entry.duplicate())
	return {"orders": planned, "candidates": candidates}


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
		if charts != null and not charts.knows_zone(fleet.owner, model.region_id, zone):
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
