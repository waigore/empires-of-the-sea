class_name QuickBattleReport
extends RefCounted
## The `quick` slice of a battle report: what the plate, the despatch and the
## condition rail print about the three rounds. [QuickBattle] fights the battle;
## this module writes the shape its readers share, so a field added for the
## plate is added for every reader (REQ-P2-03, REQ-P3-01).
##
## Pure data: no nodes, no state beyond the dictionaries it is handed
## (REQ-P3-03).


## Builds the slice. `opening` carries the facts read when the battle opened —
## the lines' strength, the wall lanes, the ground, the gates and the fort — and
## `mods` the two sides' modifier bundles. Left counts and cohesion are read
## from `state`, which the rounds have already spent.
static func build(
	state: Dictionary,
	rounds: Array[Dictionary],
	guns: Array[Dictionary],
	context: Dictionary,
	defender: int,
	opening: Dictionary,
	mods: Dictionary,
	wings_open: Dictionary
) -> Dictionary:
	var gates: Dictionary = opening["gates"]
	var atk_mods: Dictionary = mods["attacker"]
	var def_mods: Dictionary = mods["defender"]
	var report: Dictionary = {
		"plan": String(state["attacker"]["plan"]),
		"defender_plan": String(state["defender"]["plan"]),
		"rounds": rounds,
		"attacker_start": int(opening["attacker_start"]),
		"defender_start": int(opening["defender_start"]),
		"attacker_left": ArmyForce.side_regiments(state["attacker"]["side"]),
		"defender_left": ArmyForce.side_regiments(state["defender"]["side"]),
		"guns_start": guns.size(),
		"guns_left": QuickBattleBattery.alive(guns),
		"guns_lost": guns.size() - QuickBattleBattery.alive(guns),
		"gun_type": gun_type(context, defender),
		"fort_downgraded": bool(opening["downgraded"]),
		"fort_after": int(opening["after"]),
		## The wall lanes the defender held when the battle opened, and how often
		## the garrison left them to sortie (wiki: siege-mechanics).
		"lanes": {
			"wall": int(opening["wall"]),
			"behind": int(opening["behind"]),
		},
		"sorties": sortie_count(rounds),
		"terrain": String(opening["terrain"]),
		"terrain_label": SiegeGround.terrain_label(String(opening["terrain"])),
		"gates": gates.duplicate(),
		"breaches": int(gates.get("broken", 0)),
		"limits": {
			"attacker": int(atk_mods["limit"]),
			"defender": int(def_mods["limit"]),
		},
		"attacker_cohesion": int(state["attacker"]["cohesion"]),
		"defender_cohesion": int(state["defender"]["cohesion"]),
	}
	## The line's three wings as the battle opened, as it was left, and the wings
	## the enemy broke (wiki: quick-battle § Wings and collapse).
	report.merge(QuickBattleWings.record(state, wings_open))
	return report


## Emplaced gun quality the defending court's techs unlock (wiki: siege-mechanics).
static func gun_type(context: Dictionary, defender: int) -> String:
	var tech: Dictionary = context.get("tech", {}) as Dictionary
	var unlocked: Dictionary = tech.get(defender, {}) as Dictionary
	return FortRules.emplaced_type(unlocked)


## Rounds in which the garrison left the wall to sortie.
static func sortie_count(rounds: Array[Dictionary]) -> int:
	var count: int = 0
	for round: Dictionary in rounds:
		for entry: Dictionary in round.get("actions", []) as Array:
			if bool(entry.get("sortie", false)):
				count += 1
	return count
