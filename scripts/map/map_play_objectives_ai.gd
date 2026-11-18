class_name MapPlayObjectivesAi
extends RefCounted
## Runs the objective ledger for every planning rival court and stamps it into
## the turn trace (docs/ai.md; issue #491 T1).
##
## This file owns the pass: which courts plan, when the ledger runs, what it is
## granted and what the trace keeps. What the ledger *reads* — the force, the
## purse, the yard, the college, the Tribe and the expedition — is
## [MapPlayObjectiveReadings]' one reading per domain (REQ-P3-01).
##
## Reads state only: T1 issues no order, so the same seed plays the same
## campaign and the ledger is a reading of the court, not a second planner
## (REQ-P2-03, REQ-P4-03). The pass runs before the expedition pass, because the
## voyage objectives are read from the hulls and the Explorer as they stand at
## the start of the turn (issue #491 T2).
##
## One ledger per court is kept in `play.objective_ledgers` for the turn log and
## the observer panel, and the claims are persisted on `AiState` so a save
## carries them (issue #491 T1 acceptance).


## Every planning court's ledger for this turn. Empty when the session has no
## world or diplomacy to read.
static func run(play: PlaySession) -> Dictionary:
	var ledgers: Dictionary = {}
	if play == null or play.world == null or play.diplomacy == null:
		return ledgers
	play.ensure_ai()
	for faction: int in FactionCatalog.great_power_ids():
		if not AiControl.plans(play, faction):
			continue
		ledgers[faction] = court(play, faction)
	return ledgers


## One court's ranked, allocated ledger plus the readings that made it.
static func court(play: PlaySession, faction: int) -> Dictionary:
	var economy: PlayerEconomy = play.ai.economy_for(faction)
	var config: AiConfig = AiConfig.build(faction, play.map_seed)
	var phase: Dictionary = AiPhasePlanner.plan(config, play.diplomacy)
	# The footing, the leader's weights and the court's distance to the bar
	# scale the rank without deleting an aim: a voyage at war is cheaper, not
	# gone (issue #491 T4; DR-20261114-04).
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	var readings: Dictionary = MapPlayObjectiveReadings.readings(
		play, faction, config, economy, phase, pressure
	)
	var report: Dictionary = AiObjectiveLedger.run(
		AiObjectivesPlan.build(readings),
		pools(economy, readings),
		AiPosture.modifiers(
			String(phase.get("phase", "")), config, int(pressure["boost_mille"]),
			String(readings["goal"])
		)
	)
	report["phase"] = String(phase.get("phase", AiPhasePlanner.PHASE_UNKNOWN))
	report["goal"] = String(readings["goal"])
	report["treasury"] = int(readings["treasury"])
	report["reserve"] = int(readings["reserve"])
	# The deferred-aim escalations this reading applied (issue #603): the aims
	# stalled past the escalation bar, with their stall length.
	report["escalations"] = (readings["escalations"] as Dictionary).duplicate()
	report["pressure"] = pressure
	play.ai.note_objectives(faction, report, play.turn)
	return report


## The pools the allocate pass draws on. A pool is a per-turn grant: one order,
## one train slot, one muster slot, and the purse as it stands. The hull's
## material row is bounded by the store, so a fleet claim short of cloth reads
## `deferred fabric 0/1` instead of funded against an unlimited pool (issue #484).
static func pools(economy: PlayerEconomy, readings: Dictionary) -> Dictionary:
	var pools: Dictionary = {
		"treasury": maxi(economy.treasury, 0),
		"hull": int(readings["idle_hulls"]),
		"civilian": 1,
		"regiment": 1,
		"labour": economy.available_peasants(),
		"orders": 1,
	}
	for commodity: Variant in (readings.get("warship_row", {}) as Dictionary).keys():
		pools[String(commodity)] = maxi(economy.quantity(String(commodity)), 0)
	# The muster's own material row, bounded by the store: a line short of its
	# cloth reads `deferred fabric 0/1`, the row the planner actually refuses on
	# (#474), instead of a funded purse the muster never spends.
	for commodity: Variant in (readings.get("muster_row", {}) as Dictionary).keys():
		var id: String = String(commodity)
		pools[id] = maxi(economy.quantity(id), 0)
	return pools
