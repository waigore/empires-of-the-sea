class_name QuickBattle
extends RefCounted
## One-province tactical combat (wiki: quick-battle): deterministic for a seed,
## three rounds, 3 CP a side. This class conducts the battle; the law it is
## fought under — its length, command points, automatic plans and line weight —
## lives in [QuickBattleTerms], its action tables in [QuickBattleActions], fort
## guns in [QuickBattleBattery], its rounds in [QuickBattleRounds] and the
## report the plate reads in [QuickBattleReport]. Casualties feed the same
## ArmyCombat pipeline as auto-resolve (REQ-P2-03, REQ-P3-01, REQ-P3-03).


static func enabled(context: Dictionary, attacker: int, defender: int) -> bool:
	if not bool(context.get("quick_battle", false)):
		return false
	var player: int = int(context.get("player_faction", -1))
	return player == attacker or player == defender


## Resolves one attacker-versus-defender exchange as a three-round battle.
static func resolve_exchange(
	model: MapModel,
	armies: Array[ArmyState],
	province: int,
	defender: int,
	attacker: int,
	further: bool,
	context: Dictionary
) -> Dictionary:
	var def_side: Array[ArmyState] = ArmyForce.armies_of(armies, province, defender)
	var atk_side: Array[ArmyState] = ArmyForce.armies_of(armies, province, attacker)
	## The side's commander is the primary army read before the rounds
	## (wiki: military-armies § Battle grouping): its line and any medal agree.
	var def_lead: ArmyState = ArmyCommand.primary(def_side)
	var atk_lead: ArmyState = ArmyCommand.primary(atk_side)
	var def_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(def_lead, context, true), true, model, province, defender
	)
	var atk_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals_of(atk_lead, context, false), false, model, province, attacker
	)
	var fort_level: int = int(def_mods["fort"])
	var guns: Array[Dictionary] = QuickBattleBattery.make(fort_level, context, defender)
	## The ground and the gates are read once, when the battle opens: the wall
	## lanes and the terrain do not change under the fighting (wiki: quick-battle
	## § Terrain; siege-mechanics § Gates and Sortie).
	var terrain: String = SiegeLanes.lane_terrain(
		model, province, fort_level, String(context.get("terrain_override", ""))
	)
	var gates: Dictionary = SiegeLanes.gates_for(fort_level)
	var state: Dictionary = {
		"attacker": _side_state(atk_side, attacker, int(atk_mods["limit"]), atk_mods),
		"defender": _side_state(def_side, defender, int(def_mods["limit"]), def_mods),
		"terrain": terrain,
		"gates": gates,
	}
	state["attacker"]["plan"] = QuickBattleTerms.plan_for(atk_side, attacker, context, false)
	state["defender"]["plan"] = QuickBattleTerms.plan_for(
		def_side, defender, context, true, fort_level > 0,
		QuickBattleActions.line_of(state["defender"])
	)
	## The line's wings, dealt when the battle opens: the horse holds the flanks
	## and the foot and guns the centre. A garrison behind a wall holds no wings
	## — its lanes are the parapet and what waits behind it (wiki: quick-battle
	## § Wings and collapse; siege-mechanics § Quick Battle lanes).
	state["attacker"]["wings"] = QuickBattleWings.deploy(atk_side, int(atk_mods["limit"]))
	if fort_level <= 0:
		state["defender"]["wings"] = QuickBattleWings.deploy(
			def_side, int(def_mods["limit"])
		)
	var wings_open: Dictionary = QuickBattleWings.counts_of(state)
	## A hospital in the province triages the defender's survivors: the same
	## wear scale auto-resolve applies (DR-20261111-12).
	state["defender"]["triage"] = HospitalRules.triage_scale_at(model, province)
	var atk_start: int = ArmyForce.side_regiments(atk_side)
	var def_start: int = ArmyForce.side_regiments(def_side)
	## The line and the reserve as the battle deals them, read before a blow
	## lands: a side that kept a reserve is named as such on the plate and in
	## the despatch whatever its line loses (wiki: combat § The line and the
	## reserve — "the battle plate prints `Line — <crown> N of M in the line`").
	var lines_open: Dictionary = ArmyModifiers.line_fields(
		atk_side, int(atk_mods["limit"]), def_side, int(def_mods["limit"])
	)
	## Lane split when the battle opened: the line's foot on the wall and its horse
	## and guns behind it — a reserve mans neither lane — then the lanes shrink as
	## casualties are drawn from them (wiki: quick-battle § Wings and collapse;
	## combat § The line and the reserve).
	var lanes_start: Dictionary = SiegeLanes.line_ids(def_side, int(def_mods["limit"]))
	state["defender"]["lanes"] = lanes_start
	var wall_start: int = (lanes_start["wall"] as Array).size()
	var behind_start: int = (lanes_start["behind"] as Array).size()
	var atk_types: Dictionary = _type_counts(atk_side)
	var def_types: Dictionary = _type_counts(def_side)
	var rounds: Array[Dictionary] = QuickBattleRounds.fight(armies, state, guns, context)
	var atk_left: int = ArmyForce.side_regiments(atk_side)
	var def_left: int = ArmyForce.side_regiments(def_side)
	var fort_downgraded: bool = QuickBattleBattery.downgrade_fort(
		model, province, fort_level, guns
	)
	var fort_after: int = FortRules.level_at(model, province)
	var outcome: int = _outcome(
		atk_left, def_left, state, guns, atk_mods, def_mods
	)
	var atk_lost: Array[String] = state["attacker"]["lost"]
	var def_lost: Array[String] = state["defender"]["lost"]
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, province, attacker, defender, outcome, atk_lost, def_lost,
		atk_mods, def_mods
	)
	report["quick"] = QuickBattleReport.build(
		state, rounds, guns, context, defender,
		{
			"attacker_start": atk_start,
			"defender_start": def_start,
			"level": fort_level,
			"downgraded": fort_downgraded,
			"after": fort_after,
			"wall": wall_start,
			"behind": behind_start,
			"terrain": terrain,
			"gates": gates,
		},
		{"attacker": atk_mods, "defender": def_mods},
		wings_open
	)
	report["attacker_detail"] = _losses(atk_types, _type_counts(atk_side))
	report["defender_detail"] = _losses(def_types, _type_counts(def_side))
	report.merge(lines_open)
	BattleSettlement.settle(
		model, armies, report, atk_side, def_side, atk_lead, def_lead, context,
		further, def_start
	)
	return report


static func _side_state(
	side: Array[ArmyState], owner: int, limit: int, mods: Dictionary
) -> Dictionary:
	return {
		"side": side,
		"owner": owner,
		"limit": limit,
		"mods": mods,
		"cohesion": 3,
		"guard": 0.0,
		"lost": [] as Array[String],
		"plan": "balanced",
		## A sortieing defender stands outside the wall for the round.
		"exposed": false,
		## The three wings of a line in the open; empty behind a wall.
		"wings": {},
		## The men the battle deals into the line when it opens: the wings, the
		## bled lanes, the mauled survivors and the outcome all read this one
		## slice, so a reserve never steps up as the line falls (wiki: combat
		## § The line and the reserve).
		"line": ArmyForce.line_ids(side, limit),
		"broken": [] as Array[String],
	}


## Regiments held by type, so a battle can report what it cost by type.
static func _type_counts(side: Array[ArmyState]) -> Dictionary:
	var counts: Dictionary = {}
	for type_id: String in ArmyForce.side_types(side):
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	return counts


## before minus after: the regiments a side actually lost, by type.
static func _losses(before: Dictionary, after: Dictionary) -> Dictionary:
	var lost: Dictionary = {}
	for type_id: Variant in before.keys():
		var gone: int = int(before[type_id]) - int(after.get(type_id, 0))
		if gone > 0:
			lost[String(type_id)] = gone
	return lost


static func _outcome(
	atk_left: int,
	def_left: int,
	state: Dictionary,
	guns: Array[Dictionary],
	atk_mods: Dictionary,
	def_mods: Dictionary
) -> int:
	if def_left == 0 and atk_left > 0:
		return ArmyCombat.Outcome.ATTACKER_VICTORY
	if def_left == 0 and atk_left == 0:
		return ArmyCombat.Outcome.MUTUAL_ANNIHILATION
	if atk_left == 0:
		return ArmyCombat.Outcome.DEFENDER_VICTORY
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var def_side: Array[ArmyState] = state["defender"]["side"]
	var atk: float = QuickBattleTerms.effective_strength(
		atk_side,
		int(state["attacker"]["limit"]),
		int(state["attacker"]["cohesion"]),
		float(atk_mods["multiplier"]),
		0.0,
		QuickBattleActions.line_of(state["attacker"])
	)
	var def: float = QuickBattleTerms.effective_strength(
		def_side,
		int(state["defender"]["limit"]),
		int(state["defender"]["cohesion"]),
		float(def_mods["multiplier"]),
		QuickBattleBattery.strength(guns),
		QuickBattleActions.line_of(state["defender"])
	)
	## Both lines spent but each side still keeps reserves: the field is nobody's
	## (quick-battle § Outcome and integration — "mutual exhaustion"). A defender
	## whose line is gone has lost the field though it keeps its province (an
	## advantage, never a flip) when the attacker's line still stands.
	if def <= 0.0:
		return ArmyCombat.Outcome.ATTACKER_ADVANTAGE if atk > 0.0 \
			else ArmyCombat.Outcome.STALEMATE
	return ArmyCombat.Outcome.ATTACKER_ADVANTAGE if atk / def >= 1.0 \
		else ArmyCombat.Outcome.DEFENDER_VICTORY
