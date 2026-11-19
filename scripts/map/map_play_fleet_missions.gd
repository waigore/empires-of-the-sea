class_name MapPlayFleetMissions
extends RefCounted
## Fleet dossier station orders and the end-of-turn raid report. Rules stay in
## FleetMissions/NavalRaid; this only builds rows, routes intents and refreshes
## the dossier (wiki: ships-and-naval § Missions and Movement; DR-20261109-16).


## One button per station (Patrol, Defend, a Blockade target) plus the
## Beachhead costs already offered by MapPlayBeachhead.
static func rows(play: PlaySession, fleet: FleetState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if fleet == null or fleet.owner != play.player_faction:
		return rows
	if fleet.is_at_sea() and not fleet.moved:
		if fleet.mission != FleetState.Mission.PATROL:
			rows.append({"label": "Patrol this zone", "action": "mission:patrol"})
		if fleet.mission != FleetState.Mission.DEFEND:
			rows.append({"label": "Defend — hold station", "action": "mission:defend"})
		for province_id: int in FleetMissions.blockade_targets(
			play.model, fleet, MapPlayBeachhead.hostile(play)
		):
			if fleet.mission == FleetState.Mission.BLOCKADE \
					and fleet.blockade_province == province_id:
				continue
			rows.append({
				"label": "Blockade %s" % play.model.province_name(province_id),
				"action": "mission:blockade:%d" % province_id,
			})
	rows.append_array(MapPlayBeachhead.rows(play, fleet))
	return rows


## The dossier's station line: a landing site outranks an ordinary station. A
## station at sea also reads what it would catch (`Interception:`) and what it
## would take (`Prize:`), in the rule book's own order, and a crown that has
## chartered privateers reads what the bonus is worth.
static func note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction:
		return ""
	if fleet.has_beachhead():
		return MapPlayBeachhead.note(play, fleet)
	var line: String = FleetMissions.status_note(
		play.model, fleet, MapPlayBeachhead.hostile(play)
	)
	if not fleet.is_at_sea():
		return line
	var extras: Array[String] = []
	var catch_line: String = interception_note(play, fleet)
	if not catch_line.is_empty():
		extras.append(catch_line)
	var prize: String = prize_note(play, fleet)
	if not prize.is_empty():
		extras.append(prize)
	var charter: String = privateer_note(play)
	if not charter.is_empty():
		extras.append(charter)
	if extras.is_empty():
		return line
	return " ".join(extras) if line.is_empty() else "%s %s" % [line, " ".join(extras)]


## The dossier's hint line: a landing site's stake, or nothing when no site is
## held (the station note already carries the ordinary mission line).
static func hint(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction or not fleet.has_beachhead():
		return ""
	return MapPlayBeachhead.hint(play, fleet)


## What a standing station is worth this turn: the chance its raid rolls, the
## cargo it would skim and the merchant hull it could send down — read before the
## player commits the move (DR-20261111-17, DR-20261120-01). **A patrol raids as
## a blockade does**, at the patrol factor, and the pass rolls the squadron with
## every other station the crown holds in that water: the price is the group's,
## against a coast the crown is at war with, so the sheet promises no roll the
## rules would not make (wiki: ships-and-naval § Trade and Transport
## Interception; REQ-P2-03).
static func prize_note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction:
		return ""
	if play.model == null or not fleet.is_at_sea():
		return ""
	if play.economy == null or play.economy.market == null:
		return ""
	var hostile: Callable = MapPlayRaids.hostile(play)
	if not NavalRaid.raids(play.model, fleet, hostile):
		return ""
	var group: Array = NavalRaid.station_group(
		play.model, _roster(play), fleet.sea_zone, fleet.owner, hostile
	)
	if group.is_empty():
		group = [fleet]
	var mission: int = FleetMissions.station_mission(play.model, group, hostile)
	var best: Dictionary = {}
	var coasts: Array[int] = _prize_coasts(play, fleet, hostile)
	var afloat: bool = false
	for province_id: int in coasts:
		var owner: int = play.model.province_owner(province_id)
		var imports: Dictionary = play.economy.market.imports_for(owner)
		if imports.is_empty():
			continue
		afloat = true
		var home: FleetState = MapPlayRaids.home_fleet(play, owner)
		if home == null:
			continue
		var odds: Dictionary = NavalRaid.preview(
			group, home, imports, mission, play.has_tech
		)
		if best.is_empty() or float(odds.get("chance", 0.0)) > float(best.get("chance", 0.0)):
			best = odds
			best["coast"] = play.model.province_name(province_id)
	if not afloat:
		return _no_prize_words(fleet)
	if best.is_empty():
		return _no_prize_words(fleet, true)
	var chance: int = int(round(float(best.get("chance", 0.0)) * 100.0))
	var take: String = "Prize: %d%% to take ~%d cargo" % [chance, int(best.get("expected", 0))]
	# A patrol's station note names no coast, so its price names the one it works;
	# a blockade's note already reads "Blockading Coro".
	if fleet.mission == FleetState.Mission.PATROL:
		take += " off %s" % String(best.get("coast", "the coast"))
	var at_risk: String = String(best.get("hull_at_risk", ""))
	if at_risk.is_empty():
		return take + " — no merchant hull at risk."
	var hull_chance: int = int(round(float(best.get("hull_chance", 0.0)) * 100.0))
	return "%s; a hit sinks a %s on %d%%." % [
		take, ShipStats.display_name(at_risk), hull_chance
	]


## What the station catches: the chance a patrol, or a blockade that still
## stands, intercepts a hostile squadron that is still in this water when the
## turn closes — the published formula read through the rules' own
## `NavalInterception.chance`, over the squadrons that hold the station (the same
## list the combat pass rolls). A rival the crown has not read is left out and
## named, so the sheet never promises a number the fog withholds, and a water
## with nothing to catch prints no line (wiki: ships-and-naval § Naval
## Interception Probability, § Sighted strength; REQ-P2-03, REQ-P5-03).
static func interception_note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction:
		return ""
	if play.model == null or not fleet.is_at_sea():
		return ""
	var hostile: Callable = MapPlayRaids.hostile(play)
	if not NavalRaid.raids(play.model, fleet, hostile):
		return ""
	var roster: Array = _roster(play)
	var group: Array = NavalRaid.station_group(
		play.model, roster, fleet.sea_zone, fleet.owner, hostile
	)
	if group.is_empty():
		group = [fleet]
	var mission: int = FleetMissions.station_mission(play.model, group, hostile)
	var holders: Array = NavalInterception.station_holders(play.model, group, hostile)
	if holders.is_empty():
		holders = group
	var targets: Array = []
	var unread: bool = false
	for other: FleetState in roster:
		if other == null or other.owner == fleet.owner:
			continue
		if not other.is_at_sea() or other.sea_zone != fleet.sea_zone:
			continue
		if not other.is_afloat():
			continue
		if not Hostility.between(hostile, fleet.owner, other.owner):
			continue
		if not MapPlayFleetIntel.strength_read(play, other):
			unread = true
			continue
		targets.append(other)
	var read: Dictionary = NavalInterception.preview(
		holders, targets, mission, play.has_tech, unread
	)
	if read.is_empty():
		return ""
	if bool(read.get("unread", false)):
		return "Interception: the odds wait on a squadron the fog has not read."
	var hulls: int = int(read.get("hulls", 0))
	if hulls <= 0:
		return ""
	var chance: int = int(round(float(read.get("chance", 0.0)) * 100.0))
	return "Interception: %d%% to catch %d hull%s if they stay." % [
		chance, hulls, "" if hulls == 1 else "s",
	]


## The empty reading: a coast with no cargo afloat this turn, or a coast whose
## merchant hulls are at sea. A patrol works the whole water, so it says so.
static func _no_prize_words(fleet: FleetState, hulls_away: bool = false) -> String:
	if fleet.mission != FleetState.Mission.PATROL:
		if hulls_away:
			return "Prize: the coast's merchant hulls are at sea — nothing to take."
		return "Prize: no cargo afloat off this coast this turn."
	if hulls_away:
		return "Prize: the merchant hulls off these coasts are at sea — nothing to take."
	return "Prize: no cargo afloat off these coasts this turn."


## The at-war coasts this station's water reaches: the blockaded coast first, so
## a blockade reads its own shore as it always did, then the rest by province id.
static func _prize_coasts(
	play: PlaySession, fleet: FleetState, hostile: Callable
) -> Array[int]:
	var coasts: Array[int] = []
	if fleet.mission == FleetState.Mission.BLOCKADE and fleet.blockade_province >= 0:
		coasts.append(fleet.blockade_province)
	var found: Array[int] = []
	for province_id: int in NavalMovement.provinces_by_zone(play.model, fleet.sea_zone):
		if coasts.has(province_id):
			continue
		var owner: int = play.model.province_owner(province_id)
		if owner < 0 or owner == fleet.owner:
			continue
		if not Hostility.between(hostile, fleet.owner, owner):
			continue
		found.append(province_id)
	found.sort()
	coasts.append_array(found)
	return coasts


## The chart's roster, which is the group the pass reads: the dossier is open on
## a region and every station the crown holds in the water stands on that chart.
static func _roster(play: PlaySession) -> Array:
	if play.ship_layer == null:
		return []
	return play.ship_layer.fleets


## The Privateering Companies bonus, phrased for the dossier (wiki:
## ships-and-naval § Trade and Transport Interception).
static func privateer_note(play: PlaySession) -> String:
	if not play.has_tech(play.player_faction, NavalInterception.PRIVATEERING_TECH):
		return ""
	var percent: int = int(round((NavalInterception.PRIVATEERING_BONUS - 1.0) * 100.0))
	return "Privateers: interception and raids +%d%%." % percent


## Routes a "mission:<kind>[:<province>]" order through the rules and refreshes
## the dossier without deselecting the squadron.
static func on_action(play: PlaySession, action: String) -> void:
	if not action.begins_with("mission:"):
		return
	var fleet: FleetState = play.ship_layer.fleet_of(play.ship_layer.selected())
	if fleet == null or fleet.owner != play.player_faction:
		return
	var parts: PackedStringArray = action.split(":")
	if parts.size() < 2:
		return
	var mission: int = FleetMissions.from_id(String(parts[1]))
	var province_id: int = (
		int(parts[2]) if parts.size() > 2 else MapModel.NO_ID
	)
	var result: Dictionary = FleetMissions.assign(
		play.model, fleet, mission, province_id, MapPlayBeachhead.hostile(play)
	)
	if not bool(result.get("ok", false)):
		play.hud.toast(String(result.get("reason", "That station cannot be taken.")))
		return
	play.hud.toast(String(result.get("message", "")))
	MapPlayFleets.show_dossier(play, fleet)
	MapPlayFleets.refresh_options(play, fleet)
