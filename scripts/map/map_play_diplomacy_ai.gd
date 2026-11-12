class_name MapPlayDiplomacyAi
extends RefCounted
## Rival Great Powers take their one diplomatic action for the turn before the
## phase closes, so declarations apply to this turn's movement and combat
## (wiki: diplomacy § Turn Sequence). Split from MapPlayDiplomacy so the court
## panel wiring does not own the AI pass (REQ-P3-01).


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
		context(play)
	)
	play.ai_trace.assign(result.get("trace", []))
	_apply_map_changes(play, result.get("trace", []))
	if play.hud == null:
		return
	for message: String in result.get("messages", []):
		play.hud.toast(message)
	# The pass has just raised every new decision in its own words; the turn
	# resolver must not raise them a second time on the same press.
	MapPlayDiplomacyPending.mark_announced(play)


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
static func context(play: PlaySession) -> Dictionary:
	var regiments: Dictionary = {}
	var ships: Dictionary = {}
	for raw: Dictionary in FactionCatalog.all():
		var faction: int = int(raw["id"])
		if play.army_layer != null:
			regiments[faction] = play.army_layer.regiment_count_all(faction)
		if play.ship_layer != null:
			ships[faction] = play.ship_layer.hull_count_all(faction)
	var out: Dictionary = {"regiments": regiments, "ships": ships}
	var readings: Dictionary = MapPlayCourtFog.oob_readings(play)
	if not readings.is_empty():
		out["readings"] = readings
	if play.court_charts != null:
		out["charts"] = play.court_charts
	if play.ai != null:
		out["stockpiles"] = play.ai.stockpiles(play.human_faction_id())
	return out
