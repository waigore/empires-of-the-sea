class_name ArmyStorm
extends RefCounted
## Empty-walled province storms (issue #1314; wiki: siege-mechanics § Storming
## an empty walled province; combat § Multi-Attacker Chain). Split from
## [ArmyCombat] so the turn chain keeps orchestration only (REQ-P3-01). A wall
## blocks the walk-in: fort level ≥ 1 is never an unopposed flip when no
## regiment stands — the march resolves as a storm against the wall and its
## emplaced battery.


## Every attacker that fell on an empty walled province storms it, in the
## chain's own order (wiki: combat § Multi-Attacker Chain — "resolve
## sequentially … repeat until no attacker remains"). A repelled storm leaves
## the wall and its battery standing for the next attacker, so a thin host that
## marched first never voids another court's march. The first host that crosses
## takes the ground; any attacker still on the field then meets it as the
## province's holder, from the walls it just took.
static func resolve_walled(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attackers: Array[int],
	context: Dictionary
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	var holder: int = defender
	var pending: Array[int] = attackers.duplicate()
	while not pending.is_empty():
		if ArmyForce.side_regiments(ArmyForce.armies_of(armies, province, holder)) > 0:
			reports.append_array(
				ArmyCombat.resolve_chain(model, armies, province, holder, pending, context)
			)
			return reports
		var attacker: int = pending.pop_front()
		var storming: Array[ArmyState] = ArmyForce.armies_of(armies, province, attacker)
		if ArmyForce.side_regiments(storming) == 0:
			continue
		var report: Dictionary = storm_one(
			model, armies, province, holder, attacker, storming, context
		)
		reports.append(report)
		if bool(report.get("captured", false)):
			holder = attacker
	return reports


## One hostile court takes an **empty walled** province (issue #1314): the wall
## and the battery stand where no regiment does. The march is a storm, not an
## unopposed flip — only a host whose strength crosses
## [method FortRules.storm_threshold] (wall HP plus the standing battery)
## takes the ground.
##
## Losses follow the published ladder (wiki: siege-mechanics § Wall Protection,
## deterministic by design — no new roll): each whole
## [constant FortRules.STORM_STEP] of strength past the threshold costs one
## regiment, weakest first — the same weakest-first draw every battle reads. The
## battery itself is never captured: a taken province keeps whatever walls and
## guns survive, and the storm that takes it does not silence the battery (a
## standing wall is taken, not shot to pieces).
static func storm_one(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	holder: int,
	attacker: int,
	storming: Array[ArmyState],
	context: Dictionary
) -> Dictionary:
	## The storm is a **battle context**, so the attacker pays the land's price for
	## it like any other: a Great Power's attack costs `ArmyAttackCost`'s base
	## whatever it meets, and a march that only walks into an empty open province
	## pays nothing because no battle is fought at all (wiki: tech-tree-military
	## § Economy modifiers — `kLandBattleAttackTreasuryCostBase`, "per Great Power
	## attacker per battle context"; combat § Resolution). The same charge the
	## exchange takes is taken here, before the wall is read, so a repelled storm
	## costs its attacker exactly what a repelled field fight does.
	var fee: Dictionary = ArmyAttackCost.charge(context, attacker)
	## The battery is the province's, so its line is the **holder's** (that is,
	## the province owner's) studies (wiki: siege-mechanics § Emplaced
	## Artillery — "the defender's unlocked emplaced-quality tech line"). The
	## storming court's own guns never price the wall it is not manning.
	var tech: Dictionary = (context.get("tech", {}) as Dictionary).get(
		holder, {}
	) as Dictionary
	var level: int = FortRules.level_at(model, province)
	var host_strength: float = 0.0
	for army: ArmyState in storming:
		host_strength += army.strength()
	var threshold: float = FortRules.storm_threshold(tech, level)
	## The men the ladder draws from, read before the dead are spent: a storm
	## deals no line and keeps no reserve — every regiment marches on the wall —
	## so the wear below is one share of the whole host
	## (wiki: combat § Wounds in auto-resolve).
	var host_count: int = ArmyForce.side_regiments(storming)
	var lost: Array[String] = []
	var taken: bool = host_strength > threshold
	var atk_up: int = 0
	if taken:
		## The ladder's price is drawn **weakest first**, the casualty rule every
		## battle reads (wiki: siege-mechanics § Storming an empty walled province
		## — "the same weakest-first casualty draw every battle reads"; combat
		## § Casualties). The draw is [method ArmyForce.apply_losses]' own, so a
		## storm can never spend its veterans where the field spends its levies.
		lost = ArmyForce.apply_losses(
			armies, storming, FortRules.storm_losses(host_strength, tech, level)
		)
		## A storm is a battle, so the men who crossed it come home with what a
		## won field leaves: a chevron each and the ground on their colours
		## (wiki: siege-mechanics § Storming an empty walled province — "A storm
		## is a **battle**"; combat § Chevrons won, § Battle honours). Only the
		## survivors rise, exactly as after an exchange.
		atk_up = RegimentCondition.award_side(storming)
	## The ladder's dead are dead, so the side that lost them carries the field's
	## wear into the chain's next engagement — the host that took the wall meets
	## the next attacker worn, never fresh
	## (wiki: combat § Wounds in auto-resolve; § Multi-Attacker Chain — "the
	## wounds and the chevrons the exchange left it").
	RegimentCondition.wear(
		storming,
		RegimentCondition.WOUND_SHARE * float(lost.size()) / float(maxi(host_count, 1))
	)
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, province, attacker, holder, ArmyCombat.Outcome.CAPTURE,
		lost, [] as Array[String], {}, {"fort": level}
	)
	ArmyAttackCost.stamp(fee, report)
	report["captured"] = taken
	report["storm"] = {
		"fort": level,
		"strength": host_strength,
		"threshold": threshold,
		"taken": taken,
	}
	## The aftermath every land battle record carries — each survivor's condition,
	## the chevrons it won and the ground on its colours — so the land despatch
	## names what the storm cost and bought instead of going silent once the wall
	## is named (wiki: combat § Chevrons won, § Battle honours; REQ-P2-03,
	## REQ-P5-05). `taken` is the win the record's CAPTURE outcome cannot name.
	var none: Array[ArmyState] = []
	RegimentCondition.attach(report, storming, none, atk_up, 0, taken)
	if not taken:
		## The wall stands: no flip, no capture — the report names the repulse.
		report["outcome"] = ArmyCombat.Outcome.DEFENDER_VICTORY
		return report
	BattleSettlement.flip(model, province, attacker)
	return report
