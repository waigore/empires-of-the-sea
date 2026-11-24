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


## Regiments the court aims at: the guard, or the host the thinnest wall ahead
## prices when that host is larger (issues #1314, #1381). Every gate that reads
## the target — the muster, its labour floor, the chest it holds — asks for the
## same host. A court that plans conquest arms before it declares: the wall's
## host is a peace reading too, because the men a storm needs cannot be raised
## in the turn the war opens (#1381 measured a court at its guard target never
## crossing a wall it could see). Pure policy: config in, count out
## (REQ-P2-03).
static func target(config: AiConfig, at_war: bool) -> int:
	var guard: int = guard_regiments(config, at_war)
	var read: Variant = _storm_read(config)
	if read == null or not (read is Dictionary):
		return guard
	# The wall's own host, never the guard plus a net extra: a court already
	# past its guard must still arm on to the host the wall prices, so the
	# target is the larger of the two sizes — not the extra re-net of a host
	# it has partly raised (which would stop it short of the wall).
	return maxi(guard, int((read as Dictionary).get("want", 0)))


## The wall reading the map layer notes on the court's shared config
## ([method MapPlayArmyMusterAi.storm_extra]): the host the thinnest wall ahead
## prices, at peace as at war. A court with no world passes none, and the
## published target stands. At war the reading has always raised the muster
## target; since #1381 it does so at peace too, because a court that banks for
## a storm it never arms for reaches the war with a chest and no host — the
## measured deadlock the issue names. The wall itself never moves: the reading
## only sizes what the court raises and what its money goal holds.
static func _storm_read(config: AiConfig) -> Variant:
	if config == null:
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
