class_name BattleSimDespatch
extends RefCounted
## Sandbox despatch copy: the full action log, aftermath lines the game plate
## prints, and the rules readout behind the wall. Pure text — no Control nodes —
## so [BattleSimScreen] stays a thin presenter (REQ-P3-01, REQ-P2-03).


## Every action's despatch plus the aftermath lines the game plate prints, in
## the same order — ground, the wings and the line, walls, the named dead, the
## chevrons, the honours and citations won, and the siege (REQ-P5-05).
static func full(report: Dictionary, names: Array, sandbox: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var rounds: Array = rounds_of(report)
	for round: Dictionary in rounds:
		lines.append("— ROUND %s —" % QuickBattleCopy.roman(int(round.get("round", 1))))
		for action: Dictionary in round.get("actions", []) as Array:
			lines.append(QuickBattleCopy.action_line(action, report, names))
	var tail: PackedStringArray = PackedStringArray()
	for text: String in [
		QuickBattleCopy.terrain_line(report),
		QuickBattleCopy.wings_line(report, names),
		QuickBattleCopy.line_line(report, names),
		QuickBattleCopy.loss_line(report, names),
		QuickBattleCopy.health_line(report, names),
		QuickBattleCopy.chevron_line(report, names),
		QuickBattleCopy.honour_line(report, sandbox, names),
		QuickBattleCopy.citation_line(report, sandbox, names),
		QuickBattleCopy.siege_line(report),
	]:
		if not text.is_empty():
			tail.append(text)
	if not tail.is_empty():
		lines.append("— AFTERMATH —")
		lines.append_array(tail)
	lines.append("— OUTCOME —")
	lines.append(QuickBattleCopy.outcome_text(
		int(report.get("outcome", 0)), report, sandbox, names
	))
	return "\n".join(lines)


## The levers the rail set, in the rules' own words — each side's chevrons and
## the battery's emplaced line (wiki: combat § Strength; siege-mechanics
## § Emplaced Artillery) — so a playtester reads back what the fight was given.
static func lever_text(spec: Dictionary) -> String:
	var guns: String = RegimentCatalog.display_name(
		FortRules.emplaced_type(spec.get("tech", {}) as Dictionary)
	)
	return "Setup — attacker medals %d · defender medals %d · %s in the battery" % [
		int(spec.get("attacker_medals", 0)), int(spec.get("defender_medals", 0)), guns,
	]


## The numbers behind the plate: what the ground, the wall and the gates do.
static func rules_text(report: Dictionary) -> String:
	var quick: Dictionary = report["quick"] as Dictionary
	var terrain: String = String(quick.get("terrain", "open"))
	var limits: Dictionary = quick.get("limits", {}) as Dictionary
	var text: String = "Deployment %d / %d a side · 3 CP a round\n" % [
		int(limits.get("attacker", ArmyModifiers.BASE_DEPLOYMENT)),
		int(limits.get("defender", ArmyModifiers.BASE_DEPLOYMENT)),
	]
	text += "Ground %s — volley ×%.2f, assault ×%.2f, entrench ×%.2f\n" % [
		SiegeLanes.terrain_label(terrain), SiegeLanes.terrain_scale("volley", terrain),
		SiegeLanes.terrain_scale("assault", terrain), SiegeLanes.entrench_scale(terrain),
	]
	var level: int = int(report.get("fort_level", 0))
	if level > 0:
		text += "Walls spare %d%% · %d guns\n" % [
			roundi(FortRules.damage_reduction(level) * 100.0), int(quick.get("guns_start", 0)),
		]
		text += "3 gates · one breaches every %d wall casualties\n" % SiegeLanes.breach_threshold(level)
		text += "Lanes: %d wall, %d behind\n" % [
			int((quick.get("lanes", {}) as Dictionary).get("wall", 0)),
			int((quick.get("lanes", {}) as Dictionary).get("behind", 0)),
		]
		text += "Gates breached: %d of 3" % int(quick.get("breaches", 0))
	return text


## Header for a resolved fight: names, fort, and ground.
static func header(report: Dictionary, names: Array) -> String:
	var quick: Dictionary = report["quick"] as Dictionary
	return "%s vs %s — %s · %s" % [
		names[0], names[1], FortRules.describe(int(report.get("fort_level", 0))),
		String(quick.get("terrain_label", "Open field")),
	]


## Round status line for the centre plaque.
static func status_for_round(report: Dictionary, index: int) -> String:
	var rounds: Array = rounds_of(report)
	if index < 0 or index >= rounds.size():
		return "No rounds were fought."
	var entry: Dictionary = rounds[index] as Dictionary
	var guns: int = int(entry.get("guns", 0))
	return "Round %s — %d attackers, %d defenders, %d gun%s, %d of 3 gates breached." % [
		QuickBattleCopy.roman(index + 1),
		int(entry.get("attacker_count", 0)), int(entry.get("defender_count", 0)),
		guns, "" if guns == 1 else "s", int(entry.get("gates", 0)),
	]


## The side the rail left with no men, named; empty when both sides field one.
static func empty_side(spec: Dictionary, names: Array) -> String:
	for index in names.size():
		var key: String = "attacker" if index == 0 else "defender"
		if (spec.get(key, []) as Array).is_empty():
			return String(names[index])
	return ""


static func rounds_of(report: Dictionary) -> Array:
	return (report.get("quick", {}) as Dictionary).get("rounds", []) as Array
