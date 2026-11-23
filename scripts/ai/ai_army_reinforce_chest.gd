class_name AiArmyReinforceChest
extends RefCounted
## The war chest and material row a rival court holds for its next land muster
## (wiki: ai-architecture § Land reinforcement; growth-stage-planner §
## Recruitment modulation; issues #474, #807, #1381).
##
## Owns the purse floor, the fabric reservation, the peasant hands the levy
## keeps, and the absent-row reason a silent muster prints. `AiArmyReinforce`
## owns the turn plan; `AiArmyReinforceHost` owns the host size; this owner
## answers every purse question so the money goal and the drill yard never
## drift from one chest (REQ-P2-03, REQ-P3-01, REQ-P3-03).


## Peasants a court keeps in the fields so its muster stays legal: the
## `army.min_peasants` floor the muster itself reads plus the levy's own hand
## (`RegimentEconomy.WORKER_COST`). The reservation is answered only while the
## court stands under its target, is at war, holds the material row of the
## pattern it is saving for, and its purse already holds the muster's war chest
## — behind the slot un-latch and the chest escalation, never ahead of them
## (issue #807, evidence/issue-474 Round 9: measured −3.65 % on the destitute
## tree where it never fired). 0 otherwise, so a court that is not arming
## trains freely.
static func muster_hands(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool
) -> int:
	if config == null or economy == null or not at_war:
		return 0
	if own_regiments >= AiArmyReinforceHost.target(config, at_war):
		return 0
	var type_id: String = AiArmyReinforceLine.saving_type(config, economy)
	if type_id.is_empty():
		return 0
	if not RegimentEconomy.missing_inputs(type_id, economy.stockpile).is_empty():
		return 0
	if economy.treasury < muster_floor(config, economy, own_regiments, at_war):
		return 0
	return config.parameter("army.min_peasants") + RegimentEconomy.WORKER_COST


## Commodities this court keeps back so the regiment it means to raise can be
## mustered: the whole input row of the pattern it is saving for (wiki:
## growth-stage-planner § Recruitment modulation, "military fabric reservation
## holds inputs for upcoming recruits"; economy-planner § Reservations). The row
## is held even while the purse is still short of the muster — a court that only
## provisioned once it could pay would never stock the cloth it needs, and the
## muster would starve with a full war chest (issue #474). `storm_bank` is the
## storm host the money goal banks for (issue #1381): it keeps the row too, and
## zero when the court sits at its target or its fields cannot spare a hand.
static func muster_reserve(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool,
	pressure_extra: int = 0,
	storm_bank: int = 0
) -> Dictionary:
	if config == null or economy == null:
		return {}
	var target: int = AiArmyReinforceHost.target(config, at_war) + maxi(pressure_extra, 0)
	# A court banking for the storm host provisions the line even past its
	# published target; a court already fielding that host arms as published.
	if own_regiments >= target and (
		storm_bank <= 0
		or own_regiments >= target + AiArmyReinforceHost.storm_want_read(
			config, own_regiments
		)
	):
		return {}
	var type_id: String = AiArmyReinforceLine.saving_type(config, economy)
	if type_id.is_empty():
		return {}
	return RegimentEconomy.training_inputs(type_id)


## Treasury a court must hold before any muster is legal: `army.min_treasury`
## still in the purse after paying for the line it would raise — the cheapest
## line pattern its techs open, or the storm host its thinnest wall prices when
## the wall stands above it (issue #1381). Other planners read it as the war
## chest they must not spend, so a court saving for its next regiment never
## funds itself into the deadlock where every muster is one ducat short (wiki:
## ai-architecture § Land reinforcement; growth-stage-planner § Recruitment
## modulation). `storm_bank` is that host in regiments, read by the caller
## (`AiIncome.storm_want` at war, `MapPlayArmyMusterAi.storm_chest` at peace):
## the storm-sized chest is banked while the court plans the conquest — at
## peace as at war — and a court already fielding that host keeps the cheaper
## published chest. 0 when it already stands at its target, can raise nothing,
## or has no peasant to spare.
static func muster_floor(
	config: AiConfig,
	economy: PlayerEconomy,
	own_regiments: int,
	at_war: bool,
	storm_bank: int = 0
) -> int:
	if config == null or economy == null:
		return 0
	if own_regiments >= AiArmyReinforceHost.target(config, at_war):
		return 0
	if not AiArmyReinforceLine.labour_floor_ok(config, economy):
		return 0
	var floor_treasury: int = maxi(config.parameter("army.min_treasury"), 0)
	var cheapest: int = AiArmyReinforceLine.cheapest_line(economy)
	if cheapest < 0:
		return floor_treasury
	# The storm chest is one host the wall prices, handed in by the money
	# goal: at war the caller read it off the shared config (`AiIncome.
	# storm_want`), at peace the map layer read it from the map (`storm_bank`
	# on `AiIncome.plan`). A chest of zero — open ground, no wall in front of
	# the court, or a host already at the wall's size — keeps the published
	# cheapest-line floor. The host is regiments: the chest prices them at
	# the cheapest line the court's own purse saves for, so the goal and the
	# muster read one purse (`MapPlayArmyMusterAi.storm_chest` reads the
	# same rule).
	var storm_want: int = maxi(storm_bank, 0)
	return floor_treasury + maxi(cheapest, storm_want * cheapest)


## Why a court standing under its target prices no muster row ("" when the row
## stands): the muster's own gates, in the trace's words, so a silent absence
## cannot hide the starvation again (issue #1143). The muster's own money and
## food gates live on `AiArmyReinforce.plan`; this names only the gates that
## price the row itself — the labour floor and a court whose techs open no
## line pattern.
static func absent_reason(
	config: AiConfig, economy: PlayerEconomy, own_regiments: int, at_war: bool
) -> String:
	if config == null or economy == null:
		return ""
	if own_regiments >= AiArmyReinforceHost.target(config, at_war):
		return ""
	if not AiArmyReinforceLine.labour_floor_ok(config, economy):
		return "the labour floor holds: no spare hand for the levy"
	if AiArmyReinforceLine.saving_type(config, economy).is_empty():
		return "no line pattern its techs open"
	return ""
