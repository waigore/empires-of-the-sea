class_name PlayScreen
extends RefCounted
## The one way a MapPlay* helper speaks to the screen (REQ-P3-02).
##
## PlaySession keeps the campaign's state and the reads the rules ask of it;
## this class keeps the single Node that session was bound to and every airing
## the screen answers — the plate, the cue, the ink and the region swap. A
## helper says `play.screen.emit_turn_ended(turn)` instead of reaching into the
## chart's node tree, so the host stays in one place and a helper can never
## grow a `get_node` path to it (REQ-P3-02).
##
## Presentation only: nothing here decides an outcome, and with no host bound
## every call is inert — the headless harnesses run the same paths (REQ-P3-03).

## MapScreen (or a test double) that owns the signals and the viewport. Null
## while a campaign is built headless.
var host: Node = null


func viewport() -> Viewport:
	if host == null:
		return null
	return host.get_viewport()


func emit_province_selected(province_id: int) -> void:
	if host != null:
		host.emit_signal("province_selected", province_id)


func emit_selection_cleared() -> void:
	if host != null:
		host.emit_signal("selection_cleared")


func emit_coast_charted(province_id: int) -> void:
	if host != null:
		host.emit_signal("coast_charted", province_id)


## A fight is done and the courts have answered it: the screen answers with the
## plate, cue and ink (wiki: dialogue-and-mood § Design intent — event: battle
## results; DR-20261111-01). Both passes report here, so land and sea book
## alike; a sea fight carries a zone and a land battle a province.
func emit_battle_resolved(battles: Array[Dictionary]) -> void:
	if host != null:
		host.emit_signal("battle_resolved", battles)


## The turn's raids, in either direction: the screen answers with a cue and a
## ring on the waters that were worked (REQ-P5-06).
func emit_raid_resolved(raids: Array[Dictionary]) -> void:
	if host != null and host.has_signal("raid_resolved"):
		host.emit_signal("raid_resolved", raids)


func emit_turn_ended(turn: int) -> void:
	if host != null:
		host.emit_signal("turn_ended", turn)


## The rules closed the campaign — a military victory or the human crown's
## fall; the screen forwards the moment to audio and motion.
func emit_campaign_end(victory: VictoryState = null, defeat: DefeatState = null) -> void:
	if host == null:
		return
	if defeat != null and host.has_signal("defeat_declared"):
		host.emit_signal("defeat_declared", defeat)
	elif victory != null:
		host.emit_signal("victory_declared", victory)


## Political ownership changed (Join Empire): ask the screen to redraw the map.
func refresh_map_views() -> void:
	if host != null and host.has_method("refresh_political_map"):
		host.call("refresh_political_map")


## Swaps the whole view onto another region (fleet crossing a passage).
func switch_region(index: int) -> void:
	if host != null and host.has_method("load_region"):
		host.call("load_region", index)
