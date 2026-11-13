class_name MapPlayObserver
extends RefCounted
## Live full-AI observer scoreboard (wiki: game-setup § Human/AI slot assignment
## — an empty human slot set is the full-AI observer; turn-trace-interpretation).
##
## One row per Great Power: lands, public power, forces, ledger, wars and last
## turn's orders. The observatory panel and the headless exporter render these;
## this module only reads PlaySession state (REQ-P2-03, REQ-P3-03).

const NO_ID: int = MapModel.NO_ID


## Live scoreboard ranked by Old World provinces then public power, with the
## campaign result when one is decided.
static func snapshot(play: PlaySession) -> Dictionary:
	var rows: Array[Dictionary] = []
	for faction: int in FactionCatalog.great_power_ids():
		rows.append(row(play, faction))
	rows.sort_custom(_better_row)
	for index in rows.size():
		rows[index]["rank"] = index + 1
	var winner: int = _winner(play)
	var leader: int = winner
	if leader == NO_ID and not rows.is_empty():
		leader = int(rows[0]["faction"])
	return {
		"turn": play.turn,
		"year": TurnTime.year_for_turn(play.turn),
		"seed": play.map_seed,
		"ai_mode": play.ai_mode,
		"ai_live": AiControl.live_faction(play),
		"campaign_over": play.campaign_over(),
		"winner": winner,
		"leader": leader,
		"result": _result_text(play, winner),
		"rows": rows,
	}


## One court's observable state. `economy` is that court's ledger whichever
## side (human path in a live game, AiState ledger in the observer).
static func row(play: PlaySession, faction: int) -> Dictionary:
	var config: AiConfig = AiConfig.build(faction, play.map_seed)
	var agenda: String = play.ai.agenda_for(config) if play.ai != null else config.agenda
	var economy: PlayerEconomy = _economy(play, faction)
	# The footing the court plans with this turn (DR-20261113-15): a war, an
	# overstretched court with two fronts, or the published peace. The money goal
	# rides beside it (DR-20261113-19).
	var phase: String = AiPhasePlanner.phase_for(config, play.diplomacy)
	var income: Dictionary = AiIncome.plan(
		config, economy, _at_war(play, faction),
		play.army_layer.regiment_count_all(faction)
	)
	var strength: float = _strength(play, faction)
	var ships: int = play.ship_layer.hull_count_all(faction)
	var old_world: int = play.world.owned_provinces(WorldMap.OLD_WORLD, faction)
	var new_world: int = play.world.owned_provinces(WorldMap.NEW_WORLD, faction)
	var last: Dictionary = _last_turn(play, faction)
	return {
		"faction": faction,
		"name": FactionCatalog.name_of(faction),
		"leader": LeaderCatalog.label(String(play.leaders.get(faction, ""))),
		"agenda": agenda.capitalize().replace("_", " "),
		"profile": config.profile,
		"phase": phase,
		"posture": AiPhasePlanner.label(phase),
		"goal": String(income["goal"]),
		"intent": AiIncome.label(String(income["goal"])),
		"reserve": int(income["reserve"]),
		"plans": AiControl.plans(play, faction),
		"provinces_old": old_world,
		"provinces_new": new_world,
		"provinces_total": old_world + new_world,
		"power": AiPower.score(play.world, faction, int(roundf(strength)), ships),
		"strength": int(roundf(strength)),
		"regiments": play.army_layer.regiment_count_all(faction),
		"ships": ships,
		"civilians": play.civilian_layer.unit_count_all(faction),
		"treasury": economy.treasury if economy != null else 0,
		"stock": economy.total_units() if economy != null else 0,
		"workers": economy.workers.total() if economy != null else 0,
		"techs": economy.tech_unlocked.size() if economy != null else 0,
		"wars": _war_names(play, faction),
		"alliances": _alliance_count(play, faction),
		"progress": float(old_world) / float(VictoryRules.MILITARY_THRESHOLD),
		"alive": old_world + new_world > 0,
		"last": last,
		"headline": AiTurnLog.headline(last),
	}


## Turn record of one court, empty before its first resolved turn.
static func _last_turn(play: PlaySession, faction: int) -> Dictionary:
	if play.ai_turns.is_empty():
		return {}
	var merged: Dictionary = play.ai_turns[play.ai_turns.size() - 1]
	var factions: Dictionary = merged.get("factions", {})
	return factions.get(faction, {})


static func _economy(play: PlaySession, faction: int) -> PlayerEconomy:
	return play.ledger_for(faction)


## Public order-of-battle strength: FPN + FPM over every land army, no medals
## (wiki: diplomacy § Great Power power score).
static func _strength(play: PlaySession, faction: int) -> float:
	if play.army_layer == null:
		return 0.0
	var total: float = 0.0
	for raw: Variant in play.army_layer.regions.values():
		var stored: Array[ArmyState] = []
		stored.assign(raw)
		for army: ArmyState in stored:
			if army != null and army.owner == faction:
				total += army.strength()
	return total


## True when any court holds a declared war on this one: the reserve the court
## must hold is read against it (DR-20261113-19).
static func _at_war(play: PlaySession, faction: int) -> bool:
	if play.diplomacy == null:
		return false
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			return true
	return false


static func _war_names(play: PlaySession, faction: int) -> Array[String]:
	var names: Array[String] = []
	if play.diplomacy == null:
		return names
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.at_war:
			names.append(FactionCatalog.name_of(record.other(faction)))
	names.sort()
	return names


static func _alliance_count(play: PlaySession, faction: int) -> int:
	var total: int = 0
	if play.diplomacy == null:
		return total
	for record: DiplomacyRelation in play.diplomacy.relations_of(faction):
		if record.formal_alliance:
			total += 1
	return total


static func _winner(play: PlaySession) -> int:
	if play.victory != null:
		return play.victory.winner_player_id
	if play.campaign_halted:
		return MapPlayCampaign.declared_leader(play)
	return NO_ID


static func _result_text(play: PlaySession, winner: int) -> String:
	if play.victory != null:
		return "%s wins a military victory on turn %d." % [
			FactionCatalog.name_of(winner), play.victory.turn_number,
		]
	if play.campaign_halted:
		if winner == NO_ID:
			return "The age is divided — no crown is declared."
		return "%s holds the age at the calendar cap." % FactionCatalog.name_of(winner)
	if winner != NO_ID:
		return "%s leads the campaign." % FactionCatalog.name_of(winner)
	return "Campaign in progress."


## Provinces first (the victory currency), then power, then faction id so the
## same state always ranks the same way.
static func _better_row(a: Dictionary, b: Dictionary) -> bool:
	if int(a["provinces_old"]) != int(b["provinces_old"]):
		return int(a["provinces_old"]) > int(b["provinces_old"])
	if int(a["power"]) != int(b["power"]):
		return int(a["power"]) > int(b["power"])
	return int(a["faction"]) < int(b["faction"])
