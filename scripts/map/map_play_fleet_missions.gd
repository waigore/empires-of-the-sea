class_name MapPlayFleetMissions
extends RefCounted
## Fleet dossier station orders and the end-of-turn raid report. Rules stay in
## FleetMissions/NavalRaid; the two station prices in MapPlayStationNotes; this
## only builds rows, routes intents and refreshes the dossier (wiki:
## ships-and-naval § Missions and Movement; DR-20261109-16).


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


## What a standing station takes this turn — see [MapPlayStationNotes.prize].
static func prize_note(play: PlaySession, fleet: FleetState) -> String:
	return MapPlayStationNotes.prize(play, fleet)


## What the station catches this turn — see [MapPlayStationNotes.catch].
static func interception_note(play: PlaySession, fleet: FleetState) -> String:
	return MapPlayStationNotes.catch(play, fleet)


## One hull's name with its indefinite article — see
## [MapPlayStationNotes.with_article].
static func with_article(name: String) -> String:
	return MapPlayStationNotes.with_article(name)


## The Privateering Companies bonus, phrased for the dossier — see
## [MapPlayStationNotes.privateers].
static func privateer_note(play: PlaySession) -> String:
	return MapPlayStationNotes.privateers(play)


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
