class_name QuickBattleCopy
extends RefCounted
## Despatch copy for the Quick Battle plate: action lines, outcome stamps, and
## round numerals. Pure text — no Control nodes — so the overlay stays a thin
## presenter (REQ-P3-01, REQ-P2-03).


static func action_line(action: Dictionary, battle: Dictionary, names: Array) -> String:
	var owner: int = int(action.get("side", 0))
	var label: String = String(action.get("label", "Action"))
	var text: String = "%s — %s" % [faction(owner, names), label]
	var lost: int = int(action.get("attacker_lost", 0))
	if String(action.get("action", "")) == "battery":
		lost = int(action.get("attacker_lost", 0))
	elif owner == int(battle.get("defender", -1)):
		lost = int(action.get("defender_lost", 0))
	if lost > 0:
		text += " · %d lost" % lost
	var guns: int = int(action.get("guns_destroyed", 0))
	if guns > 0:
		text += " · %d gun%s silenced" % [guns, "" if guns == 1 else "s"]
	return text


static func outcome_text(
	outcome: int, battle: Dictionary, province_name: String, names: Array
) -> String:
	var attacker: String = faction(int(battle.get("attacker", 0)), names)
	var defender: String = faction(int(battle.get("defender", 1)), names)
	match outcome:
		ArmyCombat.Outcome.ATTACKER_VICTORY:
			return "%s takes %s" % [attacker, province_name]
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE:
			return "%s holds the field — %s keeps %s" % [attacker, defender, province_name]
		ArmyCombat.Outcome.DEFENDER_VICTORY:
			return "%s holds %s" % [defender, province_name]
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION:
			return "Mutual ruin — both sides are broken"
		ArmyCombat.Outcome.CAPTURE:
			return "%s occupies %s unopposed" % [attacker, province_name]
	return "%s and %s stand off" % [attacker, defender]


static func player_won(outcome: int, battle: Dictionary) -> bool:
	var player: int = int(battle.get("player_faction", -1))
	var winner: int = -1
	if outcome in [
		ArmyCombat.Outcome.ATTACKER_VICTORY,
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
		ArmyCombat.Outcome.CAPTURE,
	]:
		winner = int(battle.get("attacker", -1))
	elif outcome == ArmyCombat.Outcome.DEFENDER_VICTORY:
		winner = int(battle.get("defender", -1))
	return player >= 0 and winner == player


static func faction(owner: int, names: Array) -> String:
	if owner < 0 or owner >= names.size():
		return "An unknown flag"
	return String(names[owner])


static func roman(value: int) -> String:
	var numerals: Array[String] = ["I", "II", "III", "IV", "V"]
	return numerals[clampi(value - 1, 0, numerals.size() - 1)]
