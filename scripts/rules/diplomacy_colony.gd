class_name DiplomacyColony
extends RefCounted
## A Tribe bought into the empire (wiki: diplomacy § GP–Tribe Rules — Join
## Empire). Split from DiplomacyRules so the chain's last link keeps its own
## file under the size bar (REQ-P3-01).
##
## A colony is not an absorption: the Tribe keeps its provinces, its units and
## its court, and only the Join Empire cost is paid. The overture record is
## walked to Join Empire in both directions, so the court reads the chain as
## finished instead of offering the same purchase again next turn.


## Records the colony and reports the beat the court hears.
static func found(
	state: DiplomacyState, player: int, target: int, stage: String, cost: int
) -> Dictionary:
	state.set_colony(target, player)
	state.set_overture(player, target, stage)
	state.set_overture(target, player, stage)
	state.touch(player, target, "colonyFormed", {"stage": stage})
	return {
		"ok": true,
		"accepted": true,
		"cost": cost,
		"message": "%s becomes a colony of %s." % [
			FactionCatalog.name_of(target), FactionCatalog.name_of(player)
		],
	}
