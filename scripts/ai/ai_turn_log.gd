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
	"war", "peace", "treaty", "trade", "attack", "march", "sortie", "pursue",
	"work", "production", "recruit", "reinforce", "hospital", "train", "split",
	"invade", "cargo",
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
	"work": "work orders",
	"production": "production",
	"recruit": "workers",
	"reinforce": "regiments raised",
	"hospital": "field hospitals",
	"train": "civilians",
	"split": "splits",
	"invade": "landings",
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
	_record_diplomacy(play, merged, factions)
	_record_armies(merged, factions, army_trace)
	_record_fleets(merged, factions, fleet_trace)
	_record_economy(merged, factions, economy_report)
	_record_invasion(merged, factions, invasion_trace)
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
		# An order the rules refused never reached the court: counting it as a
		# declaration (or inventing its sentence) would report a war that never
		# happened (wiki: turn-trace-interpretation).
		var result: Dictionary = raw.get("result", {}) as Dictionary
		if result.has("ok") and not bool(result.get("ok", false)):
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
		if kind == MapPlayArmyAi.KIND_REINFORCE:
			_bump(factions[faction]["actions"], "reinforce")
			var raised: String = RegimentCatalog.display_name(String(raw.get("type", "")))
			if not raised.is_empty():
				_add_event(
					merged,
					factions[faction],
					faction,
					"%s musters %s." % [FactionCatalog.name_of(faction), raised]
				)
			continue
		if kind == MapPlayArmyAi.KIND_HOSPITAL:
			_bump(factions[faction]["actions"], "hospital")
			var face: String = String(raw.get("province_name", ""))
			if not face.is_empty():
				_add_event(
					merged,
					factions[faction],
					faction,
					"%s's army pitches a field hospital train at %s."
					% [FactionCatalog.name_of(faction), face],
				)
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


## Overseas expeditions: the split, the boarding, the crossing and the landing
## read as one campaign, so the headline counts landings rather than each leg.
static func _record_invasion(
	merged: Dictionary, factions: Dictionary, trace: Array[Dictionary]
) -> void:
	for raw: Dictionary in trace:
		var faction: int = int(raw.get("faction", NO_ID))
		if not factions.has(faction):
			continue
		var kind: String = String(raw.get("kind", ""))
		if kind == AiInvasionPlanner.KIND_SPLIT:
			_bump(factions[faction]["actions"], "split")
			continue
		_bump(factions[faction]["actions"], "invade")
		var who: String = FactionCatalog.name_of(faction)
		match kind:
			AiInvasionPlanner.KIND_EMBARK:
				_add_event(merged, factions[faction], faction, "%s's expedition boards its squadron." % who)
			AiInvasionPlanner.KIND_CROSS:
				_add_event(merged, factions[faction], faction, "%s's expedition crosses the Passage." % who)
			AiInvasionPlanner.KIND_LAND:
				var place: String = String(raw.get("province_name", ""))
				if not place.is_empty():
					_add_event(
						merged, factions[faction], faction,
						"%s's army lands at %s." % [who, place],
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
		_record_cargo(merged, bucket, faction, details.get("cargo", {}))


## Cargo routes and a new hull from the yard: the colonies' left tonnage and the
## court's trade holds explain why a rival moves or builds merchant hulls
## (wiki: economy-planner § Cargo; DR-20261110-26).
static func _record_cargo(
	merged: Dictionary, bucket: Dictionary, faction: int, cargo: Dictionary
) -> void:
	var routes: Array = cargo.get("routes", [])
	var launch: Dictionary = cargo.get("launch", {})
	if routes.is_empty() and launch.is_empty():
		return
	var who: String = FactionCatalog.name_of(faction)
	if not routes.is_empty():
		_bump(bucket["actions"], "cargo", routes.size())
		_add_event(merged, bucket, faction, "%s routes %d merchant squadron%s home." % [
			who, routes.size(), "" if routes.size() == 1 else "s",
		])
	if not launch.is_empty():
		_bump(bucket["actions"], "cargo")
		_add_event(merged, bucket, faction, "%s lays down a %s for the cargo trade." % [
			who, ShipStats.display_name(String(launch.get("type_id", ""))),
		])


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
	if kind in AiDiplomacyOffers.KINDS:
		if kind == AiDiplomacyOffers.KIND_ALLIANCE or kind == AiDiplomacyOffers.KIND_OVERTURE:
			return "treaty"
		if kind == AiDiplomacyOffers.KIND_BREAK:
			return "treaty"
		return "trade"
	return "treaty"


static func _diplomacy_line(kind: String, faction: int, target: int) -> String:
	var who: String = FactionCatalog.name_of(faction)
	if target == NO_ID:
		return "%s adjusts its court." % who
	var them: String = FactionCatalog.name_of(target)
	match kind:
		AiDiplomacyPlanner.KIND_DECLARE_WAR:
			return "%s declares war on %s." % [who, them]
		AiDiplomacyPlanner.KIND_OFFER_PEACE:
			return "%s sues for peace with %s." % [who, them]
		AiDiplomacyOffers.KIND_AID:
			return "%s sends aid to %s." % [who, them]
		AiDiplomacyOffers.KIND_FTP:
			return "%s agrees a trade pact with %s." % [who, them]
		AiDiplomacyOffers.KIND_REVOKE_FTP:
			return "%s ends its trade pact with %s." % [who, them]
		AiDiplomacyOffers.KIND_BOYCOTT:
			return "%s boycotts %s." % [who, them]
		AiDiplomacyOffers.KIND_REVOKE_BOYCOTT:
			return "%s lifts its boycott of %s." % [who, them]
		AiDiplomacyOffers.KIND_SUBSIDY:
			return "%s subsidises %s." % [who, them]
		AiDiplomacyOffers.KIND_CANCEL_SUBSIDY:
			return "%s ends its subsidy to %s." % [who, them]
		AiDiplomacyOffers.KIND_BREAK:
			return "%s breaks its alliance with %s." % [who, them]
	return "%s proposes a treaty to %s." % [who, them]
