class_name MapPlayDiplomacyAi
extends RefCounted
## Rival diplomacy turn for the map screen: one action per Great Power before
## the phase closes, then unit colour and chart rebuilds when a Minor is
## absorbed (docs/ai.md; wiki: diplomacy § Turn Sequence).
##
## Readings and charts ride the context so no court plans against unseen
## garrisons or land (DR-20261112-09, DR-20261113-03). Consent prompts stay in
## MapPlayDiplomacyConsent; court orders stay in MapPlayDiplomacy.
##
## Under BENCH, the subject uses the submission AiTurn and baseline rivals use
## mainline AiTurn; random courts issue no diplomacy.


## Rival Great Powers take their one diplomatic action for the turn before the
## phase closes, so declarations apply to this turn's movement and combat.
## BENCH baselines share the submission diplomacy planner (session AiState is
## not dual-loadable); economy/land/sea still route through AiBind mainline.
static func run(play: PlaySession) -> void:
	if play.ai == null:
		play.ai = AiState.new()
	var result: Dictionary = AiTurn.run(
		play.diplomacy,
		play.world,
		play.ai,
		play.turn,
		play.human_faction_id(),
		play.map_seed,
		_context(play)
	)
	var trace: Array = []
	trace.assign(result.get("trace", []))
	play.ai_trace.assign(trace)
	_apply_map_changes(play, trace)
	if play.hud == null:
		return
	for record: Dictionary in play.ai_trace:
		for line: String in _announcements(play, record):
			play.hud.toast(line)
	# The pass has just raised every new decision in its own words; the turn
	# resolver must not raise them a second time on the same press.
	MapPlayDiplomacyConsent.mark_announced(play)


## What the crown hears the moment the pass resolves, in the court's own voice.
## A declaration between two rivals is World news: the Gazette narrates it from
## the recorded `warDeclared` event and a spy's court report carries it, so the
## toast lane is no third announcement of the same war (wiki: the-gazette
## § Not the Gazette; civilian-units § Spy). A declaration on the crown is told
## at once — it governs this turn's movement and combat.
static func _announcements(play: PlaySession, record: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	lines.assign(record.get("messages", []))
	if lines.is_empty():
		# A trace from before the pass kept per-court lines still speaks.
		var message: String = String(record.get("message", ""))
		if not message.is_empty():
			lines.append(message)
	# A refused or unapplied order says nothing: the record only carries the
	# lines the rules actually resolved.
	if _rival_declaration(play, record):
		return []
	return lines


## True for a declaration the crown neither made nor suffered.
static func _rival_declaration(play: PlaySession, record: Dictionary) -> bool:
	var action: Dictionary = record.get("action", {}) as Dictionary
	if String(action.get("kind", "")) != AiDiplomacyPlanner.KIND_DECLARE_WAR:
		return false
	return int(action.get("target", MapModel.NO_ID)) != play.human_faction_id()


## A rival that absorbs a Minor moves provinces: its units change colour and the
## chart is rebuilt, exactly as the court's own Join Empire order does.
static func _apply_map_changes(play: PlaySession, trace: Array) -> void:
	for record: Dictionary in trace:
		var result: Dictionary = record.get("result", {})
		if not bool(result.get("map_changed", false)) and not result.has("absorbed"):
			continue
		var loser: int = int(result.get("absorbed", -1))
		if loser >= 0:
			var winner: int = int(record.get("faction", -1))
			if play.ship_layer != null:
				play.ship_layer.transfer_owner(loser, winner)
			if play.army_layer != null:
				play.army_layer.transfer_owner(loser, winner)
		play.refresh_map_views()


## Unit counts the war-desire score reads plus each rival's stockpile, so the
## resource-need bonus is live once the AI economy exists (wiki: diplomacy-planner).
## The counts stay the published docket; "readings" hands each rival the docket
## its own chart holds, so no court plans against unseen garrisons or hulls
## (DR-20261112-09). "charts" rides along so the planner's other world reads —
## the target's commodities and the land an envoy chain would open — stay on the
## same chart (DR-20261113-03).
##
## "strengths" is the order of battle the published power score reads (wiki:
## diplomacy § Great Power power score): the planner's relative-power factor is
## the public FPN + FPM over every land army, the same terms the court panel and
## the calendar's declared winner print. The head count above answers the
## invasion-capacity rule, which reads regiments and not their weight.
##
## When `only` is set, only those faction ids enter the planning gate (BENCH
## subject vs baseline passes).
static func _context(play: PlaySession, only: Array = []) -> Dictionary:
	var regiments: Dictionary = {}
	var ships: Dictionary = {}
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		if play.army_layer != null:
			regiments[faction] = MapPlayCourt.regiments(play, faction)
		if play.ship_layer != null:
			ships[faction] = MapPlayCourt.ships(play, faction)
	var planning: Array[int] = []
	for faction: int in FactionCatalog.great_power_ids():
		if not AiControl.plans(play, faction):
			continue
		if not only.is_empty() and not only.has(faction):
			continue
		# Random BENCH fillers never take diplomacy.
		if AiControl.court_kind(play, faction) == AiControl.KIND_RANDOM:
			continue
		planning.append(faction)
	var context: Dictionary = {
		"regiments": regiments,
		"ships": ships,
		"strengths": MapPlayDiplomacy.public_orders(play).get("strength", {}),
		"planning": planning,
	}
	var readings: Dictionary = MapPlayCourtFog.oob_readings(play)
	if not readings.is_empty():
		context["readings"] = readings
	if play.court_charts != null:
		context["charts"] = play.court_charts
	if play.ai != null:
		context["stockpiles"] = play.ai.stockpiles(play.human_faction_id())
	return context
