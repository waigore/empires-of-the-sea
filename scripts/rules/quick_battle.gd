class_name QuickBattle
extends RefCounted
## One-province tactical combat (wiki: quick-battle): deterministic for a seed,
## three rounds, 3 CP a side. Action tables live in [QuickBattleActions]; fort
## guns in [QuickBattleBattery]. Casualties feed the same ArmyCombat pipeline as
## auto-resolve (REQ-P2-03, REQ-P3-01, REQ-P3-03).

const MAX_ROUNDS: int = 3
const CP_PER_ROUND: int = 3


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
	var def_side: Array[ArmyState] = ArmyCombat.armies_of(armies, province, defender)
	var atk_side: Array[ArmyState] = ArmyCombat.armies_of(armies, province, attacker)
	var def_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals(def_side, context), true, model, province, defender
	)
	var atk_mods: Dictionary = ArmyModifiers.modifiers(
		context, ArmyCommand.medals(atk_side, context), false, model, province, attacker
	)
	var fort_level: int = int(def_mods["fort"])
	var guns: Array[Dictionary] = QuickBattleBattery.make(fort_level, context, defender)
	var state: Dictionary = {
		"attacker": _side_state(atk_side, attacker, int(atk_mods["limit"]), atk_mods),
		"defender": _side_state(def_side, defender, int(def_mods["limit"]), def_mods),
	}
	state["attacker"]["plan"] = plan_for(atk_side, attacker, context, false)
	state["defender"]["plan"] = plan_for(def_side, defender, context, true)
	var atk_start: int = ArmyCombat.side_regiments(atk_side)
	var def_start: int = ArmyCombat.side_regiments(def_side)
	var rounds: Array[Dictionary] = []
	for round_index in MAX_ROUNDS:
		if ArmyCombat.side_regiments(atk_side) == 0:
			break
		if ArmyCombat.side_regiments(def_side) == 0:
			break
		rounds.append(_round(armies, state, guns, round_index, context))
	var atk_left: int = ArmyCombat.side_regiments(atk_side)
	var def_left: int = ArmyCombat.side_regiments(def_side)
	var guns_left: int = QuickBattleBattery.alive(guns)
	var fort_downgraded: bool = QuickBattleBattery.downgrade_fort(
		model, province, fort_level, guns
	)
	var fort_after: int = FortRules.level_at(model, province)
	var outcome: int = _outcome(
		atk_left, def_left, state, guns_left, atk_mods, def_mods
	)
	var report: Dictionary = {
		"province": province,
		"attacker": attacker,
		"defender": defender,
		"outcome": outcome,
		"attacker_lost": state["attacker"]["lost"],
		"defender_lost": state["defender"]["lost"],
		"captured": false,
		"garrison": 0,
		"recovered_type": "",
		"attacker_medals": int(atk_mods["medals"]),
		"defender_medals": int(def_mods["medals"]),
		"battle_mode": FortRules.battle_mode(fort_level),
		"fort_level": fort_level,
		"medal_gain": "",
		"medal_owner": -1,
	}
	report["quick"] = {
		"plan": String(state["attacker"]["plan"]),
		"defender_plan": String(state["defender"]["plan"]),
		"rounds": rounds,
		"attacker_start": atk_start,
		"defender_start": def_start,
		"attacker_left": atk_left,
		"defender_left": def_left,
		"guns_start": guns.size(),
		"guns_left": guns_left,
		"fort_downgraded": fort_downgraded,
		"fort_after": fort_after,
		"attacker_cohesion": int(state["attacker"]["cohesion"]),
		"defender_cohesion": int(state["defender"]["cohesion"]),
	}
	if outcome == ArmyCombat.Outcome.ATTACKER_VICTORY:
		ArmyCombat.flip(model, province, attacker)
		report["captured"] = true
		report["medal_gain"] = ArmyCommand.award(context, atk_side, attacker)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = attacker
	elif outcome == ArmyCombat.Outcome.DEFENDER_VICTORY:
		report["medal_gain"] = ArmyCommand.award(context, def_side, defender)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = defender
	elif outcome == ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
		report["medal_gain"] = ArmyCommand.award(context, atk_side, attacker)
		if not String(report["medal_gain"]).is_empty():
			report["medal_owner"] = attacker
	elif outcome == ArmyCombat.Outcome.MUTUAL_ANNIHILATION and further:
		var recovery: Dictionary = ArmyCombat.recover_garrison(
			armies, province, defender, def_start
		)
		report["garrison"] = int(recovery.get("count", 0))
		report["recovered_type"] = String(recovery.get("type", ""))
	return report


static func plan_for(
	side: Array[ArmyState], owner: int, context: Dictionary, is_defender: bool
) -> String:
	if owner == int(context.get("player_faction", -1)):
		var chosen: String = String(context.get("battle_plan", "balanced"))
		return chosen if QuickBattleActions.PLANS.has(chosen) else "balanced"
	var riders: float = 0.0
	for army: ArmyState in side:
		if army != null:
			riders = maxf(riders, army.cavalry_share())
	if riders >= 0.3:
		return "aggressive"
	return "defensive" if is_defender else "balanced"


static func actions_for(plan: String) -> Array:
	return QuickBattleActions.actions_for(plan)


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
	var atk_side: Array[ArmyState] = state["attacker"]["side"]
	var def_side: Array[ArmyState] = state["defender"]["side"]
	var log: Dictionary = {
		"round": round_index + 1,
		"actions": [] as Array[Dictionary],
		"attacker_count": ArmyCombat.side_regiments(atk_side),
		"defender_count": ArmyCombat.side_regiments(def_side),
		"guns": QuickBattleBattery.alive(guns),
	}
	for owner: int in order:
		var key: String = "attacker" if owner == int(state["attacker"]["owner"]) else "defender"
		var enemy_key: String = "defender" if key == "attacker" else "attacker"
		var cp: int = CP_PER_ROUND
		for action: String in QuickBattleActions.actions_for(String(state[key]["plan"])):
			if cp < int(QuickBattleActions.ACTION_CP[action]):
				break
			cp -= int(QuickBattleActions.ACTION_CP[action])
			var entry: Dictionary = QuickBattleActions.resolve(
				armies, state, key, enemy_key, action, guns
			)
			log["actions"].append(entry)
		# The emplaced battery fires after the side's actions.
		if key == "defender" and QuickBattleBattery.alive(guns) > 0:
			var hit: int = QuickBattleBattery.fire(armies, state, guns)
			if hit > 0:
				log["actions"].append({
					"side": owner,
					"action": "battery",
					"label": "Emplaced battery",
					"attacker_lost": hit,
					"defender_lost": 0,
					"guns_destroyed": 0,
				})
	log["attacker_count"] = ArmyCombat.side_regiments(atk_side)
	log["defender_count"] = ArmyCombat.side_regiments(def_side)
	log["guns"] = QuickBattleBattery.alive(guns)
	log["attacker_cohesion"] = int(state["attacker"]["cohesion"])
	log["defender_cohesion"] = int(state["defender"]["cohesion"])
	return log


static func _order(state: Dictionary, context: Dictionary) -> Array[int]:
	var atk: Dictionary = state["attacker"]
	var def: Dictionary = state["defender"]
	var atk_side: Array[ArmyState] = atk["side"]
	var def_side: Array[ArmyState] = def["side"]
	var atk_score: float = ArmyCommand.initiative(
		atk_side, ArmyCommand.medals(atk_side, context)
	)
	var def_score: float = ArmyCommand.initiative(
		def_side, ArmyCommand.medals(def_side, context)
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


static func _effective(
	side: Array[ArmyState], cohesion: int, mods: Dictionary, guns_alive: int
) -> float:
	var count: float = float(ArmyCombat.side_regiments(side))
	return (count * (float(cohesion) / 3.0) + float(guns_alive) * 0.5) \
		* float(mods["multiplier"])


static func _outcome(
	atk_left: int,
	def_left: int,
	state: Dictionary,
	guns_left: int,
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
	var atk: float = _effective(
		atk_side, int(state["attacker"]["cohesion"]), atk_mods, 0
	)
	var def: float = _effective(
		def_side, int(state["defender"]["cohesion"]), def_mods, guns_left
	)
	return ArmyCombat.Outcome.ATTACKER_ADVANTAGE if def <= 0.0 or atk / def >= 1.0 \
		else ArmyCombat.Outcome.DEFENDER_VICTORY
