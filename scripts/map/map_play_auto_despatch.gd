class_name MapPlayAutoDespatch
extends RefCounted
## Auto mode's land/sea despatch wording (wiki: auto-mode § Pacing; issue #725).
## Turns a planner pass's trace into log lines: one per resolved order, grouped
## by kind and place so a court that marches three armies says so in one line.
##
## `MapPlayAuto` keeps the lifecycle and pacing; this home owns the seat's
## despatch vocabulary for expedition, land, voyage and sea (REQ-P3-01).

const NO_ID: int = MapModel.NO_ID

## The seat's own phrasing for the order kinds the rival trace merges. The
## published `AiTurnLog` labels name a court's habit ("marches", "regiments
## raised"); the crown's log reads as despatches, so the verb comes first.
const SEAT_LABELS: Dictionary = {
	AiMilitaryPlanner.KIND_MARCH: "Marches",
	AiMilitaryPlanner.KIND_SPLIT: "Detaches a column",
	MapPlayArmyMusterAi.KIND_REINFORCE: "Raises a regiment",
	MapPlayArmyMusterAi.KIND_HOSPITAL: "Pitches a field hospital",
	MapPlayArmyMusterAi.KIND_RECALL: "Re-forms the Home Army",
	AiNavalPlanner.KIND_SORTIE: "Sorties",
	AiNavalPlanner.KIND_PURSUE: "Pursues",
	AiNavalPlanner.KIND_HOME: "Sails home",
	AiNavalPlanner.KIND_RAID: "Raids the coast",
	AiNavalPlanner.KIND_CONVOY: "Sails a convoy",
	AiInvasionPlanner.KIND_DOCK: "Docks the expedition",
	AiInvasionPlanner.KIND_EMBARK: "Boards an army",
	AiInvasionPlanner.KIND_SAIL: "Sails with the expedition",
	AiInvasionPlanner.KIND_CROSS: "Crosses the Passage",
	AiInvasionPlanner.KIND_BEACHHEAD: "Holds a beachhead",
	AiInvasionPlanner.KIND_LAND: "Lands an army",
}


## Turns the pass's trace into log lines: one per resolved order, grouped by
## kind and place so a court that marches three armies says so in one line.
static func describe(play: PlaySession, trace: Array) -> void:
	var order: Array[String] = []
	var counts: Dictionary = {}
	for raw: Variant in trace:
		if not (raw is Dictionary):
			continue
		var record: Dictionary = raw
		if int(record.get("faction", NO_ID)) != play.player_faction:
			continue
		var line: String = line_of(record)
		if line.is_empty():
			continue
		if counts.has(line):
			counts[line] = int(counts[line]) + 1
			continue
		counts[line] = 1
		order.append(line)
	for line: String in order:
		var count: int = int(counts[line])
		MapPlayAuto.note(play, line if count == 1 else "%s (%d)" % [line, count])


## One trace record as a despatch line. The place is the province an army stands
## in or the sea zone a squadron entered.
static func line_of(record: Dictionary) -> String:
	var kind: String = String(record.get("kind", ""))
	var label: String = String(
		SEAT_LABELS.get(kind, AiTurnLog.ACTION_LABELS.get(kind, kind))
	)
	var place: String = String(record.get("province_name", record.get("zone_name", "")))
	if label.is_empty():
		return ""
	if place.is_empty():
		return label
	return "%s — %s" % [label, place]
