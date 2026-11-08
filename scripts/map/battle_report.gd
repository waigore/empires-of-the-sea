class_name BattleReport
extends RefCounted
## Formats a NavalCombat record as the one-line despatch the HUD toasts. Pure
## string work, so the screen stays a controller and the wording is unit-tested
## (REQ-P3-03).


static func describe(battle: Dictionary, zone_name: String, faction_names: Array) -> String:
	var attacker: String = _faction(faction_names, int(battle.get("attacker", 0)))
	var defender: String = _faction(faction_names, int(battle.get("defender", 0)))
	var outcome: int = int(battle.get("outcome", NavalCombat.Outcome.STALEMATE))
	match outcome:
		NavalCombat.Outcome.SIDE1_VICTORY:
			var sunk: int = (battle.get("defender_lost", []) as Array).size()
			return "%s holds the %s — %s loses %d ships" % [attacker, zone_name, defender, sunk]
		NavalCombat.Outcome.SIDE2_VICTORY:
			var lost: int = (battle.get("attacker_lost", []) as Array).size()
			return "%s repels %s in the %s — %d ships lost" % [defender, attacker, zone_name, lost]
	return "%s and %s trade broadsides in the %s and withdraw" % [attacker, defender, zone_name]


static func _faction(faction_names: Array, owner: int) -> String:
	if owner < 0 or owner >= faction_names.size():
		return "An unknown flag"
	return String(faction_names[owner])
