class_name AiDiplomacyTrace
extends RefCounted
## The diplomacy pass's turn-trace rows: every order a rival court put to
## another crown, counted under the panel's action key and printed as its one
## sentence (wiki: turn-trace-interpretation). Pure translation: the merged
## record and its event cap belong to AiTurnLog, so this module only reads the
## pass's own trace and names what happened (REQ-P3-01).

const NO_ID: int = MapModel.NO_ID


## Writes this turn's diplomacy orders into the merged record, one row and one
## event per accepted order. An order the rules refused never reached the court.
static func record(play: PlaySession, merged: Dictionary, factions: Dictionary) -> void:
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
		AiTurnLog.bump(factions[faction]["actions"], key(kind))
		var text: String = String(raw.get("message", ""))
		if text.is_empty():
			text = line(kind, faction, target)
		AiTurnLog.event(merged, factions[faction], faction, text)


## The panel's action key for one diplomacy order kind: war, peace, a treaty
## family row, or a trade family row.
static func key(kind: String) -> String:
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


## The one sentence an order prints when the pass handed no message of its own.
static func line(kind: String, faction: int, target: int) -> String:
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
