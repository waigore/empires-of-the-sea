class_name AiTurnLog
extends RefCounted
## Merged per-turn AI trace for the full-AI observer (wiki:
## turn-trace-interpretation). Diplomacy, land, naval and economy adapters hand
## their traces in once per resolved turn; this module merges them into one
## record per crown, so the observatory panel and the headless exporter read the
## same shape. Each pass that hands in a report owns its rows (AiDiplomacyTrace,
## AiEconomyTrace); this module owns the record, its event cap and the headline.
## It never changes rules state beyond `play.ai_turns` / feeding.

const NO_ID: int = MapModel.NO_ID
## Action keys shown in the panel headline, in reading order.
const ACTION_ORDER: Array[String] = [
	"war", "peace", "treaty", "trade", "attack", "march", "sortie", "pursue", "home",
	"work", "production", "recruit", "reinforce", "hospital", "train", "split",
	"invade", "voyage", "colony", "build", "cargo",
]
const ACTION_LABELS: Dictionary = {
	"war": "war declared",
	"peace": "peace",
	"treaty": "treaty",
	"trade": "trade terms",
	"attack": "assaults",
	"march": "marches",
	"sortie": "sorties",
	"pursue": "pursuits",
	"home": "sailings home",
	"work": "work orders",
	"production": "production",
	"recruit": "workers",
	"reinforce": "regiments raised",
	"hospital": "field hospitals",
	"train": "civilians",
	"split": "splits",
	"invade": "landings",
	"voyage": "voyage orders",
	"colony": "colony landings",
	"build": "hulls laid down",
	"cargo": "cargo routes",
}


## Appends one merged turn record to `play.ai_turns` and returns it. Call right
## after the rival/economy pass, while the turn traces are still in hand.
static func record(
	play: PlaySession,
	army_trace: Array[Dictionary],
	fleet_trace: Array[Dictionary],
	economy_report: Dictionary,
	invasion_trace: Array[Dictionary] = [],
	colonisation_trace: Array[Dictionary] = [],
	objectives: Dictionary = {}
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
	AiDiplomacyTrace.record(play, merged, factions)
	_record_armies(merged, factions, army_trace)
	_record_fleets(merged, factions, fleet_trace)
	AiEconomyTrace.record(merged, factions, economy_report)
	_record_expeditions(merged, factions, invasion_trace, colonisation_trace)
	_record_objectives(factions, _ledgers(play, objectives))
	play.ai_turns.append(merged)
	return merged


## The turn's ledger: the caller's if one was handed in, else the pass read here
## at turn close. T1's ledger changes no order, so reading it where the trace is
## written is enough; T2 moves the read before the expedition pass, where its
## claims are consulted (issue #491).
static func _ledgers(play: PlaySession, handed_in: Dictionary) -> Dictionary:
	if not handed_in.is_empty():
		return handed_in
	if play == null or play.world == null or play.diplomacy == null:
		return {}
	return MapPlayObjectivesAi.run(play)


## The objective ledger's reading of one court: its footing, its money goal and
## every ranked aim with its utility, cost, claim and deferred/blocked reason
## (docs/ai.md; issue #491 T1). T1 records the ledger without changing an order.
static func _record_objectives(factions: Dictionary, ledgers: Dictionary) -> void:
	for raw: Variant in ledgers.keys():
		var faction: int = int(raw)
		if not factions.has(faction):
			continue
		var ledger: Dictionary = ledgers[raw]
		var bucket: Dictionary = factions[faction]
		bucket["phase"] = String(ledger.get("phase", ""))
		bucket["goal"] = String(ledger.get("goal", ""))
		# The court's distance to the bar and the margin it presses at
		# (DR-20261114-04): the trace explains an endgame court's thinner storm.
		bucket["pressure"] = (ledger.get("pressure", {}) as Dictionary).duplicate(true)
		bucket["objectives"] = {
			"ranked": int(ledger.get("ranked", 0)),
			"funded": int(ledger.get("funded", 0)),
			"blocked": int(ledger.get("blocked", 0)),
			"rows": (ledger.get("objectives", []) as Array).duplicate(true),
			"lines": (ledger.get("lines", []) as Array).duplicate(),
		}


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


static func _record_armies(
	merged: Dictionary, factions: Dictionary, trace: Array[Dictionary]
) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		var kind: String = String(raw.get("kind", ""))
		if kind == AiMilitaryPlanner.KIND_SPLIT:
			bump(factions[faction]["actions"], "split")
			continue
		if kind == MapPlayArmyMusterAi.KIND_REINFORCE:
			bump(factions[faction]["actions"], "reinforce")
			var raised: String = RegimentCatalog.display_name(String(raw.get("type", "")))
			if not raised.is_empty():
				event(
					merged,
					factions[faction],
					faction,
					"%s musters %s." % [FactionCatalog.name_of(faction), raised]
				)
			continue
		if kind == MapPlayArmyMusterAi.KIND_HOSPITAL:
			bump(factions[faction]["actions"], "hospital")
			var face: String = String(raw.get("province_name", ""))
			if not face.is_empty():
				event(
					merged,
					factions[faction],
					faction,
					"%s's army pitches a field hospital train at %s."
					% [FactionCatalog.name_of(faction), face],
				)
			continue
		var key: String = "attack" if bool(raw.get("attacked", false)) else "march"
		bump(factions[faction]["actions"], key)
		var place: String = String(raw.get("province_name", ""))
		if place.is_empty():
			continue
		var line: String = (
			"%s storms into %s." if key == "attack" else "%s marches into %s."
		) % [FactionCatalog.name_of(faction), place]
		event(merged, factions[faction], faction, line)


static func _record_fleets(
	merged: Dictionary, factions: Dictionary, trace: Array[Dictionary]
) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		var kind: String = String(raw.get("kind", ""))
		var key: String = "home" if kind == AiNavalPlanner.KIND_HOME else (
			"sortie" if kind.ends_with("sortie") else "pursue"
		)
		bump(factions[faction]["actions"], key)
		var zone: String = String(raw.get("zone_name", ""))
		if zone.is_empty():
			continue
		if String(raw.get("reason", "")) == AiNavalPlanner.REASON_TRADE:
			var trade: String = "%s's squadron gives up its station to keep its holds home."
			event(merged, factions[faction], faction, trade % FactionCatalog.name_of(faction))
			continue
		event(
			merged,
			factions[faction],
			faction,
			"%s's squadron sails into the %s." % [FactionCatalog.name_of(faction), zone],
		)


## Overseas expeditions: the invasion and colonisation passes hand their traces
## to `AiExpeditionLog`, which prices each leg as an action row (the split, the
## landing, the voyage step and the colony landing); this pass counts and prints
## them. Colonisation rows keep a voyage in the trace even when no army is aboard
## (issue #476).
static func _record_expeditions(
	merged: Dictionary,
	factions: Dictionary,
	invasion_trace: Array[Dictionary],
	colonisation_trace: Array[Dictionary]
) -> void:
	for row: Dictionary in AiExpeditionLog.rows(invasion_trace, colonisation_trace):
		var faction: int = int(row.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		bump(factions[faction]["actions"], String(row.get("action", "")))
		event(merged, factions[faction], faction, String(row.get("event", "")))


## One event row on the merged record and its crown, capped so a long turn
## cannot flood the observatory panel. Every recorder shares this cap, so no pass
## can print more than its peers.
static func event(
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


## One action count under the panel's headline key.
static func bump(actions: Dictionary, key: String, amount: int = 1) -> void:
	if key.is_empty():
		return
	actions[key] = int(actions.get(key, 0)) + amount

