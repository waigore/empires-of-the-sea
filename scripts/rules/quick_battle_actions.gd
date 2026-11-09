class_name QuickBattleActions
extends RefCounted
## Plan scripts and one action's resolution for Quick Battle. Tables stay here
## so [QuickBattle] only orchestrates rounds (REQ-P3-01, REQ-P3-03).


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
	if key == "attacker" and QuickBattleBattery.alive(guns) > 0:
		var destroyed: int = QuickBattleBattery.hit(guns, maxi(1, wanted))
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
