class_name NavalDispatch
extends RefCounted
## The sea's despatch: the plate's account of one resolved naval engagement,
## written from the resolver's own record (wiki: ships-and-naval § Naval Combat
## Resolution — the report). Pure string and count work, so the screen stays a
## view and no outcome is recomputed here (REQ-P2-03, REQ-P3-03).

const ATTACKER: String = "attacker"
const DEFENDER: String = "defender"


## The hull ids the side had in the water before the first shot, in the
## resolver's own order. Empty for a record written before types were carried.
static func hull_ids(battle: Dictionary, side: String) -> Array:
	return battle.get(side + "_hulls", []) as Array


## The side's hulls by type, biggest group first then by type id, so the plate
## can stand one medallion per type and print how many of each flew.
static func groups(battle: Dictionary, side: String) -> Array[Dictionary]:
	var counts: Dictionary = {}
	for raw: Variant in hull_ids(battle, side):
		var type_id: String = ShipStats.normalize(String(raw))
		counts[type_id] = int(counts.get(type_id, 0)) + 1
	var rows: Array[Dictionary] = []
	for raw: Variant in counts.keys():
		rows.append({"type": String(raw), "count": int(counts[raw])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["count"]) != int(b["count"]):
			return int(a["count"]) > int(b["count"])
		return String(a["type"]) < String(b["type"]))
	return rows


## "4 Galleon and 2 Sloop" / "1 Sloop" — the hulls a side flew, by type.
static func groups_text(battle: Dictionary, side: String) -> String:
	var rows: Array[Dictionary] = groups(battle, side)
	var parts: PackedStringArray = PackedStringArray()
	for row: Dictionary in rows:
		parts.append("%d %s" % [int(row["count"]), ShipStats.display_name(String(row["type"]))])
	return " and ".join(parts)


## The hull count before the battle: the record's own number, falling back to
## the types it carries for a hand-built report.
static func hull_count(battle: Dictionary, side: String) -> int:
	var stated: int = int(battle.get(side + "_before", -1))
	if stated >= 0:
		return stated
	return hull_ids(battle, side).size()


## The strength the resolver struck with, rounded for the plate.
static func strength(battle: Dictionary, side: String) -> int:
	return roundi(float(battle.get(side + "_strength", 0.0)))


## The attacker's share of the two strengths, as the percentage the plate prints
## (`share > 0.53` wins, `share < 0.47` loses; between them is a standoff).
static func share_percent(battle: Dictionary) -> int:
	var attacker: float = float(battle.get("attacker_strength", 0.0))
	var total: float = attacker + float(battle.get("defender_strength", 0.0))
	if total <= 0.0:
		return 50
	return roundi(attacker / total * 100.0)


## "Strength 182 against 121 — España's share 60 of 100" — the maths the plate
## prints before the outcome, so a standoff is never a mystery (REQ-P2-03).
static func maths_line(battle: Dictionary, names: Array) -> String:
	var attacker: String = name_of(names, int(battle.get("attacker", 0)))
	var defender: String = name_of(names, int(battle.get("defender", 0)))
	return "Strength %d against %d — %s's share %d of 100; %s needs better than 53 to break her." % [
		strength(battle, ATTACKER), strength(battle, DEFENDER),
		attacker, share_percent(battle), attacker
	]


## The opening beat: who closed on whom, with the hulls each flew.
static func opening(battle: Dictionary, zone: String, names: Array) -> String:
	var attacker: String = name_of(names, int(battle.get("attacker", 0)))
	var defender: String = name_of(names, int(battle.get("defender", 0)))
	var meeting: String = "in the %s" % zone if not zone.is_empty() else "at sea"
	var attacker_hulls: String = groups_text(battle, ATTACKER)
	var defender_hulls: String = groups_text(battle, DEFENDER)
	if attacker_hulls.is_empty() or defender_hulls.is_empty():
		return "%s's %d hulls meet %s's %d %s." % [
			attacker, hull_count(battle, ATTACKER), defender,
			hull_count(battle, DEFENDER), meeting
		]
	return "%s's %d hulls (%s) close on %s's %d (%s) %s." % [
		attacker, hull_count(battle, ATTACKER), attacker_hulls, defender,
		hull_count(battle, DEFENDER), defender_hulls, meeting
	]


## One line per side that lost hulls, names included (DR-20261111-07).
static func loss_lines(battle: Dictionary, names: Array) -> Array[String]:
	var lines: Array[String] = []
	for side: String in [ATTACKER, DEFENDER]:
		var lost: Array = battle.get(side + "_lost", []) as Array
		if lost.is_empty():
			continue
		var who: String = name_of(names, int(battle.get(side, 0)))
		lines.append("%s loses %s." % [who, _loss_phrase(battle, side)])
	return lines


## The closing beat: the retreat, the winner, or the standoff.
static func closing(battle: Dictionary, names: Array) -> String:
	var retreat: Dictionary = battle.get("retreat", {}) as Dictionary
	if bool(retreat.get("success", false)):
		var beaten: int = int(retreat.get("beaten", int(battle.get("defender", 0))))
		var haven: String = name_of(names, beaten)
		var holder: String = name_of(names, int(battle.get("defender", 0)))
		if beaten == int(battle.get("defender", 0)):
			holder = name_of(names, int(battle.get("attacker", 0)))
		return "%s slips into haven, and %s holds the zone." % [haven, holder]
	match int(battle.get("outcome", NavalCombat.Outcome.STALEMATE)):
		NavalCombat.Outcome.SIDE1_VICTORY:
			return "%s holds the zone." % name_of(names, int(battle.get("attacker", 0)))
		NavalCombat.Outcome.SIDE2_VICTORY:
			return "%s holds the zone." % name_of(names, int(battle.get("defender", 0)))
	return "Both colours wear off on the swell; neither holds the zone."


## The plate's beats in the order they are read: the meeting, the maths, the
## losses, then what the sea decided.
static func beats(battle: Dictionary, zone: String, names: Array) -> Array[String]:
	var lines: Array[String] = [opening(battle, zone, names), maths_line(battle, names)]
	lines.append_array(loss_lines(battle, names))
	lines.append(closing(battle, names))
	return lines


## The stamp under the despatch: who holds the water once the smoke clears.
static func outcome_text(battle: Dictionary, zone: String, names: Array) -> String:
	var water: String = "the zone" if zone.is_empty() else "the %s" % zone
	var retreat: Dictionary = battle.get("retreat", {}) as Dictionary
	if bool(retreat.get("success", false)):
		var beaten: int = int(retreat.get("beaten", int(battle.get("defender", 0))))
		var holder: int = int(battle.get("defender", 0))
		if beaten == holder:
			holder = int(battle.get("attacker", 0))
		return "%s withdraws — %s holds %s" % [
			name_of(names, beaten), name_of(names, holder), water
		]
	match int(battle.get("outcome", NavalCombat.Outcome.STALEMATE)):
		NavalCombat.Outcome.SIDE1_VICTORY:
			return "%s holds %s" % [name_of(names, int(battle.get("attacker", 0))), water]
		NavalCombat.Outcome.SIDE2_VICTORY:
			return "%s holds %s" % [name_of(names, int(battle.get("defender", 0))), water]
	return "Neither colour holds %s" % water


## The standfirst over the plate: the court that was there and the water.
static func headline(battle: Dictionary, zone: String, names: Array) -> String:
	var attacker: String = name_of(names, int(battle.get("attacker", 0)))
	var defender: String = name_of(names, int(battle.get("defender", 0)))
	if zone.is_empty():
		return "%s against %s" % [attacker, defender]
	return "%s against %s — the %s" % [attacker, defender, zone]


## A court's name, or a neutral label when the record names an unknown id.
static func name_of(names: Array, faction: int) -> String:
	if faction >= 0 and faction < names.size():
		return String(names[faction])
	return "A strange colour"


## "2 ships (Trinidad, Concepcion)", "1 ship", "no ships" — the hulls the side
## lost, with the names the report kept.
static func _loss_phrase(battle: Dictionary, side: String) -> String:
	var count: int = (battle.get(side + "_lost", []) as Array).size()
	if count <= 0:
		return "no ships"
	var head: String = "%d ship%s" % [count, "" if count == 1 else "s"]
	var names: Array = battle.get(side + "_lost_names", []) as Array
	if names.is_empty():
		return head
	var shown: PackedStringArray = PackedStringArray()
	for raw: Variant in names:
		if shown.size() >= 3:
			break
		shown.append(String(raw))
	return "%s (%s)" % [head, ", ".join(shown)]
