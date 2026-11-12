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
	var mauled: int = int(action.get("mauled", 0))
	if mauled > 0:
		text += " · %d mauled" % mauled
	var guns: int = int(action.get("guns_destroyed", 0))
	if guns > 0:
		text += " · %d gun%s silenced" % [guns, "" if guns == 1 else "s"]
	elif int(action.get("battery_hit", 0)) > 0:
		text += " · the battery takes the blow"
	var behind: int = int(action.get("behind_lost", 0))
	if behind > 0:
		text += " · %d behind the wall" % behind
	var gates: int = int(action.get("gates_broken", 0))
	if gates > 0:
		text += " · %d gate%s breached" % [gates, "" if gates == 1 else "s"]
	if inflicted <= 0 and int(action.get("turned", 0)) > 0:
		text += " · the wall turns it aside"
	return text


## The stance line the plate prints: the player's own plan first (it is the one
## the player set, and on the defending side the report's `plan` belongs to the
## attacker), then the enemy's script and any emplaced battery.
static func plan_text(battle: Dictionary) -> String:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var mine: String = String(quick.get("plan", "balanced"))
	var theirs: String = String(quick.get("defender_plan", "defensive"))
	if int(battle.get("player_faction", -1)) == int(battle.get("defender", -1)):
		mine = String(quick.get("defender_plan", "defensive"))
		theirs = String(quick.get("plan", "balanced"))
	var text: String = "Your plan: %s · enemy: %s" % [mine.capitalize(), theirs.capitalize()]
	var guns: int = int(quick.get("guns_start", 0))
	if guns > 0:
		text += " · %d gun%s" % [guns, "" if guns == 1 else "s"]
	return text


## Siege despatch: the fort, the wall's protection, the lanes it shelters, and
## the level a silenced battery leaves behind. Empty in a field battle.
static func siege_line(battle: Dictionary) -> String:
	var level: int = int(battle.get("fort_level", 0))
	if level <= 0:
		return ""
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var lanes: Dictionary = quick.get("lanes", {}) as Dictionary
	var text: String = FortRules.describe(level)
	text += " · walls spare %d%% of the defenders' losses" % int(
		round(FortRules.damage_reduction(level) * 100.0)
	)
	text += " · %d on the wall, %d behind" % [
		int(lanes.get("wall", 0)), int(lanes.get("behind", 0))
	]
	if int(quick.get("sorties", 0)) > 0:
		text += " · %d sortie%s" % [
			int(quick.get("sorties", 0)), "" if int(quick.get("sorties", 0)) == 1 else "s"
		]
	text += gates_text(quick)
	if bool(quick.get("fort_downgraded", false)):
		var after: int = int(quick.get("fort_after", maxi(0, level - 1)))
		text += " — battery silenced, the fort falls to %s" % (
			FortRules.level_name(after) if after > 0 else "open field"
		)
	return text


## The three gates, and the ones the besiegers beat down. Empty for a field
## battle (no fort, no gates).
static func gates_text(quick: Dictionary) -> String:
	var gates: Dictionary = quick.get("gates", {}) as Dictionary
	var maximum: int = int(gates.get("max", 0))
	if maximum <= 0:
		return ""
	var broken: int = int(gates.get("broken", 0))
	if broken <= 0:
		return " · %d gates hold" % maximum
	return " · %d of %d gates breached" % [broken, maximum]


## The ground the battle is fought over and what it does to the action tables
## (wiki: quick-battle § Core actions). Empty on an old record with no terrain.
static func terrain_line(battle: Dictionary) -> String:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var terrain: String = String(quick.get("terrain", ""))
	if terrain.is_empty() or terrain == "open":
		return ""
	var assault: int = round((1.0 - SiegeLanes.terrain_scale("assault", terrain)) * 100.0)
	var volley: int = round((1.0 - SiegeLanes.terrain_scale("volley", terrain)) * 100.0)
	return "Ground — %s: assaults −%d%%, volleys −%d%%" % [
		SiegeLanes.terrain_label(terrain), assault, volley
	]


## The line and the reserve: how many regiments stood and how many were spared
## (wiki: combat § The line and the reserve; DR-20261111-15). Only sides that
## kept a reserve are named, so a full line adds no line.
static func line_line(battle: Dictionary, names: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var reserve: int = int(battle.get(key + "_reserve", 0))
		if reserve <= 0:
			continue
		var deployed: int = int(battle.get(key + "_deployed", 0))
		parts.append("%s: %d of %d in the line" % [
			faction(int(battle.get(key, -1)), names), deployed, deployed + reserve
		])
	if parts.is_empty():
		return ""
	return "Line — " + " · ".join(parts)


## Regiment detail after the battle: which types each side lost. Empty when the
## field was quiet.
static func loss_line(battle: Dictionary, names: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var tally: Dictionary = battle.get(key + "_detail", {}) as Dictionary
		var text: String = RegimentCatalog.detail_text(tally)
		if text.is_empty():
			continue
		parts.append("%s: %s" % [faction(int(battle.get(key, -1)), names), text])
	if parts.is_empty():
		return ""
	return "Losses — " + " · ".join(parts)


## Aftermath condition: the worst-hit survivors each side still has, by type and
## health. Empty when both lines are unbroken.
static func health_line(battle: Dictionary, names: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var entries: Array = _wounded(battle, key)
		if entries.is_empty():
			continue
		var listed: PackedStringArray = PackedStringArray()
		for entry: Dictionary in entries:
			## A survivor is named by the title it wears; a regiment saved
			## before names existed still prints its type (DR-20261111-18).
			var label: String = String(entry.get("name", ""))
			if label.is_empty():
				label = RegimentCatalog.display_name(String(entry.get("type", "")))
			listed.append("%s %d%%" % [
				label,
				roundi(float(entry.get("fraction", 1.0)) * 100.0),
			])
		parts.append("%s: %s" % [
			faction(int(battle.get(key, -1)), names), ", ".join(listed)
		])
	if parts.is_empty():
		return ""
	return "Mauled — " + " · ".join(parts)


## Chevrons the winning survivors won, side by side. Empty when nobody rose.
static func chevron_line(battle: Dictionary, names: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var gained: int = int(battle.get(key + "_chevrons", 0))
		if gained <= 0:
			continue
		parts.append("%s: %d regiment%s rise a chevron" % [
			faction(int(battle.get(key, -1)), names), gained, "" if gained == 1 else "s"
		])
	if parts.is_empty():
		return ""
	return "Chevrons — " + " · ".join(parts)


## The field's name added to a winning side's colours once (DR-20261112-02).
## Empty when no colour was bare enough to take it, so a repeat win adds no line.
static func honour_line(battle: Dictionary, province_name: String, names: Array) -> String:
	if province_name.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var gained: int = int(battle.get(key + "_honours", 0))
		if gained <= 0:
			continue
		parts.append("%s: %s added to %d colour%s" % [
			faction(int(battle.get(key, -1)), names), province_name,
			gained, "" if gained == 1 else "s",
		])
	if parts.is_empty():
		return ""
	return "Honours — " + " · ".join(parts)


## The colours the crown cited for a field won while mauled (DR-20261112-10).
## Empty when no colour bled enough to be named, so a clean win adds no line.
static func citation_line(battle: Dictionary, province_name: String, names: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var cited: int = int(battle.get(key + "_citations", 0))
		if cited <= 0:
			continue
		parts.append("%s: %d colour%s cited at %s" % [
			faction(int(battle.get(key, -1)), names), cited,
			"" if cited == 1 else "s", province_name,
		])
	if parts.is_empty():
		return ""
	return "Citations — " + " · ".join(parts)


## Up to three survivors under full strength, worst first.
static func _wounded(battle: Dictionary, key: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var raw_entries: Array = battle.get(key + "_health", []) as Array
	for raw: Variant in raw_entries:
		var entry: Dictionary = raw as Dictionary
		if float(entry.get("fraction", 1.0)) >= 0.999:
			continue
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["fraction"]), float(b["fraction"])):
			return float(a["fraction"]) < float(b["fraction"])
		return String(a.get("id", "")) < String(b.get("id", ""))
	)
	if entries.size() > 3:
		entries.resize(3)
	return entries


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
