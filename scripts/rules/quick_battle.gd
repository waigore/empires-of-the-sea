class_name QuickBattle
extends RefCounted
## One-province tactical combat (wiki: quick-battle): deterministic for a seed,
## three rounds, 3 CP a side. This class conducts the battle; the law it is
## fought under — its length, command points, automatic plans and line weight —
## lives in [QuickBattleTerms], its action tables in [QuickBattleActions], fort
## guns in [QuickBattleBattery] and the report the plate reads in
## [QuickBattleReport]. Casualties feed the same ArmyCombat pipeline as
## auto-resolve (REQ-P2-03, REQ-P3-01, REQ-P3-03).

## A battle is fought over this many rounds at most, each side spending this
## many command points a round; the plate, the simulator and the resolver read
## one answer (wiki: quick-battle § Core actions).
const MAX_ROUNDS: int = QuickBattleTerms.MAX_ROUNDS
const CP_PER_ROUND: int = QuickBattleTerms.CP_PER_ROUND


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
	state["attacker"]["plan"] = plan_for(atk_side, attacker, context, false)
	state["defender"]["plan"] = plan_for(def_side, defender, context, true, fort_level > 0)
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
	var rounds: Array[Dictionary] = []
	for round_index in MAX_ROUNDS:
		## A battle is fought by the two lines. A side that has lost its line
		## has lost the field — the reserve behind it was never committed, so
		## there is nothing left to strike and no blow left to deliver (wiki:
		## combat § The line and the reserve; quick-battle § Wings and collapse
		## — "a side whose wings have all broken has already lost its line").
		if QuickBattleActions.line_standing(state, "attacker") == 0 \
			or QuickBattleActions.line_standing(state, "defender") == 0:
			break
		rounds.append(_round(armies, state, guns, round_index, context))
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


## The plan one side is handed when the battle opens (see [QuickBattleTerms]).
static func plan_for(
	side: Array[ArmyState], owner: int, context: Dictionary, is_defender: bool,
	siege: bool = false
) -> String:
	return QuickBattleTerms.plan_for(side, owner, context, is_defender, siege)


static func actions_for(
	plan: String, is_defender: bool = false, siege: bool = false
) -> Array:
	return QuickBattleActions.actions_for(plan, is_defender, siege)


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


static func _round(
	armies: Array[ArmyState],
	state: Dictionary,
	guns: Array[Dictionary],
	round_index: int,
	context: Dictionary
) -> Dictionary:
	var order: Array[int] = _order(state, context)
	state["attacker"]["guard"] = 0.0
	state["defender"]["guard"] = 0.0
	state["attacker"]["exposed"] = false
	state["defender"]["exposed"] = false
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var def_side: Array[ArmyState] = state["defender"]["side"]
	var siege: bool = int((state["defender"]["mods"] as Dictionary).get("fort", 0)) > 0
	var log: Dictionary = {
		"round": round_index + 1,
		"actions": [] as Array[Dictionary],
		"attacker_count": ArmyForce.side_regiments(atk_side),
		"defender_count": ArmyForce.side_regiments(def_side),
		"guns": QuickBattleBattery.alive(guns),
		"terrain": String(state.get("terrain", "open")),
	}
	for owner: int in order:
		_orders(armies, state, guns, owner, siege, log)
	log["attacker_count"] = ArmyForce.side_regiments(atk_side)
	log["defender_count"] = ArmyForce.side_regiments(def_side)
	log["guns"] = QuickBattleBattery.alive(guns)
	log["gates"] = int((state.get("gates", {}) as Dictionary).get("broken", 0))
	_close_round(log, state, atk_side, def_side)
	return log


## One side's turn within a round: its scripted orders, then the garrison's
## emplaced battery, which answers after the orders it shelters.
static func _orders(
	armies: Array[ArmyState],
	state: Dictionary,
	guns: Array[Dictionary],
	owner: int,
	siege: bool,
	log: Dictionary
) -> void:
	var key: String = "attacker" if owner == int(state["attacker"]["owner"]) else "defender"
	var enemy_key: String = "defender" if key == "attacker" else "attacker"
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var def_side: Array[ArmyState] = state["defender"]["side"]
	var cp: int = CP_PER_ROUND
	for action: String in QuickBattleActions.actions_for(
		String(state[key]["plan"]), key == "defender", siege
	):
		## A line that has lost its last regiment spends no point and delivers no
		## blow, and nothing is left to strike when the enemy's line is gone
		## (wiki: quick-battle § Outcome and integration; § Wings and collapse).
		if cp < int(QuickBattleActions.ACTION_CP[action]) \
			or QuickBattleActions.line_standing(state, key) == 0 \
			or QuickBattleActions.line_standing(state, enemy_key) == 0:
			break
		cp -= int(QuickBattleActions.ACTION_CP[action])
		var entry: Dictionary = QuickBattleActions.resolve(
			armies, state, key, enemy_key, action, guns
		)
		log["actions"].append(entry)
		## A wing that lost its last regiment to this blow has broken: named
		## once, on the action that did it, on the line it stood in.
		entry.merge(QuickBattleWings.marks(state, key, enemy_key))
	# The emplaced battery fires after the side's actions, into one wing of
	# the besieging line; the guns are the fort's own units
	# (wiki: quick-battle § Wings and collapse).
	if key == "defender" and QuickBattleBattery.alive(guns) > 0 \
		and QuickBattleActions.line_standing(state, "attacker") > 0:
		var volley: Dictionary = QuickBattleBattery.volley_entry(armies, state, guns, owner)
		if not volley.is_empty():
			log["actions"].append(volley)


## What a round leaves behind, read by the plate: the wings as they stand and
## the ones the line has lost, then the condition the rail prints — never a
## recomputation.
static func _close_round(
	log: Dictionary, state: Dictionary, atk_side: Array[ArmyState], def_side: Array[ArmyState]
) -> void:
	log.merge(QuickBattleWings.record(state))
	log["attacker_health"] = RegimentCondition.entries(atk_side)
	log["defender_health"] = RegimentCondition.entries(def_side)
	log["attacker_strength"] = RegimentCondition.average(atk_side)
	log["defender_strength"] = RegimentCondition.average(def_side)
	log["attacker_cohesion"] = int(state["attacker"]["cohesion"])
	log["defender_cohesion"] = int(state["defender"]["cohesion"])


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


static func _order(state: Dictionary, context: Dictionary) -> Array[int]:
	var atk: Dictionary = state["attacker"]
	var def: Dictionary = state["defender"]
	var atk_side: Array[ArmyState] = atk["side"]
	var def_side: Array[ArmyState] = def["side"]
	var atk_score: float = ArmyCommand.initiative(
		atk_side, ArmyCommand.medals(atk_side, context, false)
	)
	var def_score: float = ArmyCommand.initiative(
		def_side, ArmyCommand.medals(def_side, context, true)
	)
	var atk_owner: int = int(atk["owner"])
	var def_owner: int = int(def["owner"])
	if is_equal_approx(atk_score, def_score):
		if atk_owner < def_owner:
			return [atk_owner, def_owner]
		return [def_owner, atk_owner]
	if atk_score > def_score:
		return [atk_owner, def_owner]
	return [def_owner, atk_owner]


## One side's battle weight (see [QuickBattleTerms]).
static func effective_strength(
	side: Array[ArmyState],
	limit: int,
	cohesion: int,
	multiplier: float,
	gun_weight: float = 0.0,
	line: Array[String] = []
) -> float:
	return QuickBattleTerms.effective_strength(
		side, limit, cohesion, multiplier, gun_weight, line
	)


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
	var atk: float = effective_strength(
		atk_side,
		int(state["attacker"]["limit"]),
		int(state["attacker"]["cohesion"]),
		float(atk_mods["multiplier"]),
		0.0,
		QuickBattleActions.line_of(state["attacker"])
	)
	var def: float = effective_strength(
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
