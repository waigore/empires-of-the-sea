class_name AiArmyReinforceHost
extends RefCounted
## How many land regiments a rival court aims at (wiki: ai-architecture § Land
## reinforcement; issue #1314, #1381).
##
## Owns the published guard, the storm-wall extra, and the host the thinnest
## wall prices for the money goal. `AiArmyReinforce` owns the turn plan and the
## food gates; `AiArmyReinforceChest` owns the purse; this owner answers every
## host-size question so the muster, labour floor and war chest never drift
## from one target (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## Regiments the court aims at: the guard plus the host the thinnest wall ahead
## asks for (issue #1314). Every gate that reads the target — the muster, its
## labour floor, the chest it holds — asks for the same host. Pure policy:
## config in, count out (REQ-P2-03).
static func guard_regiments(config: AiConfig, at_war: bool) -> int:
	if config == null:
		return 0
	var target: int = config.parameter("army.regiment_target")
	if at_war:
		target += config.parameter("army.war_extra")
	return target


## Regiments the court aims at: the guard plus the host the thinnest wall ahead
## asks for (issue #1314). Every gate that reads the target — the muster, its
## labour floor, the chest it holds — asks for the same host.
static func target(config: AiConfig, at_war: bool) -> int:
	return guard_regiments(config, at_war) + AiStormGate.extra_regiments(
		_storm_read(config, at_war)
	)


## The wall reading the map layer hands in ([method
## MapPlayArmyMusterAi.storm_extra]); a court with no world passes none, and the
## published target stands. At war the reading raises the muster target — the
## wall is a war reading. At peace the reading prices only money: the conquest
## bank sizes the storm chest from it (`AiIncome.storm_bank`), so a court that
## plans conquest banks for the host its thinnest wall prices before it
## declares (issue #1381) — the purse cannot be the reason a war never starts,
## and the bank cannot freeze the economy a war is fought with (issue #1384,
## the retuned stand-down). The peace target stays published.
static func _storm_read(config: AiConfig, at_war: bool) -> Variant:
	if config == null or not at_war:
		return null
	return config.storm_read


## The army the court desires at its published target — the size it plans food
## income for while it stands under it (issue #807). The same table
## [method target] prices the muster with.
static func desired_regiments(config: AiConfig, at_war: bool) -> int:
	if config == null:
		return 0
	return target(config, at_war)


## Regiments the thinnest wall ahead prices at war, read off the court's own
## target: the `want` the storm reading stamped less the host the court already
## fields, floored at zero — what stands between the guard and the wall
## (`MapPlayArmyMusterAi.storm_extra` notes the reading on the shared config).
## Zero with no reading — open ground, no wall in front of the court. At war
## the money goal reads this off the shared read (`AiIncome.storm_want`); at
## peace the map layer hands the host in (`MapPlayArmyMusterAi.storm_chest`).
static func storm_want_read(config: AiConfig, own_regiments: int) -> int:
	if config == null:
		return 0
	var want: int = int(config.storm_read.get("want", 0.0))
	return maxi(want - maxi(own_regiments, 0), 0) if want > 0 else 0
