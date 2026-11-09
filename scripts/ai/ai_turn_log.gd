class_name AiTurnLog
extends RefCounted
## Merged per-turn AI trace for the full-AI observer (wiki:
## turn-trace-interpretation). Diplomacy, land, naval and economy adapters hand
## their traces in once per resolved turn; this module merges them into one
## record per crown, so the observatory panel and the headless exporter read the
## same shape. It never changes rules state beyond `play.ai_turns` / feeding.

const NO_ID: int = MapModel.NO_ID
## Action keys shown in the panel headline, in reading order.
const ACTION_ORDER: Array[String] = [
	"war", "peace", "treaty", "attack", "march", "sortie", "pursue",
	"work", "production", "recruit", "train", "split",
]
const ACTION_LABELS: Dictionary = {
	"war": "war declared",
	"peace": "peace",
	"treaty": "treaty",
	"attack": "assaults",
	"march": "marches",
	"sortie": "sorties",
	"pursue": "pursuits",
	"work": "work orders",
	"production": "production",
	"recruit": "workers",
	"train": "civilians",
	"split": "splits",
}


## Appends one merged turn record to `play.ai_turns` and returns it. Call right
## after the rival/economy pass, while the turn traces are still in hand.
static func record(
	play: PlaySession,
	army_trace: Array[Dictionary],
	fleet_trace: Array[Dictionary],
	economy_report: Dictionary
) -> Dictionary:
	var merged: Dictionary = {
		"turn": play.turn,
		"year": TurnTime.year_for_turn(play.turn),
		"factions": {},
		"events": [],
	}
	var factions: Dictionary = merged["factions"]
	for faction: int in FactionCatalog.great_power_ids():
		factions[faction] = {"actions": {}, "events": []}
	_record_diplomacy(play, merged, factions)
	_record_armies(merged, factions, army_trace)
	_record_fleets(merged, factions, fleet_trace)
	_record_economy(merged, factions, economy_report)
	play.ai_turns.append(merged)
	return merged


## Feeding coverage per crown from the resolved consumption pass; the next
## Combat phase reads `play.feeding` by faction (wiki: economy § Consumption).
static func apply_feeding(play: PlaySession, report: Dictionary) -> void:
	var per: Dictionary = report.get("factions", {})
	for raw: Variant in per.keys():
		var faction: int = int(raw)
		var resolved: Dictionary = (per[raw] as Dictionary).get("resolved", {})
		var consumption: Dictionary = resolved.get("consumption", {})
		var demand: int = int(consumption.get("army_demand", 0))
		if demand <= 0:
			play.feeding[faction] = 1.0
			continue
		play.feeding[faction] = clampf(
			float(int(consumption.get("army_fed", 0))) / float(demand), 0.0, 1.0
		)


## "war declared ×1 · marches ×2 · work orders ×3", or a quiet line.
static func headline(last: Dictionary) -> String:
	if last.is_empty():
		return "no resolved turn yet"
	var actions: Dictionary = last.get("actions", {})
	var parts: PackedStringArray = []
	for key: String in ACTION_ORDER:
		var count: int = int(actions.get(key, 0))
		if count > 0:
			parts.append("%s ×%d" % [String(ACTION_LABELS.get(key, key)), count])
	if parts.is_empty():
		return "held station, no orders"
	return " · ".join(parts)


# --- turn record -------------------------------------------------------------


static func _record_diplomacy(
	play: PlaySession, merged: Dictionary, factions: Dictionary
) -> void:
	for raw: Dictionary in play.ai_trace:
		var faction: int = int(raw.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		var action: Dictionary = raw.get("action", {}) as Dictionary
		if action.is_empty():
			continue
		var kind: String = String(action.get("kind", ""))
		var target: int = int(action.get("target", NO_ID))
		_bump(factions[faction]["actions"], _diplomacy_key(kind))
		var text: String = String(raw.get("message", ""))
		if text.is_empty():
			text = _diplomacy_line(kind, faction, target)
		_add_event(merged, factions[faction], faction, text)


static func _record_armies(
	merged: Dictionary, factions: Dictionary, trace: Array[Dictionary]
) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		var kind: String = String(raw.get("kind", ""))
		if kind == AiMilitaryPlanner.KIND_SPLIT:
			_bump(factions[faction]["actions"], "split")
			continue
		var key: String = "attack" if bool(raw.get("attacked", false)) else "march"
		_bump(factions[faction]["actions"], key)
		var place: String = String(raw.get("province_name", ""))
		if place.is_empty():
			continue
		var line: String = (
			"%s storms into %s." if key == "attack" else "%s marches into %s."
		) % [FactionCatalog.name_of(faction), place]
		_add_event(merged, factions[faction], faction, line)


static func _record_fleets(
	merged: Dictionary, factions: Dictionary, trace: Array[Dictionary]
) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		var kind: String = String(raw.get("kind", ""))
		_bump(factions[faction]["actions"], "sortie" if kind.ends_with("sortie") else "pursue")
		var zone: String = String(raw.get("zone_name", ""))
		if zone.is_empty():
			continue
		_add_event(
			merged,
			factions[faction],
			faction,
			"%s's squadron sails into the %s." % [FactionCatalog.name_of(faction), zone],
		)


static func _record_economy(
	merged: Dictionary, factions: Dictionary, report: Dictionary
) -> void:
	var per: Dictionary = report.get("factions", {})
	for raw: Variant in per.keys():
		var faction: int = int(raw)
		if not factions.has(faction):
			continue
		var details: Dictionary = per[raw]
		var bucket: Dictionary = factions[faction]
		var assignments: Array = (details.get("production", {}) as Dictionary).get(
			"assignments", []
		)
		var recruits: Array = details.get("recruits", [])
		var civilians: Dictionary = details.get("civilians", {})
		var orders: Array = civilians.get("orders", [])
		var training: Array = civilians.get("training", [])
		var who: String = FactionCatalog.name_of(faction)
		if not assignments.is_empty():
			_bump(bucket["actions"], "production")
			_add_event(merged, bucket, faction, "%s sets %d production runs." % [
				who, assignments.size(),
			])
		if not recruits.is_empty():
			_bump(bucket["actions"], "recruit", recruits.size())
			_add_event(merged, bucket, faction, "%s trains %d workers." % [
				who, recruits.size(),
			])
		if not orders.is_empty():
			_bump(bucket["actions"], "work", orders.size())
			_add_event(merged, bucket, faction, "%s's civilians take %d work orders." % [
				who, orders.size(),
			])
		if not training.is_empty():
			_bump(bucket["actions"], "train")
			_add_event(merged, bucket, faction, "%s musters a civilian." % who)


static func _add_event(
	merged: Dictionary, bucket: Dictionary, faction: int, text: String
) -> void:
	if text.is_empty():
		return
	var events: Array = bucket["events"]
	if events.size() >= 60:
		return
	events.append(text)
	var merged_events: Array = merged["events"]
	merged_events.append({"faction": faction, "text": text})


static func _bump(actions: Dictionary, key: String, amount: int = 1) -> void:
	if key.is_empty():
		return
	actions[key] = int(actions.get(key, 0)) + amount


static func _diplomacy_key(kind: String) -> String:
	if kind == AiDiplomacyPlanner.KIND_DECLARE_WAR:
		return "war"
	if kind == AiDiplomacyPlanner.KIND_OFFER_PEACE:
		return "peace"
	return "treaty"


static func _diplomacy_line(kind: String, faction: int, target: int) -> String:
	var who: String = FactionCatalog.name_of(faction)
	if target == NO_ID:
		return "%s adjusts its court." % who
	var them: String = FactionCatalog.name_of(target)
	if kind == AiDiplomacyPlanner.KIND_DECLARE_WAR:
		return "%s declares war on %s." % [who, them]
	if kind == AiDiplomacyPlanner.KIND_OFFER_PEACE:
		return "%s sues for peace with %s." % [who, them]
	return "%s proposes a treaty to %s." % [who, them]
