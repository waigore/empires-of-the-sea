class_name QuickBattleSiegeCopy
extends RefCounted
## The wall a siege Quick Battle is fought over, as the plate and the despatch
## read it (wiki: siege-mechanics § Quick Battle lanes, § Gates and Sortie).
## Pure text — no Control nodes — so the plate stays a thin presenter and the
## opening line and the aftermath can be read apart (REQ-P2-03, REQ-P3-01).
##
## The two readings are kept apart on purpose: the plate is populated before the
## first round plays, so it reads the wall as the siege found it, while the
## aftermath reads what the siege did to it (REQ-P5-05, REQ-P5-06).


## The wall as it stood when the plate opened: the fort, the protection it gives
## and the lanes it shelters. No gate state, no sortie count and no outcome —
## the fight has not been watched yet. What the siege did to the wall is
## [method siege_line]'s.
static func siege_wall(battle: Dictionary) -> String:
	var level: int = int(battle.get("fort_level", 0))
	if level <= 0:
		return ""
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var lanes: Dictionary = quick.get("lanes", {}) as Dictionary
	var text: String = FortRules.describe(level)
	text += " · walls spare %d%% of the defenders' losses" % int(
		round(FortRules.damage_reduction(level) * 100.0)
	)
	return text + " · %d on the wall, %d behind" % [
		int(lanes.get("wall", 0)), int(lanes.get("behind", 0))
	]


## The wall the plate opens with: the terms above and the three gates still
## standing as the siege found them. A record written before the opening gate
## state was kept carries only the gates as the siege left them, and reads as it
## stands (REQ-P2-03).
static func siege_opening(battle: Dictionary) -> String:
	var wall: String = siege_wall(battle)
	if wall.is_empty():
		return ""
	return wall + gates_line(opening_gates(battle.get("quick", {}) as Dictionary))


## Siege despatch at the close: the wall as it opened, the gates the siege beat
## down and the sorties the garrison made, then the level a silenced battery
## leaves behind. Empty in a field battle.
static func siege_line(battle: Dictionary) -> String:
	var wall: String = siege_wall(battle)
	if wall.is_empty():
		return ""
	var quick: Dictionary = battle.get("quick", {}) as Dictionary
	var text: String = wall + gates_text(quick)
	var sorties: int = int(quick.get("sorties", 0))
	if sorties > 0:
		text += " · %d sortie%s" % [sorties, "" if sorties == 1 else "s"]
	if bool(quick.get("fort_downgraded", false)):
		var after: int = int(quick.get("fort_after", maxi(0, int(battle.get("fort_level", 0)) - 1)))
		text += " — battery silenced, the fort falls to %s" % (
			FortRules.level_name(after) if after > 0 else "open field"
		)
	return text


## The gate state the plate was handed when it opened: nothing breached, every
## gate standing. A record that kept no opening state reads its final gates.
static func opening_gates(quick: Dictionary) -> Dictionary:
	var opened: Variant = quick.get("gates_open", null)
	if typeof(opened) == TYPE_DICTIONARY:
		return opened as Dictionary
	return quick.get("gates", {}) as Dictionary


## The three gates, and the ones the besiegers beat down. Empty for a field
## battle (no fort, no gates).
static func gates_text(quick: Dictionary) -> String:
	return gates_line(quick.get("gates", {}) as Dictionary)


## The same sentence for any gate state: the one the plate opened on, or the one
## the siege left.
static func gates_line(gates: Dictionary) -> String:
	var maximum: int = int(gates.get("max", 0))
	if maximum <= 0:
		return ""
	var broken: int = int(gates.get("broken", 0))
	if broken <= 0:
		return " · %d gates hold" % maximum
	return " · %d of %d gates breached" % [broken, maximum]
