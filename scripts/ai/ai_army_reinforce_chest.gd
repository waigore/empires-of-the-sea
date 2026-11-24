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


## Ducats the muster holds back for the next man of the storm host (issue
## #1381): one man, priced on the line the host is sized with ([method
## AiArmyReinforceLine.storm_price]), never the whole host. A chest sized
## to the whole host froze the measured run: three crowns filled 24,200 ducats
## against a wall that asked twelve men and raised not one in 200 turns, because
## each regiment had to leave the whole chest untouched behind it and no court
## can hold a host's price and pay its government at once. The wall's host is
## the muster **target** (that is what raises the men); the purse only keeps the
## next man's own price, so the host is paid as it is raised and the muster is
## never one payment short. `storm_bank` is the host still missing (the map
## layer's own read). Zero when no host is due or no line is open.
static func storm_line_hold(
	config: AiConfig, economy: PlayerEconomy, storm_bank: int
) -> int:
	if config == null or economy == null or maxi(storm_bank, 0) <= 0:
		return 0
	return AiArmyReinforceLine.storm_price(config, economy)


## Treasury a court must hold before any muster is legal: `army.min_treasury`
## still in the purse after paying for the line it would raise — the cheapest
## line pattern its techs open, or the next man of the storm host when the wall
## stands above it (issue #1381). Other planners read it as the war chest they
## must not spend, so a court saving for its next regiment never funds itself
## into the deadlock where every muster is one ducat short (wiki:
## ai-architecture § Land reinforcement; growth-stage-planner § Recruitment
## modulation). `storm_bank` is the host still missing, read by the caller
## (`AiIncome.storm_want` at war, `MapPlayArmyMusterAi.storm_chest` at peace):
## the court arms toward that host one man at a time — the host is the target,
## the purse is its next man. 0 when it already stands at its target, can raise
## nothing, or has no peasant to spare.
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
	# The storm host prices the next man on the line it is raised with, so a
	# court mustering toward a wall never pays the cheapest pattern while its
	# host is sized on a dearer one. No host due keeps the published line.
	return floor_treasury + maxi(cheapest, storm_line_hold(config, economy, storm_bank))


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
