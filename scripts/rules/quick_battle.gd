class_name QuickBattle
extends RefCounted
## One-province tactical combat (wiki: quick-battle): deterministic for a seed,
## three rounds, 3 CP a side. The human's plan picks the script; casualties feed
## the same ArmyCombat pipeline as auto-resolve (REQ-P2-03, REQ-P3-03).

const MAX_ROUNDS: int = 3
const CP_PER_ROUND: int = 3
const GUN_HP: float = 2.0
const GUN_FIRE: float = 0.03

const PLANS: Dictionary = {
	"aggressive": ["maneuver", "assault"], "balanced": ["volley", "entrench", "volley"],
	"defensive": ["fall_back", "volley"],
}
const ACTION_CP: Dictionary = {
	"volley": 1, "entrench": 1, "maneuver": 1, "assault": 2, "fall_back": 2,
}
const ACTION_DAMAGE: Dictionary = {
	"volley": 0.12, "assault": 0.26, "entrench": 0.0, "maneuver": 0.0, "fall_back": 0.0,
}
const ACTION_SELF: Dictionary = {
	"volley": 0.0, "assault": 0.10, "entrench": 0.0, "maneuver": 0.0, "fall_back": 0.0,
}
const ACTION_GUARD: Dictionary = {
	"volley": 0.0, "assault": 0.0, "entrench": 0.45, "maneuver": 0.0, "fall_back": 0.25,
}
const ACTION_LABEL: Dictionary = {
	"volley": "Volley fire", "assault": "Assault", "entrench": "Entrench",
	"maneuver": "Maneuver", "fall_back": "Fall back",
}


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
	var guns: Array[Dictionary] = _make_guns(fort_level, context, defender)
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
	var guns_left: int = _alive_guns(guns)
	var fort_downgraded: bool = _downgrade_fort(model, province, fort_level, guns)
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
		return chosen if PLANS.has(chosen) else "balanced"
	var riders: float = 0.0
	for army: ArmyState in side:
		if army != null:
			riders = maxf(riders, army.cavalry_share())
	if riders >= 0.3:
		return "aggressive"
	return "defensive" if is_defender else "balanced"


static func actions_for(plan: String) -> Array:
	return (PLANS.get(plan, PLANS["balanced"]) as Array).duplicate()


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
		"guns": _alive_guns(guns),
	}
	for owner: int in order:
		var key: String = "attacker" if owner == int(state["attacker"]["owner"]) else "defender"
		var enemy_key: String = "defender" if key == "attacker" else "attacker"
		var cp: int = CP_PER_ROUND
		for action: String in actions_for(String(state[key]["plan"])):
			if cp < int(ACTION_CP[action]):
				break
			cp -= int(ACTION_CP[action])
			var entry: Dictionary = _act(armies, state, key, enemy_key, action, guns)
			log["actions"].append(entry)
		# The emplaced battery fires after the side's actions.
		if key == "defender" and _alive_guns(guns) > 0:
			var hit: int = _gun_fire(armies, state, guns)
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
	log["guns"] = _alive_guns(guns)
	log["attacker_cohesion"] = int(state["attacker"]["cohesion"])
	log["defender_cohesion"] = int(state["defender"]["cohesion"])
	return log


static func _act(
	armies: Array[ArmyState],
	state: Dictionary,
	key: String,
	enemy_key: String,
	action: String,
	guns: Array[Dictionary]
) -> Dictionary:
	var me: Dictionary = state[key]
	var enemy: Dictionary = state[enemy_key]
	var entry: Dictionary = {
		"side": int(me["owner"]),
		"action": action,
		"label": String(ACTION_LABEL[action]),
		"attacker_lost": 0,
		"defender_lost": 0,
		"guns_destroyed": 0,
		"guard": 0.0,
	}
	if action == "maneuver":
		me["cohesion"] = mini(3, int(me["cohesion"]) + 1)
		return entry
	if action == "entrench" or action == "fall_back":
		me["guard"] = maxf(float(me["guard"]), float(ACTION_GUARD[action]))
		entry["guard"] = float(me["guard"])
		return entry
	var ratio: float = float(ACTION_DAMAGE[action]) * (float(me["cohesion"]) / 3.0)
	ratio *= 1.0 - clampf(float(enemy["guard"]), 0.0, 0.8)
	var enemy_side: Array[ArmyState] = enemy["side"]
	var enemy_count: int = ArmyCombat.side_regiments(enemy_side)
	var wanted: int = ceili(ratio * float(maxi(enemy_count, 1)))
	if key == "attacker" and _alive_guns(guns) > 0:
		var destroyed: int = _hit_guns(guns, maxi(1, wanted))
		entry["guns_destroyed"] = destroyed
		wanted = maxi(0, wanted - destroyed)
	if enemy_count <= 0:
		return entry
	var lost: Array[String] = ArmyCombat.apply_losses(
		armies, enemy_side, wanted, int(enemy["limit"])
	)
	enemy["lost"].append_array(lost)
	if key == "attacker":
		entry["defender_lost"] = lost.size()
	else:
		entry["attacker_lost"] = lost.size()
	if lost.size() >= ceili(float(enemy_count) * 0.25):
		enemy["cohesion"] = maxi(0, int(enemy["cohesion"]) - 1)
	var self_ratio: float = float(ACTION_SELF[action]) * (float(me["cohesion"]) / 3.0)
	if self_ratio > 0.0:
		var own_side: Array[ArmyState] = me["side"]
		var own: Array[String] = ArmyCombat.apply_losses(
			armies, own_side, ceili(self_ratio * float(ArmyCombat.side_regiments(own_side))),
			int(me["limit"])
		)
		me["lost"].append_array(own)
		if key == "attacker":
			entry["attacker_lost"] = int(entry["attacker_lost"]) + own.size()
		else:
			entry["defender_lost"] = int(entry["defender_lost"]) + own.size()
	return entry


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


static func _make_guns(level: int, context: Dictionary, defender: int) -> Array[Dictionary]:
	var guns: Array[Dictionary] = []
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var unlocked: Dictionary = tech.get(defender, {}) as Dictionary
	var type_id: String = FortRules.emplaced_type(unlocked)
	for _index in FortRules.guns(level):
		guns.append({"hp": GUN_HP, "alive": true, "type": type_id})
	return guns


static func _alive_guns(guns: Array[Dictionary]) -> int:
	var alive: int = 0
	for gun: Dictionary in guns:
		if bool(gun["alive"]):
			alive += 1
	return alive


static func _hit_guns(guns: Array[Dictionary], damage: int) -> int:
	var destroyed: int = 0
	var left: float = float(damage)
	for gun: Dictionary in guns:
		if left <= 0.0:
			break
		if not bool(gun["alive"]):
			continue
		var take: float = minf(left, float(gun["hp"]))
		gun["hp"] = float(gun["hp"]) - take
		left -= take
		if float(gun["hp"]) <= 0.0:
			gun["alive"] = false
			destroyed += 1
	return destroyed


static func _gun_fire(
	armies: Array[ArmyState], state: Dictionary, guns: Array[Dictionary]
) -> int:
	var atk: Dictionary = state["attacker"]
	var atk_side: Array[ArmyState] = atk["side"]
	var count: int = ArmyCombat.side_regiments(atk_side)
	if count <= 0:
		return 0
	var wanted: int = ceili(float(_alive_guns(guns)) * GUN_FIRE * float(count))
	var lost: Array[String] = ArmyCombat.apply_losses(
		armies, atk_side, wanted, int(atk["limit"])
	)
	atk["lost"].append_array(lost)
	return lost.size()


static func _downgrade_fort(
	model: MapModel, province: int, level: int, guns: Array[Dictionary]
) -> bool:
	if level <= 0 or guns.is_empty() or _alive_guns(guns) > 0:
		return false
	var data: ProvinceState = model.get_province(province)
	if data == null:
		return false
	data.fort_level = maxi(0, level - 1)
	return true


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
