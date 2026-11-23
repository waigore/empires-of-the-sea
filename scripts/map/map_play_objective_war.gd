class_name MapPlayObjectiveWar
extends RefCounted
## The war-desire reading the objective ledger prices (docs/ai.md;
## DR-20261115-04): the same score the diplomacy planner weighs, against the
## court's enemy or the weakest Great Power. `MapPlayObjectiveReadings` owns the
## ledger; this owner answers every war question, so the ledger's war aim and
## the planner's declaration price the same war (REQ-P2-03, REQ-P3-01,
## REQ-P3-03).


## War desire against the court's enemy, else against the weakest Great Power —
## the same score the diplomacy planner weighs, read once per turn for the trace.
## The victory press rides the same reading.
static func desire(
	play: PlaySession, config: AiConfig, faction: int, pressure: Dictionary = {}
) -> int:
	var target: int = _war_target(play, faction)
	if target < 0:
		target = _weakest_rival(play, faction)
	if target < 0 or play.diplomacy.relation(faction, target) == null:
		return 0
	var powers: Dictionary = {
		faction: _power(play, faction), target: _power(play, target),
	}
	var context: Dictionary = {
		"power": powers,
		"victory_press": int(pressure.get("war_press", 0)),
		"regiments": {
			faction: MapPlayCourtHoldings.regiments(play, faction),
			target: MapPlayCourtHoldings.regiments(play, target),
		},
		"ships": {
			faction: MapPlayCourtHoldings.ships(play, faction),
			target: MapPlayCourtHoldings.ships(play, target),
		},
	}
	return int(
		AiDiplomacyDesire.war_desire(
			config, play.diplomacy, play.world, faction, target, context
		).get("score", 0)
	)


## The first Great Power this court is at war with, or -1.
static func _war_target(play: PlaySession, faction: int) -> int:
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record == null or not record.at_war:
			continue
		var other: int = record.other(faction)
		if FactionCatalog.type_of(other) == FactionCatalog.Type.GREAT_POWER:
			return other
	return -1


## Weakest rival by the published power score; the id breaks a tie, so the same
## chart always reads the same target.
static func _weakest_rival(play: PlaySession, faction: int) -> int:
	var best: int = -1
	var best_score: int = 0
	for rival: int in FactionCatalog.great_power_ids():
		if rival == faction:
			continue
		var score: int = _power(play, rival)
		if best < 0 or score < best_score:
			best = rival
			best_score = score
	return best


static func _power(play: PlaySession, faction: int) -> int:
	return AiPower.score(
		play.world, faction, MapPlayCourtHoldings.regiments(play, faction),
		MapPlayCourtHoldings.ships(play, faction)
	)
