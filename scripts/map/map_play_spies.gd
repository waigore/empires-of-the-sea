class_name MapPlaySpies
extends RefCounted
## Spy resolution, counter-espionage and court reports on the map screen
## (wiki: civilian-units § Spy, diplomacy § Spy-death penalty). Presence and
## research theft live in SpyNetworks; this adapter applies the consequences to
## the shared session and reports only what the human court could know
## (REQ-P3-02).


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
		for owner: Variant in SpyRules.screened_owners(model, _roster(play, region)).keys():
			screens[int(owner)] = true
	if screens.is_empty():
		return events
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[CivilianState] = _roster(play, region)
		var found: Array[Dictionary] = SpyRules.resolve_turn(
			model, roster, play.turn, play.map_seed, screens
		)
		if found.is_empty():
			continue
		play.civilian_layer.regions.set_region(region, roster)
		for event: Dictionary in found:
			event["region"] = region
			_apply_relation(play, event)
			_toast(play, event)
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
	var result: Array[int] = []
	if play == null or play.world == null or play.civilian_layer == null:
		return result
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		for rival: int in SpyNetworks.qualifying_rivals(
			model, _roster(play, region), faction
		):
			if not result.has(rival):
				result.append(rival)
	result.sort()
	return result


## Last-turn court reports for each observed rival: diplomatic acts, battles,
## provinces taken or lost and technologies completed. One toast per court.
static func report(
	play: PlaySession,
	land_battles: Array,
	naval_battles: Array,
	economy_report: Dictionary
) -> void:
	if play == null or play.hud == null:
		return
	var qualifying: Array[int] = qualifying_rivals(play, play.player_faction)
	if qualifying.is_empty():
		return
	for rival: int in qualifying:
		var lines: Array[String] = _diplomacy_lines(play, rival)
		lines.append_array(_battle_lines(play, rival, land_battles, naval_battles))
		lines.append_array(_research_lines(rival, economy_report))
		if lines.is_empty():
			continue
		play.hud.toast(
			"Spy report — %s: %s"
			% [FactionCatalog.name_of(rival), " · ".join(lines)]
		)


# --- internals ---------------------------------------------------------------


static func _roster(play: PlaySession, region: int) -> Array[CivilianState]:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.units
	var roster: Array[CivilianState] = []
	roster.assign(play.civilian_layer.regions.value(region, []))
	return roster


## A killed spy cools relations by 8 and counts as this turn's interaction
## (wiki: diplomacy § Spy-death diplomacy penalty).
static func _apply_relation(play: PlaySession, event: Dictionary) -> void:
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


## Spies are invisible to every other court: the human only hears about its own
## loss or a spy caught in its own land (wiki: civilian-units § Spy (4)).
static func _toast(play: PlaySession, event: Dictionary) -> void:
	if play.hud == null:
		return
	var player: int = play.player_faction
	var owner: int = int(event.get("owner", -1))
	var territory: int = int(event.get("territory_owner", -1))
	var province: int = int(event.get("province", -1))
	var model: MapModel = play.world.region(int(event.get("region", play.region_index)))
	var place: String = "the wilds"
	if model != null and province >= 0:
		place = model.province_name(province)
	var kind: String = String(event.get("kind", ""))
	if kind == "killed":
		if owner == player:
			play.hud.toast("A spy in %s has gone silent." % place)
		elif territory == player:
			play.hud.toast(
				"Counter-espionage caught a %s spy in %s."
				% [FactionCatalog.name_of(owner), place]
			)
	elif kind == "defected":
		if owner == player:
			play.hud.toast("A spy in %s has turned coat." % place)
		elif territory == player:
			play.hud.toast(
				"A %s spy in %s has turned coat and now serves your crown."
				% [FactionCatalog.name_of(owner), place]
			)


static func _diplomacy_lines(play: PlaySession, rival: int) -> Array[String]:
	var lines: Array[String] = []
	for record: Dictionary in play.ai_trace:
		if int(record.get("faction", -1)) != rival:
			continue
		var message: String = String(record.get("message", ""))
		if not message.is_empty():
			lines.append(message)
	return lines


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
			lines.append("took %s from %s" % [province, FactionCatalog.name_of(defender)])
		elif bool(battle.get("captured", false)) and defender == rival:
			lines.append("lost %s to %s" % [province, FactionCatalog.name_of(attacker)])
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
	var factions: Dictionary = economy_report.get("factions", {})
	var entry: Dictionary = factions.get(rival, {})
	var resolved: Dictionary = entry.get("resolved", {})
	var research: Dictionary = resolved.get("research", {})
	for tech: Variant in research.get("researched", []):
		lines.append("completed %s" % TechCatalog.display_name(String(tech)))
	return lines


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
