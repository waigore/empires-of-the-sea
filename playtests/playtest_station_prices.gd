extends SceneTree
## Headless free-playtest drive for the station's two prices: what a patrol or a
## blockade promises it will **catch** and what it promises it will **take**
## (wiki: ships-and-naval § Naval Interception Probability, § Trade and Transport
## Interception; DR-20261120-01, DR-20261120-02).
##
## The state is one of the hardest a crown can stand in: a station at sea off an
## enemy coast, at war, with a hostile squadron in the same water — and behind
## her a fog that may or may not have read that squadron's weight. The drive
## arrives the way a player does (sortie, station order, a declared war, a rival
## in the water) and reads only what the court is shown: the fleet dossier's
## station line and the turn's despatch. Every number on that line is then held
## to the pass that rolls it, called with the same inputs.
##
## A rival squadron is seated in the water and a second crown station is minted
## only where a scenario seat is the shortest way to the rare branch; the
## stations, the war, the interception roll, the raid, the cargo and the
## despatches are the game's own.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_station_prices.gd

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null
var _play: PlaySession = null
var _zone: int = -1
var _rival: int = -1
var _checks: int = 0
var _failed: int = 0
var _battles: Array[Dictionary] = []
var _raids: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, AdvancedStart.TURNS100)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_screen.battle_resolved.connect(_on_battle)
	_screen.raid_resolved.connect(_on_raid)
	var player: int = _play.player_faction
	_say("seed %s · turn %d · player %s · capital %s (%d) · %d hulls" % [
		SEED_TEXT, _play.turn, FactionCatalog.name_of(player),
		_play.model.province_name(_play.capital_province), _play.capital_province,
		_play.ship_layer.hull_count_all(player),
	])
	_zone = _war_zone(player)
	if _zone < 0:
		_say("no rival coast on any water the crown can reach")
		_finish()
		return
	_rival = _rival_off(_zone, player)
	_say("the water: %s · the rival: %s" % [
		_play.model.sea_zone_name(_zone), FactionCatalog.name_of(_rival),
	])
	if not _sortie_pass(player):
		_finish()
		return
	_prize_pass(player)
	_catch_pass(player)
	_fog_pass()
	_defend_pass()
	_group_pass()
	_blockade_pass()
	_fight_pass()
	_finish()


# --- the reached state ------------------------------------------------------


## The home squadron sorties into the war water, at peace, and takes its station:
## the crossing spends the move, so the drive clears that one field the way a
## turn boundary does — without the AI's own turn in between — and the station
## order is the one a player gives on the next turn.
func _sortie_pass(player: int) -> bool:
	_say("")
	_say("=== sortie: the home squadron to sea ===")
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home == null:
		_say("no home squadron in port at the seat")
		return false
	_say("  in port at %s: %s" % [
		_play.model.province_name(home.province), _named(home),
	])
	_clear_toasts()
	MapPlayCivilianVoyage.sortie(_play, home, _zone)
	_my_toasts()
	_say("  sortie: %s, moved %s, hulls %d" % [
		_station(home), str(home.moved), home.ship_count(),
	])
	var fleet: FleetState = _fleet_by_id(home.id)
	if fleet == null or not fleet.is_afloat() or not fleet.is_at_sea():
		_say("the squadron did not reach the water")
		return false
	fleet.moved = false
	_select(fleet)
	_clear_toasts()
	MapPlayFleetMissions.on_action(_play, "mission:patrol")
	_my_toasts()
	_say("  station order: mission %d, moved %s" % [fleet.mission, str(fleet.moved)])
	_say("  dossier line: \"%s\"" % MapPlayFleetMissions.note(_play, fleet))
	return true


# --- the prize --------------------------------------------------------------


## A patrol with nothing to catch: the water holds no hostile squadron, so the
## catch line is silent and the prize line alone speaks. The cargo a raid reads
## is booked by the market clearing at a turn's close (wiki: § Trade and
## Transport Interception), so one turn passes first, at peace — the turn a
## player has played before the station prices anything. The war comes after it,
## so the turn that books the cargo is not a turn the AI fights over. Then the
## line is read, and the turn it priced is rolled: the cargo the court actually
## took is held to the cargo it was promised.
func _prize_pass(player: int) -> void:
	_say("")
	_say("=== the prize: a station with nothing to catch ===")
	_say("  the water before the turn: %d crown squadron(s), %d rival" % [
		_crown_squadrons(_zone), _rival_squadrons(_zone),
	])
	_run_turn()
	if not _declared_war(player, _rival):
		_declare(player, _rival)
	var fleet: FleetState = _ensure_station()
	if fleet == null:
		_say("no crown station at sea to read")
		return
	_say("  the water after the turn: %d crown squadron(s), %d rival" % [
		_crown_squadrons(_zone), _rival_squadrons(_zone),
	])
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  dossier line: \"%s\"" % line)
	_check("no catch line with an empty water",
		not line.contains("Interception:"), line)
	var prize: String = _segment(line, "Prize:")
	_say("  the prize's own words: \"%s\"" % prize)
	if prize.is_empty():
		_check("a patrol at war prices its raid", false, "no Prize: line")
		return
	var priced: int = _percent(prize)
	var read: Dictionary = _prize_read(fleet)
	var expected: int = int(round(float(read.get("chance", 0.0)) * 100.0))
	_check("the printed chance is the raid's own",
		priced == expected, "printed %d%% · the raid rolls %d%%" % [priced, expected])
	_say("  the cargo the raid reads: %d units" % _cargo_of(_rival))
	# The turn the line priced, through the real closure.
	var victim_before: int = _cargo_of(_rival)
	_raids.clear()
	_run_turn()
	var ours: Array[Dictionary] = _crown_prizes()
	_say("  prizes the crown took: %s" % _prize_rows(ours))
	_say("  %s's cargo afloat: %d -> %d" % [
		FactionCatalog.name_of(_rival), victim_before, _cargo_of(_rival),
	])
	if ours.is_empty():
		_say("  (the roll missed this turn — the chance was %d%%)" % priced)
		return
	var took: int = 0
	for row: Dictionary in ours:
		took += int(row.get("taken", 0))
	var promised: int = _expected_take(prize)
	_check("the cargo taken is the cargo promised", took <= maxi(promised, 1),
		"promised ~%d · took %d" % [promised, took])


# --- the catch --------------------------------------------------------------


## A hostile squadron in the same water: the catch line must price her hulls and
## the pass must roll the same number. The turn that rolls it is the last pass,
## so the state read here is the state fought.
func _catch_pass(player: int) -> void:
	_say("")
	_say("=== the catch: a hostile squadron in the water ===")
	if not _declared_war(_play.player_faction, _rival):
		_declare(_play.player_faction, _rival)
	var fleet: FleetState = _ensure_station()
	if fleet == null:
		_say("no crown station at sea to read")
		return
	var foe: FleetState = _seat_rival(_zone, _rival)
	if foe == null:
		_say("no rival squadron could be seated in the water")
		return
	_make_read(foe, true)
	_say("  %s's squadron in the water: %s (read %s)" % [
		FactionCatalog.name_of(_rival), _named(foe),
		str(MapPlayFleetIntel.strength_read(_play, foe)),
	])
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  dossier line: \"%s\"" % line)
	var catch_line: String = _segment(line, "Interception:")
	_say("  the catch's own words: \"%s\"" % catch_line)
	if catch_line.is_empty():
		_check("a patrol with a hostile in the water prices the catch", false, "no Interception: line")
		return
	var printed: int = _percent(catch_line)
	var hulls: int = _leading_count(catch_line)
	var pass_read: Dictionary = _crown_pass_read(_zone)
	var expected: int = int(round(float(pass_read.get("chance", 0.0)) * 100.0))
	_check("the printed chance is the pass's own",
		printed == expected, "printed %d%% · the pass rolls %d%%" % [printed, expected])
	_check("the hulls named are the hulls in the water",
		hulls == int(pass_read.get("hulls", -1)),
		"printed %d · the water holds %d" % [hulls, int(pass_read.get("hulls", -1))])
	_say("  the station's holders: %d of %d crown squadrons in the water" % [
		int(pass_read.get("holders", 0)), _crown_squadrons(_zone),
	])
	_say("  the panel: %s" % _dossier_lines())


## The pass, rolled: one real turn closes with the hostile squadron in the water
## and the record's own `interception_chance` is held to the line read above.
## Only the crown's own attempt is compared: a record whose attacker is the rival
## rolled the rival's station, not the crown's.
func _fight_pass() -> void:
	_say("")
	_say("=== the pass, rolled: the record's own chance ===")
	var fleet: FleetState = _ensure_station()
	var foe: FleetState = _rival_in_zone()
	if fleet == null or foe == null:
		_say("no contested water left to roll")
		return
	var player: int = _play.player_faction
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	var printed: int = _percent(_segment(line, "Interception:"))
	_say("  the line before the close: \"%s\"" % _segment(line, "Interception:"))
	_battles.clear()
	_run_turn()
	var record: Dictionary = _battle_in(_zone)
	if record.is_empty():
		_say("  (no engagement this turn — the water was not contested at the close)")
		return
	_say("  record: intercepted %s, chance %.3f, attacker %s, defender %s" % [
		str(record.get("intercepted", false)),
		float(record.get("interception_chance", 0.0)),
		FactionCatalog.name_of(int(record.get("attacker", -1))),
		FactionCatalog.name_of(int(record.get("defender", -1))),
	])
	_my_toasts()
	var rolled: int = int(round(float(record.get("interception_chance", 0.0)) * 100.0))
	if printed < 0:
		_say("  the line named no catch at the close")
		return
	if int(record.get("attacker", -1)) != player:
		_say("  the record is the rival's own attempt (%s attacked) — nothing to hold the crown's line to" % [
			FactionCatalog.name_of(int(record.get("attacker", -1))),
		])
		return
	_check("the number the record rolled is the number the line printed",
		rolled == printed, "printed %d%% · record %.3f" % [
			printed, float(record.get("interception_chance", 0.0)),
		])


# --- the fog ----------------------------------------------------------------


## A rival the crown has not read: the line names no number the fog withholds.
func _fog_pass() -> void:
	_say("")
	_say("=== the fog: a squadron the chart has not read ===")
	var fleet: FleetState = _ensure_station()
	var foe: FleetState = _rival_in_zone()
	if fleet == null or foe == null:
		_say("the fight took the station or the rival — nothing to re-read")
		return
	_make_read(foe, false)
	_say("  read now: %s" % str(MapPlayFleetIntel.strength_read(_play, foe)))
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  dossier line: \"%s\"" % line)
	_check("an unread rival withholds the number",
		line.contains("the fog has not read") and not _has_catch(line),
		line)
	_make_read(foe, true)
	var back: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  read again: \"%s\"" % back)
	_check("a read rival gives the number back", _has_catch(back), back)


# --- a station that is not a station ----------------------------------------


## Defend holds the water but rolls no interception and takes no prize: the line
## must say so by printing neither price.
func _defend_pass() -> void:
	_say("")
	_say("=== defend: a squadron that holds a station but works none ===")
	var fleet: FleetState = _ensure_station()
	if fleet == null:
		_say("no crown station left at sea")
		return
	_clear_toasts()
	MapPlayFleetMissions.on_action(_play, "mission:defend")
	_my_toasts()
	_say("  mission %d" % fleet.mission)
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  dossier line: \"%s\"" % line)
	_check("a defending squadron prices no catch", not line.contains("Interception:"), line)
	_check("a defending squadron prices no prize", not line.contains("Prize:"), line)
	# Back to patrol for the group read: the order spends the move, so the drive
	# clears that one field the way the next turn would.
	fleet.moved = false
	_clear_toasts()
	MapPlayFleetMissions.on_action(_play, "mission:patrol")
	_my_toasts()
	_say("  back on patrol: mission %d" % fleet.mission)


# --- the group --------------------------------------------------------------


## Two of the crown's stations in one water roll as one group: the line must
## price both, not the squadron in hand alone.
func _group_pass() -> void:
	_say("")
	_say("=== the group: two stations in one water ===")
	var fleet: FleetState = _ensure_station()
	var foe: FleetState = _rival_in_zone()
	if fleet == null or foe == null:
		_say("no pair left to read the group on")
		return
	var alone: int = int(round(
		float(_crown_pass_read(_zone).get("chance", 0.0)) * 100.0
	))
	var mate: FleetState = FleetState.at_sea(
		_play.ship_layer.next_hull + 70, _play.player_faction, _zone,
		["playtest_mate_1", "playtest_mate_2"],
		{"playtest_mate_1": "galleon", "playtest_mate_2": "galleon"}
	)
	mate.mission = FleetState.Mission.PATROL
	_play.ship_layer.fleets.append(mate)
	_play.ship_layer.rebuild_markers()
	_say("  a second station joins the water (fixture): %s" % _named(mate))
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  dossier line: \"%s\"" % line)
	var printed: int = _percent(_segment(line, "Interception:"))
	var grouped: int = int(round(
		float(_crown_pass_read(_zone).get("chance", 0.0)) * 100.0
	))
	_say("  the pass over the group: %d%% (one station alone read %d%%)" % [grouped, alone])
	_check("the line prices the group the pass rolls", printed == grouped,
		"printed %d%% · the group rolls %d%%" % [printed, grouped])


# --- a blockade -------------------------------------------------------------


## A blockade's station line names the coast it holds, so its price must not name
## that coast again (wiki: § Trade and Transport Interception; the patrol's line
## names the coast it works because its station note names none).
func _blockade_pass() -> void:
	_say("")
	_say("=== a blockade: the coast the station already names ===")
	var fleet: FleetState = _ensure_station()
	if fleet == null:
		_say("no crown station to blockade with")
		return
	_select(fleet)
	fleet.moved = false
	var targets: Array[int] = FleetMissions.blockade_targets(
		_play.model, fleet, _hostile()
	)
	_say("  blockade targets from %s: %s" % [
		_play.model.sea_zone_name(fleet.sea_zone), str(targets),
	])
	if targets.is_empty():
		_say("  no hostile coast borders this water — nothing to blockade")
		return
	_clear_toasts()
	MapPlayFleetMissions.on_action(_play, "mission:blockade:%d" % targets[0])
	_my_toasts()
	_say("  mission %d on %s" % [fleet.mission, _play.model.province_name(targets[0])])
	var line: String = MapPlayFleetMissions.note(_play, fleet)
	_say("  dossier line: \"%s\"" % line)
	var prize: String = _segment(line, "Prize:")
	_say("  the prize's own words: \"%s\"" % prize)
	_check("a blockade names no coast its station note already names",
		not prize.contains(" off "), prize)
	_check("a blockade prices its prize", not prize.is_empty() and _percent(prize) >= 0, prize)
	# Back on patrol for the fight this drive ends on.
	fleet.moved = false
	_clear_toasts()
	MapPlayFleetMissions.on_action(_play, "mission:patrol")
	_my_toasts()
	_say("  back on patrol: mission %d" % fleet.mission)


# --- the reads --------------------------------------------------------------


## The catch the combat pass rolls for the crown's own station: the same holders,
## the same targets, the same mission, read the same way `attacker_owner` reads
## them for the crown (`NavalInterception.chance`).
func _crown_pass_read(zone: int) -> Dictionary:
	var group: Array = []
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != _play.player_faction or not fleet.is_at_sea():
			continue
		if fleet.sea_zone != zone or not fleet.is_afloat():
			continue
		group.append(fleet)
	var holders: Array = NavalInterception.station_holders(_play.model, group, _hostile())
	var targets: Array = []
	var hulls: int = 0
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction or not fleet.is_at_sea():
			continue
		if fleet.sea_zone != zone or not fleet.is_afloat():
			continue
		if not Hostility.between(_hostile(), _play.player_faction, fleet.owner):
			continue
		targets.append(fleet)
		hulls += fleet.ship_count()
	var mission: int = FleetMissions.station_mission(_play.model, group, _hostile())
	return {
		"chance": NavalInterception.chance(holders, targets, mission, _play.has_tech),
		"hulls": hulls, "holders": holders.size(), "targets": targets.size(),
		"mission": mission,
	}


## The prize the rules roll for the station's water: the group, the victim's
## home fleet, its imports and the station's own mission, read through the same
## `NavalRaid.preview` the dossier asks.
func _prize_read(fleet: FleetState) -> Dictionary:
	var group: Array = NavalRaid.station_group(
		_play.model, _play.ship_layer.fleets, fleet.sea_zone, fleet.owner, _hostile()
	)
	if group.is_empty():
		group = [fleet]
	var mission: int = FleetMissions.station_mission(_play.model, group, _hostile())
	var best: Dictionary = {}
	for province_id: int in _prize_coasts(fleet):
		var owner: int = _play.model.province_owner(province_id)
		var imports: Dictionary = _play.economy.market.imports_for(owner)
		if imports.is_empty():
			continue
		var home: FleetState = MapPlayRaids.home_fleet(_play, owner)
		if home == null:
			continue
		var odds: Dictionary = NavalRaid.preview(
			group, home, imports, mission, _play.has_tech
		)
		if best.is_empty() or float(odds.get("chance", 0.0)) > float(best.get("chance", 0.0)):
			best = odds
	return best


func _prize_coasts(fleet: FleetState) -> Array[int]:
	var coasts: Array[int] = []
	if fleet.mission == FleetState.Mission.BLOCKADE and fleet.blockade_province >= 0:
		coasts.append(fleet.blockade_province)
	for province_id: int in NavalMovement.provinces_by_zone(_play.model, fleet.sea_zone):
		if coasts.has(province_id):
			continue
		var owner: int = _play.model.province_owner(province_id)
		if owner < 0 or owner == fleet.owner:
			continue
		if not Hostility.between(_hostile(), fleet.owner, owner):
			continue
		coasts.append(province_id)
	return coasts


# --- the fog's own switch ---------------------------------------------------


## Sets the crown's watch on one rival squadron: read when `read` is true (seen
## on an earlier turn and still under the eye), unread otherwise (seen this turn
## only). The same two readings a turn boundary gives a player.
func _make_read(fleet: FleetState, read: bool) -> void:
	var region: int = _play.region_index
	_play.naval_intel.observe([], _play.turn, region)
	if read:
		_play.naval_intel.observe([fleet.id], _play.turn - 1, region)
		_play.naval_intel.observe([fleet.id], _play.turn, region)
	else:
		_play.naval_intel.observe([fleet.id], _play.turn, region)


# --- seats ------------------------------------------------------------------


## Moves an existing rival squadron into the water rather than minting one, so
## hull ids and names stay the campaign's own.
func _seat_rival(zone: int, rival: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == rival and fleet.is_afloat():
			fleet.location = FleetState.Location.AT_SEA
			fleet.sea_zone = zone
			fleet.province = MapModel.NO_ID
			fleet.clear_beachhead()
			fleet.moved = true
			fleet.mission = FleetState.Mission.MOVE
			_play.ship_layer.rebuild_markers()
			return fleet
	var seated: FleetState = FleetState.at_sea(
		_play.ship_layer.next_hull + 50, rival, zone,
		["playtest_foe_1", "playtest_foe_2"],
		{"playtest_foe_1": "frigate", "playtest_foe_2": "frigate"}
	)
	_play.ship_layer.fleets.append(seated)
	_play.ship_layer.rebuild_markers()
	return seated


func _crown_station() -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction and fleet.is_at_sea() \
				and fleet.is_afloat() and fleet.sea_zone == _zone:
			return fleet
	return null


func _rival_in_zone() -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _rival and fleet.is_at_sea() \
				and fleet.is_afloat() and fleet.sea_zone == _zone:
			return fleet
	return null


## The crown's station in the water, or the same squadron sailed back and given
## its station again — a retreat can take her out of the water the drive prices
## (a beaten squadron withdraws to safe adjacent water, wiki: ships-and-naval
## § Naval Retreat). A court with no squadron left is handed one only as a last
## fixture, so a read always has a station to read.
func _ensure_station() -> FleetState:
	var station: FleetState = _crown_station()
	if station != null:
		return station
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != _play.player_faction or not fleet.is_afloat():
			continue
		_say("  the station is not in this water (%s) — sailed back (fixture)" % _station(fleet))
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = _zone
		fleet.province = MapModel.NO_ID
		fleet.clear_beachhead()
		fleet.moved = false
		fleet.mission = FleetState.Mission.PATROL
		_play.ship_layer.rebuild_markers()
		return fleet
	var seated: FleetState = FleetState.at_sea(
		_play.ship_layer.next_hull + 90, _play.player_faction, _zone,
		["playtest_station_1", "playtest_station_2", "playtest_station_3"],
		{
			"playtest_station_1": "galleon",
			"playtest_station_2": "galleon",
			"playtest_station_3": "frigate",
		}
	)
	seated.mission = FleetState.Mission.PATROL
	_play.ship_layer.fleets.append(seated)
	_play.ship_layer.rebuild_markers()
	_say("  no crown squadron afloat — one seated at the station (fixture)")
	return seated


## How many of the crown's squadrons stand in the water.
func _crown_squadrons(zone: int) -> int:
	var count: int = 0
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != _play.player_faction or not fleet.is_at_sea():
			continue
		if fleet.sea_zone == zone and fleet.is_afloat():
			count += 1
	return count


## How many squadrons of any court the crown is at war with stand in the water.
func _rival_squadrons(zone: int) -> int:
	var count: int = 0
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner == _play.player_faction or not fleet.is_at_sea():
			continue
		if fleet.sea_zone != zone or not fleet.is_afloat():
			continue
		if not Hostility.between(_hostile(), _play.player_faction, fleet.owner):
			continue
		count += 1
	return count


## The dossier panel's own station line, as the panel prints it.
func _dossier_lines() -> String:
	var fleet: FleetState = _crown_station()
	if fleet == null:
		return "no station"
	_select(fleet)
	var panel: FleetPanel = _play.hud.panels.fleet_panel
	if panel == null or not panel.visible:
		return "no fleet dossier shown"
	var station: PackedStringArray = PackedStringArray()
	for text: String in _labels(panel):
		if text.contains("Interception:") or text.contains("Prize:") \
				or text.contains("On patrol") or text.contains("Blockading") \
				or text.contains("Holding station"):
			station.append(text)
	return " / ".join(station) if not station.is_empty() else "no station line"


# --- turn -------------------------------------------------------------------


## One whole turn through the real closure, answering whatever the court asks.
func _run_turn() -> void:
	var turn: int = _play.turn
	_clear_toasts()
	MapPlayTurn.end_turn(_play)
	var guard: int = 0
	while _play.turn == turn and not _play.campaign_over() and guard < 12:
		guard += 1
		if CallToArms.has_pending(_play.diplomacy, _play.player_faction):
			_say("  court asks: call to arms — stood aside")
			MapPlayTurn.answer_call(_play, false)
		elif Intervention.has_pending(_play.diplomacy, _play.player_faction):
			_say("  court asks: intervention — did nothing")
			MapPlayTurn.answer_intervention(_play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(_play.diplomacy, _play.player_faction):
			_say("  court asks: a proposal — refused")
			MapPlayTurn.answer_offer(_play, false)
		else:
			break
	_say("  calendar: turn %d -> %d" % [turn, _play.turn])


func _on_battle(battles: Array[Dictionary]) -> void:
	_battles.append_array(battles)


func _on_raid(raids: Array[Dictionary]) -> void:
	_raids.append_array(raids)


func _battle_in(zone: int) -> Dictionary:
	for battle: Dictionary in _battles:
		if int(battle.get("zone", -1)) == zone:
			return battle
	return {}


func _crown_prizes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raid: Dictionary in _raids:
		if int(raid.get("raider", -1)) == _play.player_faction:
			rows.append(raid)
	return rows


## Units of cargo the rival's court has afloat this turn — the stock a raid skims.
func _cargo_of(faction: int) -> int:
	if _play.economy == null or _play.economy.market == null:
		return 0
	return NavalRaid.total_of(_play.economy.market.imports_for(faction))


# --- words ------------------------------------------------------------------


## From `prefix` to the next full stop: one price's own sentence.
func _segment(line: String, prefix: String) -> String:
	var at: int = line.find(prefix)
	if at < 0:
		return ""
	var rest: String = line.substr(at)
	var stop: int = rest.find(".")
	return rest if stop < 0 else rest.substr(0, stop + 1)


## True when the line carries a priced catch (`Interception: 30% …`).
func _has_catch(line: String) -> bool:
	var seg: String = _segment(line, "Interception:")
	return not seg.is_empty() and _percent(seg) >= 0


## The first whole percentage in a line (`62%`).
func _percent(line: String) -> int:
	var at: int = line.find("%")
	if at < 0:
		return -1
	var digits: String = ""
	var index: int = at - 1
	while index >= 0 and line[index] >= "0" and line[index] <= "9":
		digits = line[index] + digits
		index -= 1
	return int(digits) if not digits.is_empty() else -1


## The hull count a catch line names (`to catch 4 hulls`) — `-1` when it names none.
func _leading_count(line: String) -> int:
	var at: int = line.find("to catch ")
	if at < 0:
		return -1
	var rest: String = line.substr(at + 9)
	var count: int = 0
	for index in rest.length():
		var ch: String = rest[index]
		if ch < "0" or ch > "9":
			break
		count = count * 10 + int(ch)
	return count


## The cargo a prize line promises (`to take ~3 cargo`).
func _expected_take(line: String) -> int:
	var at: int = line.find("to take ~")
	if at < 0:
		return 0
	var rest: String = line.substr(at + 9)
	var count: int = 0
	for index in rest.length():
		var ch: String = rest[index]
		if ch < "0" or ch > "9":
			break
		count = count * 10 + int(ch)
	return count


func _check(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	_say("  %s %s — %s" % ["ok  " if ok else "FAIL", label, detail])


# --- world helpers ----------------------------------------------------------


## The water the crown will fight on: a zone a sortie can reach that borders a
## rival Great Power's coast.
func _war_zone(player: int) -> int:
	var home: FleetState = _play.ship_layer.home_fleet(_play.capital_province)
	if home != null:
		var crew: Dictionary = MapPlayCivilianVoyage.crew(_play, home)
		for raw: Variant in crew.get("sortie", []):
			var zone: int = int((raw as Dictionary)["zone"])
			if _rival_off(zone, player) >= 0:
				return zone
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.owner != player or not fleet.is_afloat():
			continue
		var zone: int = fleet.sea_zone if fleet.is_at_sea() else _zone_beside(fleet.province)
		if zone >= 0 and _rival_off(zone, player) >= 0:
			return zone
	return -1


func _declared_war(player: int, rival: int) -> bool:
	return DiplomacyRules.at_war_with(_play.diplomacy, player, rival)


func _declare(player: int, rival: int) -> void:
	_say("")
	_say("--- war on %s ---" % FactionCatalog.name_of(rival))
	if _declared_war(player, rival):
		_say("  already at war")
		return
	var war: Dictionary = DiplomacyRules.declare_war(_play.diplomacy, player, rival)
	_say("  %s" % (
		"declared" if bool(war.get("ok", false)) else String(war.get("reason", "refused"))
	))


func _hostile() -> Callable:
	return func(a: int, b: int) -> bool:
		return DiplomacyRules.at_war_with(_play.diplomacy, a, b)


func _rival_off(zone: int, player: int) -> int:
	for province_id: int in NavalMovement.provinces_by_zone(_play.model, zone):
		var owner: int = _play.model.province_owner(province_id)
		if owner == player or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.great_power_ids().has(owner):
			return owner
	return -1


func _zone_beside(province: int) -> int:
	var zones: Array[int] = NavalMovement.province_sea_zones(_play.model, province)
	return zones[0] if not zones.is_empty() else -1


func _fleet_by_id(fleet_id: int) -> FleetState:
	for fleet: FleetState in _play.ship_layer.fleets:
		if fleet.id == fleet_id:
			return fleet
	return null


func _select(fleet: FleetState) -> void:
	var ship: Ship = _play.ship_layer.ship_for(fleet)
	if ship == null:
		_say("  no marker on the chart for fleet %d" % fleet.id)
		return
	_play.ship_layer.select(ship)
	MapPlayFleets.select(_play, ship)


func _station(fleet: FleetState) -> String:
	if fleet == null:
		return "nowhere"
	if fleet.is_at_sea():
		return "sea %s" % _play.model.sea_zone_name(fleet.sea_zone)
	return "port %s" % _play.model.province_name(fleet.province)


func _named(fleet: FleetState) -> String:
	if fleet == null:
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	for hull_id: String in fleet.hulls:
		parts.append("%s %s" % [hull_id, ShipNames.of(fleet, hull_id)])
	return "none" if parts.is_empty() else ", ".join(parts)


func _prize_rows(raids: Array[Dictionary]) -> String:
	if raids.is_empty():
		return "none"
	var parts: PackedStringArray = PackedStringArray()
	for raid: Dictionary in raids:
		parts.append("%s %d cargo on %.0f%%, hull %s" % [
			_play.model.sea_zone_name(int(raid.get("zone", -1))),
			int(raid.get("taken", raid.get("lost_total", 0))),
			float(raid.get("chance", 0.0)) * 100.0,
			str(raid.get("hull", "-")),
		])
	return "; ".join(parts)


func _my_toasts() -> void:
	for panel: Node in _play.hud._toast_box.get_children():
		if panel.is_queued_for_deletion():
			continue
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if lower.contains("fleet") or lower.contains("squadron") \
					or lower.contains("hull") or lower.contains("prize") \
					or lower.contains("cargo") or lower.contains("raid") \
					or lower.contains("intercept") or lower.contains("sea "):
				_say("    toast: %s" % text)


func _clear_toasts() -> void:
	for child: Node in _play.hud._toast_box.get_children():
		child.queue_free()


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		out.append_array(_labels(child))
	return out


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_station_prices: %d steps, %d checks, %d failed ---" % [
		_steps.size(), _checks, _failed,
	])
	quit()
