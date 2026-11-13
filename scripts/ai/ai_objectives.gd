class_name AiObjectives
extends RefCounted
## Read-only objective emitters, one per planner (T1, trace-only).
##
## Each emitter reads the turn output that planner already produced — its
## scored candidates or its applied orders — and turns it into `AiObjective`
## rows. Nothing is recomputed and nothing is spent, so the ledger adds no
## per-turn cost beyond a walk over the trace (REQ-P4-03) and cannot change an
## order (REQ-P2-03). A planner whose output carries no score of its own is
## priced at its published bench weight (`AiUtility.DOMAIN_BASE`).

const DOMAIN_DIPLOMACY: String = "diplomacy"
const DOMAIN_MILITARY: String = "military"
const DOMAIN_NAVAL: String = "naval"
const DOMAIN_INVASION: String = "invasion"
const DOMAIN_COLONISATION: String = "colonisation"
const DOMAIN_ECONOMY: String = "economy"
const DOMAIN_RESEARCH: String = "research"
const DOMAIN_CARGO: String = "cargo"
const DOMAIN_MARKET: String = "market"
const DOMAIN_CIVILIAN: String = "civilian"
const DOMAIN_MUSTER: String = "muster"
const DOMAIN_SPY: String = "spy"


## Every objective this court's planners emitted this turn, already normalized
## into the shared currency and adjusted for posture and agenda.
static func collect(context: Dictionary) -> Array[AiObjective]:
	var objectives: Array[AiObjective] = []
	objectives.append_array(diplomacy(context))
	objectives.append_array(military(context))
	objectives.append_array(naval(context))
	objectives.append_array(invasion(context))
	objectives.append_array(colonisation(context))
	objectives.append_array(economy(context))
	objectives.append_array(research(context))
	objectives.append_array(cargo(context))
	objectives.append_array(market(context))
	objectives.append_array(civilian(context))
	objectives.append_array(muster(context))
	objectives.append_array(spy(context))
	return objectives


## One objective per scored diplomatic candidate: a war it wants, a peace it
## would take, or a court-menu offer. The planner's own `blocked` reason rides
## along, so the trace says why a live option is not taken.
static func diplomacy(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	var owner: int = int(context.get("owner", -1))
	for record: Dictionary in _array(context.get("ai_trace", [])):
		if int(record.get("faction", -1)) != owner:
			continue
		for candidate: Dictionary in _array(record.get("candidates", [])):
			var target: int = int(candidate.get("target", -1))
			var at_war: bool = bool(candidate.get("at_war", false))
			var kind: String = "peace" if at_war else "war"
			out.append(_objective(
				context, "diplomacy.%s.%d" % [kind, target], DOMAIN_DIPLOMACY,
				AiUtility.normalize(int(candidate.get("desire", 0)), 0, DOMAIN_DIPLOMACY),
				{"orders": 1}, String(candidate.get("blocked", ""))
			))
	return out


## One objective per applied land order: a march, a storm or the Home Army's
## split. The army trace carries no score, so the domain's bench weight prices
## it and the posture modifier decides its rank.
static func military(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	var owner: int = int(context.get("owner", -1))
	for entry: Dictionary in _array(context.get("army_trace", [])):
		if int(entry.get("faction", -1)) != owner:
			continue
		var kind: String = String(entry.get("kind", "march"))
		out.append(_objective(
			context, "military.%s.%d" % [kind, int(entry.get("army", -1))],
			DOMAIN_MILITARY, int(AiUtility.DOMAIN_BASE[DOMAIN_MILITARY]),
			{"orders": 1, "regiment": 1}
		))
	return out


## One objective per squadron order: a sortie, a pursuit, a raid or the sail
## home. A hull is the pool it claims.
static func naval(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	var owner: int = int(context.get("owner", -1))
	for entry: Dictionary in _array(context.get("fleet_trace", [])):
		if int(entry.get("faction", -1)) != owner:
			continue
		var kind: String = String(entry.get("kind", "home"))
		out.append(_objective(
			context, "naval.%s.%d" % [kind, int(entry.get("fleet", -1))],
			DOMAIN_NAVAL, int(AiUtility.DOMAIN_BASE[DOMAIN_NAVAL]),
			{"orders": 1, "hull": 1}
		))
	return out


## One objective per overseas expedition step: the crossing claims a hull, a
## regiment and the court's order attention.
static func invasion(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	var owner: int = int(context.get("owner", -1))
	for entry: Dictionary in _array(context.get("invasion_trace", [])):
		if int(entry.get("faction", -1)) != owner:
			continue
		var kind: String = String(entry.get("kind", "cross"))
		out.append(_objective(
			context, "invasion.%s" % kind, DOMAIN_INVASION,
			int(AiUtility.DOMAIN_BASE[DOMAIN_INVASION]),
			{"orders": 1, "hull": 1, "regiment": 1}
		))
	return out


## A court with no land in the other region still wants a voyage: the parent
## issue's bench prices colonisation at 50 per province, and the expedition
## claims a hull, a civilian and an order.
static func colonisation(context: Dictionary) -> Array[AiObjective]:
	var world: WorldMap = context.get("world", null)
	var owner: int = int(context.get("owner", -1))
	if world == null or owner < 0:
		return []
	var home: int = FactionCatalog.region_of(owner)
	if home < 0:
		return []
	var target: int = WorldMap.NEW_WORLD if home == WorldMap.OLD_WORLD else WorldMap.OLD_WORLD
	if _owns_land_in(world, target, owner):
		return []
	return [_objective(
		context, "colonisation.voyage", DOMAIN_COLONISATION,
		int(AiUtility.DOMAIN_BASE[DOMAIN_COLONISATION]),
		{"orders": 1, "hull": 1, "civilian": 1}
	)]


## One objective per scored production recipe; the runs it was assigned are the
## labour it claims.
static func economy(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	for candidate: Dictionary in _candidates(context, "production"):
		var runs: int = maxi(int(candidate.get("assigned", 0)), 1)
		out.append(_objective(
			context, "economy.production.%s" % String(candidate.get("recipe", "")),
			DOMAIN_ECONOMY,
			AiUtility.normalize(int(candidate.get("score", 0)), 0, DOMAIN_ECONOMY),
			{"labour": runs}
		))
	return out


## One objective per scored study; a study occupies the court's order attention
## for the turn it is funded.
static func research(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	for candidate: Dictionary in _candidates(context, "research"):
		out.append(_objective(
			context, "research.%s" % String(candidate.get("tech", "")),
			DOMAIN_RESEARCH,
			AiUtility.normalize(int(candidate.get("score", 0)), 0, DOMAIN_RESEARCH),
			{"orders": 1}
		))
	return out


## One objective per cargo route or new hull; the holds it brings home are its
## utility, and a hull is the pool it claims.
static func cargo(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	for candidate: Dictionary in _candidates(context, "cargo"):
		var kind: String = String(candidate.get("kind", "route"))
		var holds: int = int(candidate.get("holds", candidate.get("cargo", 0)))
		var cost: Dictionary = {"hull": 1}
		if kind == "launch":
			cost["treasury"] = 1
		out.append(_objective(
			context, "cargo.%s.%d" % [kind, int(candidate.get("fleet_id", -1))],
			DOMAIN_CARGO, AiUtility.normalize(holds, 0, DOMAIN_CARGO), cost
		))
	return out


## One objective per market offer or bid. A bid claims the purse it would spend;
## an offer claims only the court's order attention.
static func market(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	for candidate: Dictionary in _candidates(context, "trade"):
		var kind: String = String(candidate.get("kind", "bid"))
		var commodity: String = String(candidate.get("commodity", ""))
		var magnitude: int = int(candidate.get("deficit", candidate.get("surplus", 0)))
		var cost: Dictionary = {"orders": 1}
		if kind == "bid":
			cost["treasury"] = maxi(
				int(candidate.get("quantity", 0)) * int(candidate.get("unit_price", 0)), 1
			)
		out.append(_objective(
			context, "market.%s.%s" % [kind, commodity], DOMAIN_MARKET,
			AiUtility.normalize(magnitude, 0, DOMAIN_MARKET), cost
		))
	return out


## One objective per applied civilian work order; the order's own score is the
## utility and the crew's labour is the claim.
static func civilian(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	var report: Dictionary = context.get("report", {})
	var civilians: Dictionary = report.get("civilians", {})
	for order: Dictionary in _array(civilians.get("orders", [])):
		out.append(_objective(
			context, "civilian.%s.%d" % [
				String(order.get("action", "work")), int(order.get("unit_id", -1)),
			],
			DOMAIN_CIVILIAN,
			AiUtility.normalize(int(order.get("score", 0)), 0, DOMAIN_CIVILIAN),
			{"orders": 1, "labour": 1}
		))
	return out


## One objective per worker the court trained; the muster bench prices it and
## the purse plus a regiment slot are the claim.
static func muster(context: Dictionary) -> Array[AiObjective]:
	var out: Array[AiObjective] = []
	var report: Dictionary = context.get("report", {})
	var recruits: Array = _array(report.get("recruits", []))
	for index in recruits.size():
		out.append(_objective(
			context, "muster.worker.%d" % index, DOMAIN_MUSTER,
			int(AiUtility.DOMAIN_BASE[DOMAIN_MUSTER]),
			{"treasury": 1, "regiment": 1}
		))
	return out


## A court that keeps a Spy abroad wants the station held: the bench prices it
## and the order attention is the claim.
static func spy(context: Dictionary) -> Array[AiObjective]:
	var owner: int = int(context.get("owner", -1))
	for raw: Variant in _array(context.get("units", [])):
		var unit: CivilianState = raw
		if unit == null or unit.owner != owner or unit.type_id != "spy":
			continue
		return [_objective(
			context, "spy.station.%d" % unit.id, DOMAIN_SPY,
			int(AiUtility.DOMAIN_BASE[DOMAIN_SPY]), {"orders": 1}
		)]
	return []


# --- helpers -----------------------------------------------------------------


## Builds one objective with the court's posture and agenda already applied.
static func _objective(
	context: Dictionary,
	objective_id: String,
	domain: String,
	utility: int,
	cost: Dictionary,
	blocked: String = ""
) -> AiObjective:
	var adjusted: int = AiUtility.adjust(
		utility, domain,
		String(context.get("phase", AiUtility.POSTURE_PEACE)),
		String(context.get("agenda", ""))
	)
	return AiObjective.make(objective_id, domain, adjusted, cost, blocked)


## The scored candidates one planner left in this court's economy report.
static func _candidates(context: Dictionary, key: String) -> Array:
	var report: Dictionary = context.get("report", {})
	var section: Dictionary = report.get(key, {})
	return _array(section.get("candidates", []))


static func _owns_land_in(world: WorldMap, region: int, owner: int) -> bool:
	var model: MapModel = world.region(region)
	if model == null:
		return false
	for province: ProvinceState in model.provinces:
		if province.owner == owner:
			return true
	return false


static func _array(raw: Variant) -> Array:
	return raw if typeof(raw) == TYPE_ARRAY else []
