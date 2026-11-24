class_name QuickBattleCopy
extends RefCounted
## Despatch copy for the Quick Battle plate: action lines, the line and its
## reserve, losses and outcome stamps. The wall a siege is fought over lives in
## [QuickBattleSiegeCopy] and the decorations in [QuickBattleHonoursCopy], so the
## opening line, the aftermath and the honours are read apart. Pure text — no
## Control nodes — so the overlay stays a thin presenter (REQ-P3-01, REQ-P2-03).


static func action_line(action: Dictionary, battle: Dictionary, names: Array) -> String:
	var owner: int = int(action.get("side", 0))
	var label: String = String(action.get("label", "Action"))
	var text: String = "%s — %s" % [faction(owner, names), label]
	# A sally leaves the parapet: the wall no longer shelters the garrison for
	# the round, and the court is told before the price is (wiki: quick-battle
	# § Turn structure and actions — Sortie; siege-mechanics § Gates and Sortie).
	if bool(action.get("sortie", false)):
		text += " · the wall stands open"
	# A stance that costs the line its footing names the step it spends: a
	# manoeuvre over broken ground or under the press, a fall back that gives
	# ground (wiki: quick-battle § Turn structure and actions).
	var cohesion: int = int(action.get("cohesion_lost", 0))
	if cohesion > 0:
		var why: String = String(action.get("cohesion_why", ""))
		text += " · cohesion -%d%s" % [
			cohesion, "" if why.is_empty() else ", " + why
		]
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
	# The wing the blow fell on, why it fell heavier, and the wing it broke
	# (wiki: quick-battle § Wings and collapse).
	var wing: String = String(action.get("wing", ""))
	if not wing.is_empty():
		text += " · into the %s" % QuickBattleWings.label(wing)
		var flank: float = float(action.get("flank", 1.0))
		if flank >= QuickBattleWings.ENCIRCLED_SCALE:
			text += " · taken from three sides"
		elif flank > 1.0:
			text += " · its flank is turned"
	var broke: String = _broke_clause(action.get("wing_broken", []) as Array, false)
	if not broke.is_empty():
		text += " · %s" % broke
	var own_broke: String = _broke_clause(action.get("own_broken", []) as Array, true)
	if not own_broke.is_empty():
		text += " · %s" % own_broke
	if inflicted <= 0 and int(action.get("turned", 0)) > 0:
		text += " · the wall turns it aside"
	return text


## "the left breaks" / "the left and right break": a wing is named once, on the
## blow that emptied it, and on the line it stood in — the enemy's, or the
## actor's own (wiki: quick-battle § Wings and collapse).
static func _broke_clause(wings: Array, own: bool) -> String:
	if wings.is_empty():
		return ""
	var names: PackedStringArray = PackedStringArray()
	for wing: String in wings:
		names.append(QuickBattleWings.label(wing))
	return "%s%s %s" % [
		"its own " if own else "the ", _joined(names),
		"breaks" if names.size() == 1 else "break",
	]


## "a, b and c" — a list read as prose.
static func _joined(words: PackedStringArray) -> String:
	if words.is_empty():
		return ""
	if words.size() == 1:
		return words[0]
	return "%s and %s" % [
		", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]
	]


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


## The line's wings: how the horse and the foot were dealt across left, centre
## and right when the battle opened, what stands on them now, and the wings the
## enemy has broken (wiki: quick-battle § Wings and collapse). Empty when the
## record carries no wings — a garrison behind a wall, or an older plate.
static func wings_line(battle: Dictionary, names: Array) -> String:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var opened: Dictionary = quick.get("wings_open", {}) as Dictionary
	var now: Dictionary = quick.get("wings", {}) as Dictionary
	var broken: Dictionary = quick.get("wings_broken", {}) as Dictionary
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var held: Dictionary = opened.get(key, {}) as Dictionary
		if int(held.get("left", 0)) + int(held.get("center", 0)) \
			+ int(held.get("right", 0)) <= 0:
			continue
		var text: String = "%s: %s" % [
			faction(int(battle.get(key, -1)), names), QuickBattleWings.describe(held)
		]
		var standing: String = QuickBattleWings.describe(now.get(key, held) as Dictionary)
		if standing != QuickBattleWings.describe(held):
			text += " → %s" % standing
		var down: Array = broken.get(key, []) as Array
		if not down.is_empty():
			var lost: PackedStringArray = PackedStringArray()
			for wing: String in down:
				lost.append(QuickBattleWings.label(wing))
			text += " · %s broken" % _joined(lost)
		parts.append(text)
	if parts.is_empty():
		return ""
	return "Wings — " + " · ".join(parts)


## The deal alone, as the plate opens: how each side's horse, foot and guns were
## dealt across left, centre and right. No standing counts and no broken wings —
## the plate is drawn before the first round plays, so a strike-through here
## would hand the court the result (REQ-P5-05, REQ-P5-06). The wings as the
## fight left them are [method wings_line]'s.
static func wings_opening(battle: Dictionary, names: Array) -> String:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var opened: Dictionary = quick.get("wings_open", {}) as Dictionary
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var held: Dictionary = opened.get(key, {}) as Dictionary
		if int(held.get("left", 0)) + int(held.get("center", 0)) \
			+ int(held.get("right", 0)) <= 0:
			continue
		parts.append("%s: %s" % [
			faction(int(battle.get(key, -1)), names), QuickBattleWings.describe(held)
		])
	if parts.is_empty():
		return ""
	return "Wings — " + " · ".join(parts)


## The ground the battle is fought over and what it does to the action tables
## (wiki: quick-battle § Core actions). Empty on an old record with no terrain.
static func terrain_line(battle: Dictionary) -> String:
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var terrain: String = String(quick.get("terrain", ""))
	if terrain.is_empty() or terrain == "open":
		return ""
	var assault: int = round((1.0 - SiegeGround.terrain_scale("assault", terrain)) * 100.0)
	var volley: int = round((1.0 - SiegeGround.terrain_scale("volley", terrain)) * 100.0)
	return "Ground — %s: assaults −%d%%, volleys −%d%%" % [
		SiegeGround.terrain_label(terrain), assault, volley
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
			if battle.has("storm"):
				return "%s storms the walls of %s" % [attacker, province_name]
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
