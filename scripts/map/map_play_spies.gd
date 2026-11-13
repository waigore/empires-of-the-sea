class_name MapPlaySpies
extends RefCounted
## Spy resolution and counter-espionage on the map screen (wiki: civilian-units
## § Spy, diplomacy § Spy-death penalty). Presence and research theft live in
## SpyNetworks; court despatches leave to MapPlaySpyReports; this adapter applies
## kill and defection consequences to the shared session and reports only what
## the human court could know (REQ-P3-01, REQ-P3-02).


## Pre-Research pass: counter-espionage kills and defections in every region.
## Returns the events for callers/tests; the HUD hears only player-facing ones.
##
## One spy on `counter_spy` anywhere covers the whole empire, so the screen set
## is gathered across every region first: a spy caught in a colony is hunted by
## the screen kept at home (wiki: civilian-units § Spy (3)).
static func resolve(play: PlaySession) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if play == null or play.world == null or play.civilian_layer == null:
		return events
	var screens: Dictionary = {}
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		for owner: Variant in SpyRules.screened_owners(
			model, MapPlaySpyAi.roster_for(play, region)
		).keys():
			screens[int(owner)] = true
	if screens.is_empty():
		return events
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[CivilianState] = MapPlaySpyAi.roster_for(play, region)
		var found: Array[Dictionary] = SpyRules.resolve_turn(
			model, roster, play.turn, play.map_seed, screens
		)
		if found.is_empty():
			continue
		play.civilian_layer.regions.set_region(region, roster)
		for event: Dictionary in found:
			event["region"] = region
			var place: String = _place(play, event)
			_apply_relation(play, event, place)
			var line: String = notice(event, place, play.player_faction)
			if not line.is_empty() and play.hud != null:
				play.hud.toast(line)
			events.append(event)
	if events.is_empty():
		return events
	play.civilian_layer._rebuild_markers()
	play.civilian_layer.queue_redraw()
	if play.hud != null and play.hud.is_node_ready():
		play.hud.set_civilians(
			play.civilian_layer.unit_count_all(play.player_faction)
		)
	var selected: CivilianState = play.civilian_layer.selected_unit
	if selected != null and (
		not play.civilian_layer.units.has(selected)
		or SpyRules.hidden_from(selected, play.player_faction)
	):
		play.civilian_layer.deselect()
		if play.hud != null and play.hud.panels != null:
			play.hud.panels.hide_civilian()
	return events


## Rival Great Powers observed by this court's spies in any region.
static func qualifying_rivals(play: PlaySession, faction: int) -> Array[int]:
	return MapPlaySpyAi.qualifying_rivals(play, faction)


## Lines a court's despatch keeps (mirrors MapPlaySpyReports.MAX_LINES).
const MAX_LINES: int = 8


## Last-turn court reports — see MapPlaySpyReports.report.
static func report(
	play: PlaySession,
	land_battles: Array,
	naval_battles: Array,
	economy_report: Dictionary
) -> void:
	MapPlaySpyReports.report(play, land_battles, naval_battles, economy_report)


# --- internals ---------------------------------------------------------------


## A killed spy cools relations by 8 and counts as this turn's interaction
## (wiki: diplomacy § Spy-death penalty). The price is also a diplomatic act, so
## the chronicle keeps it: without a line there, the court panel's standing has
## shifted for no stated reason (wiki: diplomacy § Diplomatic History).
static func _apply_relation(
	play: PlaySession, event: Dictionary, place: String
) -> void:
	if String(event.get("kind", "")) != "killed" or play.diplomacy == null:
		return
	var owner: int = int(event.get("owner", -1))
	var territory: int = int(event.get("territory_owner", -1))
	if owner < 0 or territory < 0 or owner == territory:
		return
	var relation: DiplomacyRelation = play.diplomacy.relation(owner, territory)
	if relation == null:
		return
	relation.add_score(-SpyRules.KILL_RELATION_PENALTY)
	relation.last_interaction_turn = play.turn
	play.diplomacy.record_event("spyTaken", owner, territory, {"province": place})


## The line the court hears for a spy event it can know about, or "" when the
## event is another court's business (wiki: civilian-units § Spy (4): a spy's
## province is invisible to every other court). A killed spy costs the pair 8
## relations, so the line names that price: a court that pays for its own
## defence is told what it paid (wiki: diplomacy § Spy-death penalty).
static func notice(event: Dictionary, place: String, viewer: int) -> String:
	var owner: int = int(event.get("owner", -1))
	var territory: int = int(event.get("territory_owner", -1))
	var who: String = FactionCatalog.name_of(owner)
	var price: int = int(SpyRules.KILL_RELATION_PENALTY)
	match String(event.get("kind", "")):
		"killed":
			if owner == viewer:
				return "A spy in %s has gone silent — −%d with %s." % [
					place, price, FactionCatalog.name_of(territory),
				]
			if territory == viewer:
				return "Counter-espionage caught %s's spy in %s — −%d with %s." % [
					who, place, price, who,
				]
		"defected":
			if owner == viewer:
				return "A spy in %s has turned coat." % place
			if territory == viewer:
				return "%s's spy in %s has turned coat and now serves your crown." % [
					who, place,
				]
	return ""


## The province an event names, or "the wilds" when the tile belongs to none.
static func _place(play: PlaySession, event: Dictionary) -> String:
	var model: MapModel = play.world.region(int(event.get("region", play.region_index)))
	var province: int = int(event.get("province", -1))
	if model == null or province < 0:
		return "the wilds"
	return model.province_name(province)
