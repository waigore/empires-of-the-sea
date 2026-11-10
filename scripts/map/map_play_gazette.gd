class_name MapPlayGazette
extends RefCounted
## Turn-close collection for the crown's news sheet, and the plate's commands
## (wiki: the-gazette; DR-20261110-14). The rules live in [Gazette] and
## [GazetteState]; this adapter reads the resolved turn from the session, files
## the sheet and raises or lowers the soft plate. It decides no outcome
## (REQ-P3-02, REQ-P5-06).


## Founds the watchlist on the bonds the campaign opens with. Safe to call on
## every turn start: a court the player struck off stays off (wiki: the-gazette
## § Courts of interest).
static func ensure(play: PlaySession) -> void:
	if play == null or play.observer_mode:
		return
	if play.gazette == null:
		play.gazette = GazetteState.new()
	GazetteState.seed(play.gazette, play.diplomacy, play.player_faction)


## Files the sheet for the turn that just resolved and opens it when it printed
## anything. `land`/`naval` are the phase records, `economy` the rival ledgers'
## report, `crown_report` the human ledger's, `raids` MapPlayRaids' result.
static func close_turn(
	play: PlaySession,
	land: Array,
	naval: Array,
	economy: Dictionary,
	crown_report: Dictionary,
	raids: Dictionary
) -> void:
	if play == null or play.observer_mode or play.diplomacy == null:
		return
	# The calendar already advanced: the sheet narrates the turn that resolved.
	var resolved: int = maxi(play.turn - 1, 1)
	ensure(play)
	var sheet: Dictionary = Gazette.collect(
		play.player_faction,
		resolved,
		play.world,
		play.diplomacy,
		play.gazette.watched,
		land,
		naval,
		play.last_falls,
		research_report(play, economy, crown_report),
		int(crown_report.get("riches_treasury", 0)),
		raids.get("reports", []) as Array
	)
	# An empty sheet is still filed so the archive has no gaps; it is not shown.
	play.gazette.append(sheet)
	if Gazette.is_empty(sheet):
		return
	show(play, sheet)


## Raises a sheet on the plate — the turn-start auto-open and a reopen alike.
static func show(play: PlaySession, sheet: Dictionary) -> void:
	if play == null or play.gazette == null or play.hud == null:
		return
	if play.hud.gazette_plate == null:
		return
	play.gazette.opened_turn = int(sheet.get("turn", 0))
	play.hud.gazette_plate.open_sheet(
		sheet, play.gazette, play.diplomacy, play.player_faction
	)


## The newest sheet, on demand from the cartouche seal.
static func open_archive(play: PlaySession) -> void:
	if play == null or play.hud == null or play.hud.gazette_plate == null:
		return
	ensure(play)
	play.hud.gazette_plate.open_archive(play.gazette, play.diplomacy, play.player_faction)


## Adds or removes one court on the watchlist; the plate repaints itself.
static func toggle_watch(play: PlaySession, faction: int) -> void:
	if play == null or play.gazette == null:
		return
	play.gazette.set_watched(faction, not play.gazette.is_watched(faction))


## Faction -> the technologies it finished this turn, from the rival ledgers'
## report and the crown's own. Rules take one shape so the collector stays pure.
static func research_report(
	play: PlaySession, economy: Dictionary, crown_report: Dictionary
) -> Dictionary:
	var finished: Dictionary = {}
	var factions: Dictionary = economy.get("factions", {})
	for raw: Variant in factions.keys():
		var entry: Dictionary = factions[raw] as Dictionary
		var resolved: Dictionary = entry.get("resolved", {}) as Dictionary
		var ids: Array[String] = _techs(resolved.get("research", {}))
		if not ids.is_empty():
			finished[int(raw)] = ids
	var mine: Array[String] = _techs(crown_report.get("research", {}))
	if not mine.is_empty():
		finished[play.player_faction] = mine
	return finished


static func _techs(report: Variant) -> Array[String]:
	var ids: Array[String] = []
	if typeof(report) != TYPE_DICTIONARY:
		return ids
	for tech: Variant in (report as Dictionary).get("researched", []):
		ids.append(String(tech))
	return ids
