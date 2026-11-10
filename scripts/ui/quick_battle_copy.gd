class_name QuickBattleCopy
extends RefCounted
## Despatch copy for the Quick Battle plate: action lines, outcome stamps, and
## round numerals. Pure text — no Control nodes — so the overlay stays a thin
## presenter (REQ-P3-01, REQ-P2-03).


static func action_line(action: Dictionary, battle: Dictionary, names: Array) -> String:
	var owner: int = int(action.get("side", 0))
	var label: String = String(action.get("label", "Action"))
	var text: String = "%s — %s" % [faction(owner, names), label]
	# A despatch reports what the action did to the other side; the acting side's
	# own losses (an assault's price) follow so the round reads honestly.
	var attacking: bool = owner == int(battle.get("attacker", -1))
	var inflicted_key: String = "defender_lost" if attacking else "attacker_lost"
	var own_key: String = "attacker_lost" if attacking else "defender_lost"
	var inflicted: int = int(action.get(inflicted_key, 0))
	var own: int = int(action.get(own_key, 0))
	if inflicted > 0:
		text += " · %d lost" % inflicted
	if own > 0:
		text += " · %d of its own" % own
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


## Siege despatch: the fort the defenders hold, the protection its walls give,
## and — when the battery is silenced — the level it falls to. Empty in a field
## battle (wiki: siege-mechanics § Damage Reduction, quick-battle § Integration).
static func siege_line(battle: Dictionary) -> String:
	var level: int = int(battle.get("fort_level", 0))
	if level <= 0:
		return ""
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var text: String = FortRules.describe(level)
	text += " · walls spare %d%% of the defenders' losses" % int(
		round(FortRules.damage_reduction(level) * 100.0)
	)
	if bool(quick.get("fort_downgraded", false)):
		var after: int = int(quick.get("fort_after", maxi(0, level - 1)))
		text += " — battery silenced, the fort falls to %s" % (
			FortRules.level_name(after) if after > 0 else "open field"
		)
	return text


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
