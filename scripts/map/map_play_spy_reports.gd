class_name MapPlaySpyReports
extends RefCounted
## Court despatches from the spy network: last-turn acts, battles and studies
## the human crown's spies could see (wiki: civilian-units § Spy). Resolve and
## kill notices stay on MapPlaySpies; this only builds the page, toasts it, and
## writes the chronicle notes the dossier weighs later (REQ-P3-01, REQ-P3-02).


## Lines a court's despatch keeps: a page, not a chronicle.
const MAX_LINES: int = 8


## Last-turn court reports for each observed rival: diplomatic acts, battles,
## provinces taken or lost and technologies completed. One toast per court, and
## the same lines stay in `play.court_reports` so the court panel can show the
## despatch again after the toast has gone (wiki: civilian-units § Spy).
static func report(
	play: PlaySession,
	land_battles: Array,
	naval_battles: Array,
	economy_report: Dictionary
) -> void:
	if play == null or play.hud == null:
		return
	var qualifying: Array[int] = MapPlaySpyAi.qualifying_rivals(play, play.player_faction)
	if qualifying.is_empty():
		return
	var kept: Dictionary = {}
	for rival: int in qualifying:
		# What only the spy could see is written to the chronicle before the
		# despatch is built, so the dossier weighs it the moment the court opens
		# (DR-20261110-25).
		_record_studies(play, rival, economy_report)
		_record_builds(play, rival, economy_report)
		var lines: Array[String] = _diplomacy_lines(play, rival)
		lines.append_array(_battle_lines(play, rival, land_battles, naval_battles))
		lines.append_array(_research_lines(rival, economy_report))
		if lines.size() > MAX_LINES:
			lines.resize(MAX_LINES)
		if lines.is_empty():
			continue
		kept[rival] = lines
		play.hud.toast(
			"Spy report — %s: %s"
			% [FactionCatalog.name_of(rival), " · ".join(lines)]
		)
	# The despatch reports the turn that just resolved; the calendar has already
	# advanced by the time this runs.
	play.court_reports = {
		"turn": maxi(play.turn - 1, 1),
		"shadowed": qualifying,
		"lines": kept,
	}
	# A panel already open shows the despatch without waiting for another turn.
	if play.hud.panels != null:
		MapPlayDiplomacy.refresh(play)


# --- internals ---------------------------------------------------------------


## The court's own acts this turn, as its spy's despatch tells them: reworded
## from what the rules resolved with masked names, so a stranger court never
## leaks through the trace's sentence (wiki: civilian-units § Spy (5)).
static func _diplomacy_lines(play: PlaySession, rival: int) -> Array[String]:
	var lines: Array[String] = []
	for record: Dictionary in play.ai_trace:
		if int(record.get("faction", -1)) != rival:
			continue
		var line: String = _act_line(play, rival, record)
		if line.is_empty():
			line = String(record.get("message", ""))
		if not line.is_empty():
			lines.append(line)
	return lines


## A resolved act's line by the kind the planner emits; war and peace answer for
## themselves below. A kind no row names keeps the court's own wording.
const ACT_LINES: Dictionary = {
	AiDiplomacyOffers.KIND_ALLIANCE: "%s proposes a formal alliance to %s.",
	AiDiplomacyOffers.KIND_OVERTURE: "%s sends an envoy to %s.",
	AiDiplomacyOffers.KIND_FTP: "%s proposes a favoured trading pact to %s.",
	AiDiplomacyOffers.KIND_REVOKE_FTP: "%s ends its trade pact with %s.",
	AiDiplomacyOffers.KIND_BOYCOTT: "%s closes its colonies to %s.",
	AiDiplomacyOffers.KIND_REVOKE_BOYCOTT: "%s reopens its colonies to %s.",
	AiDiplomacyOffers.KIND_AID: "%s sends aid to %s.",
	AiDiplomacyOffers.KIND_SUBSIDY: "%s sets a subsidy for %s.",
	AiDiplomacyOffers.KIND_CANCEL_SUBSIDY: "%s ends its subsidy to %s.",
	AiDiplomacyOffers.KIND_BREAK: "%s breaks its alliance with %s.",
}


static func _act_line(play: PlaySession, rival: int, record: Dictionary) -> String:
	var action: Dictionary = record.get("action", {}) as Dictionary
	if action.is_empty():
		return ""
	# An order the rules refused never reached the court: no war, no proposal.
	var result: Dictionary = record.get("result", {}) as Dictionary
	if result.has("ok") and not bool(result.get("ok", false)):
		return ""
	var target: int = int(action.get("target", MapModel.NO_ID))
	if target == MapModel.NO_ID:
		return ""
	var kind: String = String(action.get("kind", ""))
	var who: String = FactionCatalog.name_of(rival)
	var them: String = _name(play, target)
	match kind:
		AiDiplomacyPlanner.KIND_DECLARE_WAR:
			return "%s declares war on %s." % [who, them]
		AiDiplomacyPlanner.KIND_OFFER_PEACE:
			if bool(action.get("propose", false)):
				return "%s offers a white peace to %s." % [who, them]
			if result.has("accepted") and not bool(result.get("accepted", true)):
				return "%s sues for peace with %s and is refused." % [who, them]
			return "%s makes peace with %s." % [who, them]
	var template: String = String(ACT_LINES.get(kind, ""))
	return template % [who, them] if not template.is_empty() else ""


static func _battle_lines(
	play: PlaySession, rival: int, land_battles: Array, naval_battles: Array
) -> Array[String]:
	var lines: Array[String] = []
	for raw: Variant in land_battles:
		var battle: Dictionary = raw
		var attacker: int = int(battle.get("attacker", -1))
		var defender: int = int(battle.get("defender", -1))
		if attacker != rival and defender != rival:
			continue
		var province: String = _province_name(play, battle)
		if bool(battle.get("captured", false)) and attacker == rival:
			lines.append("took %s from %s" % [province, _name(play, defender)])
		elif bool(battle.get("captured", false)) and defender == rival:
			lines.append("lost %s to %s" % [province, _name(play, attacker)])
		else:
			lines.append("fought at %s" % province)
	for raw: Variant in naval_battles:
		var battle: Dictionary = raw
		var attacker: int = int(battle.get("attacker", -1))
		var defender: int = int(battle.get("defender", -1))
		if attacker != rival and defender != rival:
			continue
		lines.append("fought a squadron action in %s" % _zone_name(play, battle))
	return lines


static func _research_lines(rival: int, economy_report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for tech: String in _researched(rival, economy_report):
		lines.append("completed %s" % TechCatalog.display_name(tech))
	return lines


## The turn the despatch narrates: the calendar has already advanced when the
## spy reports, so the observation keeps the turn it resolved on.
static func _resolved_turn(play: PlaySession) -> int:
	return maxi(play.turn - 1, 1)


## Studies the shadowed court finished this turn, as ids.
static func _researched(rival: int, economy_report: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var factions: Dictionary = economy_report.get("factions", {})
	var entry: Dictionary = factions.get(rival, {})
	var resolved: Dictionary = entry.get("resolved", {})
	var research: Dictionary = resolved.get("research", {})
	for tech: Variant in research.get("researched", []):
		found.append(String(tech))
	return found


## A finished study is invisible to every crown but the one that posted the spy,
## so the observation enters the chronicle and the dossier can weigh it later:
## a court racing the field reads as a tech thief (DR-20261110-25).
static func _record_studies(play: PlaySession, rival: int, economy_report: Dictionary) -> void:
	if play.diplomacy == null:
		return
	for tech: String in _researched(rival, economy_report):
		play.diplomacy.record_event(
			IntelEvidence.SPY_TECH,
			rival,
			play.player_faction,
			{"tech": tech, IntelEvidence.OBSERVED_TURN: _resolved_turn(play)}
		)


## The works the shadowed court's builders began this turn, counted by theme.
## Build notes are behaviour, not suspicion: the dossier lists them without
## weighing an agenda.
static func _record_builds(play: PlaySession, rival: int, economy_report: Dictionary) -> void:
	var works: Dictionary = {}
	var factions: Dictionary = economy_report.get("factions", {})
	var entry: Dictionary = factions.get(rival, {})
	var civilians: Dictionary = entry.get("civilians", {})
	for raw: Variant in civilians.get("orders", []):
		var order: Dictionary = raw as Dictionary
		var what: String = _build_kind(String(order.get("action", "")))
		if what.is_empty():
			continue
		works[what] = int(works.get(what, 0)) + 1
	if works.is_empty() or play.diplomacy == null:
		return
	play.diplomacy.record_event(
		IntelEvidence.SPY_BUILD,
		rival,
		play.player_faction,
		{"works": works, IntelEvidence.OBSERVED_TURN: _resolved_turn(play)}
	)


## A work order that raises something, folded into the theme the notes name.
static func _build_kind(action: String) -> String:
	match action:
		"build_improvement":
			return "improvement"
		"upgrade_town":
			return "town"
		"build_road":
			return "road"
		"build_port":
			return "port"
		"build_fort":
			return "fort"
		"build_rail":
			return "rail"
	return ""


## A court the viewer has met by name, a stranger masked, the viewer itself
## always named (wiki: diplomacy § Diplomatic History).
static func _name(play: PlaySession, faction: int) -> String:
	if play.diplomacy == null:
		return FactionCatalog.name_of(faction)
	return DiplomacyHistory.name_for(play.diplomacy, play.player_faction, faction)


static func _province_name(play: PlaySession, battle: Dictionary) -> String:
	var region: int = int(battle.get("region", play.region_index))
	var model: MapModel = play.world.region(region)
	if model == null:
		return "—"
	return model.province_name(int(battle.get("province", -1)))


static func _zone_name(play: PlaySession, battle: Dictionary) -> String:
	var region: int = int(battle.get("region", play.region_index))
	var model: MapModel = play.world.region(region)
	if model == null:
		return "—"
	return model.sea_zone_name(int(battle.get("zone", -1)))
