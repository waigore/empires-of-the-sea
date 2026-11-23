class_name ArmyExchange
extends RefCounted
## One attacker-versus-defender auto-resolve exchange (wiki: combat,
## military-armies; siege-mechanics). Split from [ArmyCombat] so the turn chain
## keeps orchestration only (REQ-P3-01). Quick Battle still owns the human
## path; both settle through [BattleSettlement].


## One attacker-versus-defender exchange with ratio-band casualties.
static func resolve(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attacker: int,
	further: bool,
	context: Dictionary
) -> Dictionary:
	var fee: Dictionary = ArmyAttackCost.charge(context, attacker)
	if QuickBattle.enabled(context, attacker, defender):
		return ArmyAttackCost.stamp(fee, QuickBattle.resolve_exchange(
			model, armies, province, defender, attacker, further, context
		))
	var defending: Array[ArmyState] = ArmyForce.armies_of(armies, province, defender)
	var attacking: Array[ArmyState] = ArmyForce.armies_of(armies, province, attacker)
	## The primary army read before any casualties commands the side, and wins
	## its medal (wiki: military-armies § Battle grouping).
	var def_lead: ArmyState = ArmyCommand.primary(defending)
	var atk_lead: ArmyState = ArmyCommand.primary(attacking)
	var def_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(def_lead, context, true), true, model, province, defender
	)
	var atk_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(atk_lead, context, false), false, model, province, attacker
	)
	var def_limit: int = int(def_mods["limit"])
	var atk_limit: int = int(atk_mods["limit"])
	var initial_defenders: int = mini(ArmyForce.side_regiments(defending), def_limit)
	var atk_deployed: int = mini(ArmyForce.side_regiments(attacking), atk_limit)
	## The line and the reserve as the exchange deals them, read before a blow
	## lands: a side that kept a reserve is named as such on the plate and in
	## the despatch whatever its line loses (wiki: combat § The line and the
	## reserve).
	var lines_open: Dictionary = ArmyModifiers.line_fields(
		attacking, atk_limit, defending, def_limit
	)
	## The line each side dealt when the exchange opened, read before a blow
	## lands: casualties are drawn from it, and the battle wear is spent over
	## these men alone, so a reserve never steps up into the slice after
	## casualties and takes wear it never earned (wiki: combat § The line and the
	## reserve; quick-battle § Wings and collapse).
	var atk_line: Array[String] = ArmyForce.line_ids(attacking, atk_limit)
	var def_line: Array[String] = ArmyForce.line_ids(defending, def_limit)
	## The besieging train's opening fire: silenced guns fall before the clash
	## (wiki: siege-mechanics § Emplaced Artillery; DR-20261110-22).
	var siege: Dictionary = AutoSiege.resolve(
		model, province, int(def_mods["fort"]), defender, attacking, atk_limit, context
	)
	## A silenced gun stops answering: only the standing pieces add their weight.
	var emplaced: float = float(def_mods["emplaced"])
	if not siege.is_empty():
		emplaced *= float(int(siege["guns_left"])) / float(maxi(int(siege["guns_start"]), 1))
	var def_strength: float = ArmyModifiers.strength(
		defending, def_limit, float(def_mods["multiplier"])
	) + emplaced
	var atk_strength: float = FortRules.wall_soak(
		ArmyModifiers.strength(attacking, atk_limit, float(atk_mods["multiplier"])),
		int(atk_mods["fort"]))
	var ratio: float = atk_strength / def_strength if def_strength > 0.0 else 0.0
	var band: Dictionary = ArmyBands.for_ratio(
		ratio, ArmyModifiers.morale(context, attacker),
		ArmyModifiers.morale(context, defender)
	)
	var attacker_lost: Array[String] = ArmyForce.apply_losses(
		armies, attacking, ceili(float(atk_deployed) * float(band["attacker"])), atk_limit
	)
	var defender_lost: Array[String] = ArmyForce.apply_losses(
		armies, defending, ceili(float(initial_defenders) * float(band["defender"])
		* float(def_mods["loss_scale"])), def_limit
	)
	RegimentCondition.wear(
		attacking,
		RegimentCondition.WOUND_SHARE
		* float(attacker_lost.size()) / float(maxi(atk_deployed, 1)),
		atk_limit, atk_line
	)
	RegimentCondition.wear(
		defending,
		RegimentCondition.WOUND_SHARE
		* float(defender_lost.size()) / float(maxi(initial_defenders, 1))
		* HospitalRules.triage_scale_at(model, province),
		def_limit, def_line
	)
	var atk_left: int = ArmyForce.side_regiments(ArmyForce.armies_of(armies, province, attacker))
	var def_left: int = ArmyForce.side_regiments(ArmyForce.armies_of(armies, province, defender))
	var outcome: int = ArmyCombat.Outcome.STALEMATE
	if def_left == 0 and atk_left > 0 and not bool(band.get("blunted", false)):
		outcome = ArmyCombat.Outcome.ATTACKER_VICTORY
	elif def_left == 0 and atk_left == 0:
		outcome = ArmyCombat.Outcome.MUTUAL_ANNIHILATION
	elif atk_left == 0:
		outcome = ArmyCombat.Outcome.DEFENDER_VICTORY
	# The hungrier attacker's gutted garrison keeps its owner (wiki: combat).
	var blunted: bool = outcome == ArmyCombat.Outcome.STALEMATE and def_left == 0 and atk_left > 0
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, province, attacker, defender, outcome,
		attacker_lost, defender_lost, atk_mods, def_mods
	)
	report["attack_cost"] = int(fee["due"])
	report["attack_paid"] = int(fee["paid"])
	report.merge(lines_open)
	if not siege.is_empty():
		report["siege"] = siege
	if outcome == ArmyCombat.Outcome.STALEMATE:
		report["blunted"] = blunted
	BattleSettlement.settle(
		model, armies, report, attacking, defending, atk_lead, def_lead, context,
		further, initial_defenders
	)
	return report
