class_name QuickBattleHonoursCopy
extends RefCounted
## Aftermath copy for the decorations a Quick Battle left behind: the field's
## name added to a winning side's colours, and the citations a mauled win earns.
## Split from [QuickBattleCopy] so the despatch, the honours and the siege each
## own their lines (REQ-P3-01). Pure text — no Control nodes — and no rule is
## decided here (REQ-P2-03).


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
			QuickBattleCopy.faction(int(battle.get(key, -1)), names), province_name,
			gained, "" if gained == 1 else "s",
		])
	if parts.is_empty():
		return ""
	return "Honours — " + " · ".join(parts)


## The colours the crown cited for a field won while mauled, and the weight the
## citation buys (DR-20261112-10, DR-20261113-04). Empty when no colour bled
## enough to be named, so a clean win adds no line.
static func citation_line(battle: Dictionary, province_name: String, names: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in ["attacker", "defender"]:
		var cited: int = int(battle.get(key + "_citations", 0))
		if cited <= 0:
			continue
		parts.append("%s: %d colour%s cited at %s" % [
			QuickBattleCopy.faction(int(battle.get(key, -1)), names), cited,
			"" if cited == 1 else "s", province_name,
		])
	if parts.is_empty():
		return ""
	var percent: int = roundi(RegimentDecorations.CITED_STEP * 100.0)
	return "Citations — %s (+%d%% each)" % [" · ".join(parts), percent]
