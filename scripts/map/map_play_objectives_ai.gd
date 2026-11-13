class_name MapPlayObjectivesAi
extends RefCounted
## Rival objective ledger pass (T1, trace-only).
##
## Runs once per resolved turn, after the rival planners have staged their
## orders and before `AiTurnLog.record` merges the trace. For each planning
## court it collects the objectives those planners already scored, ranks them
## in the shared 0–100 currency, allocates the court's pools, and stamps the
## result into the turn record. It spends nothing and moves nothing, so the
## same seed yields the same orders with or without the ledger (REQ-P2-03,
## REQ-P4-03).
##
## The pass reads the turn's own reports rather than re-running a planner: a
## second scoring pass would both double the per-turn cost and score a state
## the real pass never saw.

const NO_ID: int = MapModel.NO_ID


static func run(
	play: PlaySession,
	economy_report: Dictionary,
	army_trace: Array[Dictionary] = [],
	fleet_trace: Array[Dictionary] = [],
	invasion_trace: Array[Dictionary] = []
) -> Dictionary:
	var report: Dictionary = {"factions": {}}
	if play == null or play.world == null or play.diplomacy == null:
		return report
	play.ensure_ai()
	var by_faction: Dictionary = report["factions"]
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction and not play.observer_mode:
			continue
		if not AiControl.plans(play, faction):
			continue
		var economy: PlayerEconomy = play.ledger_for(faction)
		if economy == null:
			continue
		var config: AiConfig = AiConfig.build(faction, play.map_seed)
		var phase: Dictionary = AiPhasePlanner.plan(config, play.diplomacy)
		var context: Dictionary = {
			"owner": faction,
			"config": config,
			"economy": economy,
			"phase": String(phase.get("phase", AiPhasePlanner.PHASE_PEACE)),
			"agenda": play.ai.agenda_for(config),
			"report": _faction_report(economy_report, faction),
			"ai_trace": play.ai_trace,
			"army_trace": army_trace,
			"fleet_trace": fleet_trace,
			"invasion_trace": invasion_trace,
			"world": play.world,
			"units": _units(play),
			"turn": play.turn,
		}
		var ranked: Array[AiObjective] = AiObjectiveLedger.rank(
			AiObjectives.collect(context)
		)
		var allocated: Array[AiObjective] = AiObjectiveLedger.allocate(
			ranked, _pools(play, faction, economy)
		)
		play.ai.claims[faction] = AiObjectiveLedger.claims_of(allocated)
		by_faction[faction] = {
			"phase": context["phase"],
			"objectives": _serialize(allocated),
			"lines": AiObjectiveLedger.trace_lines(allocated),
		}
	return report


## The court's resource pools for the allocate pass: its purse, the hulls,
## civilians and regiments it already holds, its labour, and one order of
## attention for the turn.
static func _pools(
	play: PlaySession, faction: int, economy: PlayerEconomy
) -> Dictionary:
	return {
		"treasury": economy.treasury,
		"hull": play.ship_layer.hull_count_all(faction) if play.ship_layer != null else 0,
		"civilian": (
			play.civilian_layer.unit_count_all(faction)
			if play.civilian_layer != null else 0
		),
		"regiment": (
			play.army_layer.regiment_count_all(faction)
			if play.army_layer != null else 0
		),
		"labour": economy.workers.labour(),
		"orders": 1,
	}


static func _faction_report(report: Dictionary, faction: int) -> Dictionary:
	var per: Dictionary = report.get("factions", {})
	var row: Variant = per.get(faction, {})
	return row if typeof(row) == TYPE_DICTIONARY else {}


## Every civilian on the map, so the spy emitter can see a court's station.
static func _units(play: PlaySession) -> Array:
	var units: Array = []
	if play.civilian_layer == null:
		return units
	for raw: Variant in play.civilian_layer.regions.values():
		if typeof(raw) == TYPE_ARRAY:
			units.append_array(raw)
	return units


static func _serialize(objectives: Array[AiObjective]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for objective: AiObjective in objectives:
		rows.append(objective.to_dict())
	return rows
