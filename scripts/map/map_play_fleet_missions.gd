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
## crown that has chartered privateers also reads what the bonus is worth.
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


## What a standing blockade is worth this turn: the chance its raid rolls, the
## cargo it would skim and the merchant hull it could send down — read before the
## player commits the move (DR-20261111-17).
static func prize_note(play: PlaySession, fleet: FleetState) -> String:
	if fleet == null or fleet.owner != play.player_faction:
		return ""
	if fleet.mission != FleetState.Mission.BLOCKADE or play.model == null:
		return ""
	if fleet.blockade_province == MapModel.NO_ID:
		return ""
	var province: ProvinceState = play.model.province_data(fleet.blockade_province)
	if province == null or province.owner == play.player_faction:
		return ""
	if play.economy == null or play.economy.market == null:
		return ""
	var imports: Dictionary = play.economy.market.imports_for(province.owner)
	if imports.is_empty():
		return "Prize: no cargo afloat off this coast this turn."
	var home: FleetState = MapPlayRaids.home_fleet(play, province.owner)
	if home == null:
		return "Prize: the coast's merchant hulls are at sea — nothing to take."
	var odds: Dictionary = NavalRaid.preview(
		[fleet], home, imports, FleetState.Mission.BLOCKADE, play.has_tech
	)
	var chance: int = int(round(float(odds.get("chance", 0.0)) * 100.0))
	var at_risk: String = String(odds.get("hull_at_risk", ""))
	if at_risk.is_empty():
		return "Prize: %d%% to take ~%d cargo — no merchant hull at risk." % [
			chance, int(odds.get("expected", 0))
		]
	var hull_chance: int = int(round(float(odds.get("hull_chance", 0.0)) * 100.0))
	return "Prize: %d%% to take ~%d cargo; a hit sinks a %s on %d%%." % [
		chance, int(odds.get("expected", 0)),
		ShipStats.display_name(at_risk), hull_chance,
	]


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
