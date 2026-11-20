class_name DeedBar
extends RefCounted
## The words a deed's bar reads: the refused march that names its holders, and
## the province sheet's Deeds row. One home for both, because the crown reads the
## same holdings before the order and after it (wiki: factions § Tribe — "unless
## another GP has invested in the province"; diplomacy § GP–Minor Rules
## § Intervention; REQ-P2-03, REQ-P5-03).
##
## The cause is [InvasionBar.read]'s reading and the counts are
## [DeedProtection.province_holders]', so no sentence here can name a holding the
## rules would not count.

## The refusal line for a march the bar refuses. `fallback` is the order's own
## reason, kept for every cause but a deed (own land, a peace, a stale order), so
## the crown still reads the rules' words when nothing was bought.
static func refusal(
	bar: Dictionary, model: MapModel, province_id: int, fallback: String
) -> String:
	var deeds: Dictionary = bar.get("deeds", {}) as Dictionary
	if String(bar.get("cause", "")) != InvasionBar.DEED:
		return fallback
	if deeds.is_empty() or model == null:
		return fallback
	return "Deeds in %s bar an undeclared march — %s %s bought land there; declare war before invading." % [
		model.province_name(province_id), held_by(deeds), _verb(deeds),
	]


## The courts that bought land here, by name: "England", "England and Portugal".
static func held_by(deeds: Dictionary) -> String:
	var names: Array[String] = []
	for raw: Variant in deeds.keys():
		names.append(FactionCatalog.name_of(int(raw)))
	if names.is_empty():
		return ""
	return _join_names(names)


## The province sheet's Deeds row: "England 2 tiles · Portugal 1 tile", or "" for
## a province no crown has bought land in — the row hides rather than printing an
## absence.
static func holders(deeds: Dictionary) -> String:
	var parts: PackedStringArray = []
	for raw: Variant in deeds.keys():
		var tiles: int = int(deeds[raw])
		parts.append(
			"%s %d tile%s" % [
				FactionCatalog.name_of(int(raw)), tiles, "" if tiles == 1 else "s",
			]
		)
	return " · ".join(parts)


static func _verb(deeds: Dictionary) -> String:
	return "has" if deeds.size() == 1 else "have"


## "A", "A and B", "A, B and C" — Oxford-free list for the refusal line.
static func _join_names(names: Array[String]) -> String:
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	var head: String = ""
	for index in names.size() - 1:
		head += ("" if index == 0 else ", ") + names[index]
	return "%s and %s" % [head, names[names.size() - 1]]