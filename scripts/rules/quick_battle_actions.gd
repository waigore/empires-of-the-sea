class_name QuickBattleActions
extends RefCounted
## Plan scripts and one action's resolution for Quick Battle. Tables stay here
## so [QuickBattle] only orchestrates rounds (REQ-P3-01, REQ-P3-03).
## A siege routes casualties through [SiegeLanes]: the wall shelters the
## garrison, only artillery reaches behind it, and a sortie trades that shelter
## for every regiment's fire.


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


static func actions_for(plan: String) -> Array:
	return (PLANS.get(plan, PLANS["balanced"]) as Array).duplicate()


## Resolve one scripted action against the enemy side (and guns, when assaulting).
static func resolve(
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
		"battery_hit": 0,
		"wall_lost": 0,
		"behind_lost": 0,
		"turned": 0,
		"sortie": false,
		"guard": 0.0,
		"hits": [] as Array[Dictionary],
		"mauled": 0,
		"own_hits": [] as Array[Dictionary],
		"own_mauled": 0,
	}
	if action == "maneuver":
		me["cohesion"] = mini(3, int(me["cohesion"]) + 1)
		return entry
	if action == "entrench" or action == "fall_back":
		me["guard"] = maxf(float(me["guard"]), float(ACTION_GUARD[action]))
		entry["guard"] = float(me["guard"])
		return entry
	var fort: int = int((state["defender"].get("mods", {}) as Dictionary).get("fort", 0))
	var siege: bool = fort > 0
	var me_side: Array[ArmyState] = me["side"]
	var enemy_side: Array[ArmyState] = enemy["side"]
	var ratio: float = float(ACTION_DAMAGE[action]) * (float(me["cohesion"]) / 3.0)
	ratio *= 1.0 - clampf(float(enemy["guard"]), 0.0, 0.8)
	var enemy_count: int = ArmyCombat.side_regiments(enemy_side)
	## The action's published share of a line, spent as tactical weight: a
	## stronger line breaks more of the enemy, and a tougher enemy line loses
	## fewer regiments to the same blow (wiki: quick-battle § Cohesion and
	## effective strength).
	var blow: float = ratio * ArmyModifiers.strength(
		me_side, int(me["limit"]), _multiplier(me)
	) / ArmyModifiers.average_rank(enemy_side, int(enemy["limit"]))
	var wanted: int = ceili(blow)
	# The battery is shot at before the men behind it; melee cannot reach it. A
	# standing gun spends the blow before the lanes, so the garrison is sheltered
	# until the battery is quiet (wiki: siege-mechanics § Quick Battle lanes).
	if key == "attacker" and QuickBattleBattery.alive(guns) > 0 \
		and SiegeLanes.can_reach_wall(me_side):
		var battery: Dictionary = QuickBattleBattery.absorb(guns, maxi(1, wanted))
		entry["guns_destroyed"] = int(battery["destroyed"])
		entry["battery_hit"] = int(battery["absorbed"])
		wanted = maxi(0, wanted - int(battery["absorbed"]))
	if siege and key == "defender":
		var sortie: bool = action == "assault"
		entry["sortie"] = sortie
		if sortie:
			entry["label"] = "Sortie"
		me["exposed"] = sortie
		if not sortie:
			wanted = ceili(float(wanted) * SiegeLanes.return_fire_share(me_side))
	if enemy_count <= 0:
		return entry
	var lost: Array[String] = []
	if wanted > 0 and siege and key == "attacker":
		var split: Dictionary = SiegeLanes.strike(
			armies, me_side, enemy_side, wanted, int(enemy["limit"]), fort,
			bool(enemy.get("exposed", false))
		)
		var wall_lost: Array[String] = split["wall"]
		var behind_lost: Array[String] = split["behind"]
		lost.append_array(wall_lost)
		lost.append_array(behind_lost)
		entry["wall_lost"] = wall_lost.size()
		entry["behind_lost"] = behind_lost.size()
		entry["turned"] = int(split["turned"])
	elif wanted > 0:
		lost = ArmyCombat.apply_losses(armies, enemy_side, wanted, int(enemy["limit"]))
	enemy["lost"].append_array(lost)
	# The blow that broke a regiment also mauls the men still standing: the
	# plate shows every survivor's health drop (wiki: combat § Strength).
	var pool: float = float(lost.size()) * RegimentCondition.HP_PER_SLOT
	entry["hits"] = RegimentCondition.damage_side(enemy_side, pool, int(enemy["limit"]))
	entry["mauled"] = (entry["hits"] as Array).size()
	if key == "attacker":
		entry["defender_lost"] = lost.size()
	else:
		entry["attacker_lost"] = lost.size()
	if lost.size() >= ceili(float(enemy_count) * 0.25):
		enemy["cohesion"] = maxi(0, int(enemy["cohesion"]) - 1)
	return _pay_own(armies, me, key, entry, action)


## A side's combat multiplier from its modifier bundle; an unmodified side
## (tests, a hand-built state) fights at 1.0.
static func _multiplier(side: Dictionary) -> float:
	var mods: Dictionary = side.get("mods", {}) as Dictionary
	return float(mods.get("multiplier", 1.0))


## An action's own price (an assault, or a sortie, costs the side that launches it).
static func _pay_own(
	armies: Array[ArmyState], me: Dictionary, key: String, entry: Dictionary, action: String
) -> Dictionary:
	var self_ratio: float = float(ACTION_SELF[action]) * (float(me["cohesion"]) / 3.0)
	if self_ratio <= 0.0:
		return entry
	var own_side: Array[ArmyState] = me["side"]
	var wanted_own: int = ceili(self_ratio * float(ArmyCombat.side_regiments(own_side)))
	var own: Array[String] = ArmyCombat.apply_losses(
		armies, own_side, wanted_own, int(me["limit"])
	)
	me["lost"].append_array(own)
	var pool: float = float(own.size()) * RegimentCondition.HP_PER_SLOT
	entry["own_hits"] = RegimentCondition.damage_side(own_side, pool, int(me["limit"]))
	entry["own_mauled"] = (entry["own_hits"] as Array).size()
	if key == "attacker":
		entry["attacker_lost"] = int(entry["attacker_lost"]) + own.size()
	else:
		entry["defender_lost"] = int(entry["defender_lost"]) + own.size()
	return entry
