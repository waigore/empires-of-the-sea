class_name MainlineAiExpeditionLog
extends RefCounted
## Trace rows for a court's overseas expeditions (wiki: turn-trace-interpretation;
## issue #476).
##
## The invasion and colonisation passes both move an army or a colonist across a
## Passage, and both used to reach the merged turn trace through their own
## recorder inside `MainlineAiTurnLog`. This module owns the reading of those traces: the
## adapters' entries in, one plain row per action out (`{faction, action, event}`),
## so `MainlineAiTurnLog` only counts and prints what it is handed.
##
## Invasion: the split is its own action, and the boarding, crossing and landing
## legs read as one campaign, so the headline counts landings rather than each
## leg (the published behaviour). Colonisation: every applied voyage step is a
## voyage order, and the landing is also a colony landing, so an expedition is
## visible even when no army is aboard.
##
## Pure: no session state is read, and the same traces always make the same rows.


## Rows for one turn, invasion trace first (the order the trace was written in).
static func rows(
	invasion_trace: Array[Dictionary], colonisation_trace: Array[Dictionary]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_append_invasion(out, invasion_trace)
	_append_colonisation(out, colonisation_trace)
	return out


static func _append_invasion(out: Array[Dictionary], trace: Array[Dictionary]) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", MapModel.NO_ID))
		var kind: String = String(raw.get("kind", ""))
		if kind == MainlineAiInvasionPlanner.KIND_SPLIT:
			out.append({"faction": faction, "action": "split"})
			continue
		out.append({
			"faction": faction, "action": "invade", "event": _invasion_event(raw, kind),
		})


## The kinds here are the plain strings `MapPlayColonisationAi._apply` writes.
static func _append_colonisation(out: Array[Dictionary], trace: Array[Dictionary]) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", MapModel.NO_ID))
		var kind: String = String(raw.get("kind", ""))
		var place: String = String(raw.get("province_name", ""))
		var who: String = FactionCatalog.name_of(faction)
		var event: String = ""
		if kind == "embark" and not place.is_empty():
			event = "%s's Explorer boards at %s." % [who, place]
		elif kind == "cross":
			event = "%s's voyage crosses the Passage." % who
		elif kind == "land" and not place.is_empty():
			event = "%s's Explorer lands at %s." % [who, place]
		out.append({"faction": faction, "action": "voyage", "event": event})
		if kind == "land":
			out.append({"faction": faction, "action": "colony"})


static func _invasion_event(raw: Dictionary, kind: String) -> String:
	var faction: int = int(raw.get("faction", MapModel.NO_ID))
	var who: String = FactionCatalog.name_of(faction)
	match kind:
		MainlineAiInvasionPlanner.KIND_EMBARK:
			return "%s's expedition boards its squadron." % who
		MainlineAiInvasionPlanner.KIND_CROSS:
			return "%s's expedition crosses the Passage." % who
		MainlineAiInvasionPlanner.KIND_LAND:
			var place: String = String(raw.get("province_name", ""))
			if not place.is_empty():
				return "%s's army lands at %s." % [who, place]
	return ""