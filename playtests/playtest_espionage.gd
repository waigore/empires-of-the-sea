extends SceneTree
## Headless free-playtest drive for espionage (wiki: civilian-units § Spy;
## DR-20261110-03, DR-20261110-07): reaches a mid-age starting position with
## spies on the roster, despatch one across a border, ends a real turn and
## prints what the court is actually told — the civilian dossier, the ledger's
## research line, presence reveal, the toast and the court panel's despatch.
## Then it exercises counter-espionage over several resolutions and the minor
## court a spy can shadow. Not a CI gate — run it by hand:
##   godot --headless --path . --script res://playtests/playtest_espionage.gd
##
## The spies are seated by the harness (a scenario seat, the same one rules
## tests use); movement, resolution, presentation and the HUD are the real ones.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
## Turn 100 hands the crown two spies and a treasury (wiki: advanced-starts).
const ADVANCED: String = "turns100"
const SPY: String = "spy"

var _steps: PackedStringArray = PackedStringArray()
var _screen: MapScreen = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await _open_game()
	if _screen == null:
		_finish()
		return
	var play: PlaySession = _screen.play
	var player: int = play.player_faction
	_say("seed %s · %s · turn %d · player %s" % [
		SEED_TEXT, ADVANCED, play.turn, FactionCatalog.name_of(player),
	])
	var spies: Array[CivilianState] = _spies(play, player)
	_say("roster: %d civilian(s), %d spy/spies" % [
		play.civilian_layer.unit_count_all(player), spies.size(),
	])
	if spies.is_empty():
		_say("no spy on the roster — the drive cannot reach the area")
		_finish()
		return
	_home_pass(play, spies[0])
	var rival: int = _rival(play, player)
	if rival >= 0:
		_abroad_pass(play, spies[0], rival)
		if spies[0].tile != CivilianState.NO_TILE:
			var foreign: Vector2i = spies[0].tile
			_turn_pass(play, rival, foreign)
			_share_pass(play, rival)
			_leave_pass(play, foreign)
	else:
		_say("no rival Great Power on this world")
	if spies.size() > 1:
		_screen_pass(play, spies[1])
	_minor_pass(play, spies[0], player)
	_finish()


# --- passes -----------------------------------------------------------------


## The idle spy at home: what the dossier claims before any order is given.
func _home_pass(play: PlaySession, spy: CivilianState) -> void:
	_say("")
	_say("--- dossier: spy at home on crown land ---")
	_show_panel(play, spy)


## Despatch: the spy walks over a border into a rival Great Power's province.
func _abroad_pass(play: PlaySession, spy: CivilianState, rival: int) -> void:
	_say("")
	_say("--- despatch: cross into %s ---" % FactionCatalog.name_of(rival))
	var seat: Dictionary = _border_seat(play, spy.owner, rival)
	if seat.is_empty():
		var tile: Vector2i = _any_land(play, rival)
		if tile == CivilianState.NO_TILE:
			return
		_say("no rival province borders crown land — seated on rival land instead")
		spy.tile = tile
		spy.moved = true
	else:
		var from: Vector2i = seat["from"]
		var to: Vector2i = seat["to"]
		spy.tile = from
		spy.moved = false
		var province: int = play.model.province_at(to.x, to.y)
		var result: Dictionary = CivilianMovement.apply_move(
			play.model, spy, to, play.visibility
		)
		_say("march into %s: %s" % [
			play.model.province_name(province),
			"allowed — no declaration, no war" if bool(result.get("ok", false))
			else String(result.get("reason", "refused")),
		])
		if not bool(result.get("ok", false)):
			return
	_show_panel(play, spy)


## The whole turn: resolution, presence reveal and the despatch the court keeps.
func _turn_pass(play: PlaySession, rival: int, foreign: Vector2i) -> void:
	_say("")
	_say("--- end of turn ---")
	var province: int = play.model.province_at(foreign.x, foreign.y)
	var before: int = play.visibility.province_visibility(province)
	_clear_toasts()
	_run_turn(play)
	_say("presence: %s visibility %d -> %d" % [
		play.model.province_name(province), before,
		play.visibility.province_visibility(province),
	])
	_despatch(play, rival)


## The share is only due once a rival knows a tech the crown does not. The
## advanced start hands every court the same fixed list, so the drive seeds the
## rival's ledger with one tech the crown can study — a fixture step, like a
## seated army, not a rule.
func _share_pass(play: PlaySession, rival: int) -> void:
	_say("")
	_say("--- research share ---")
	var tech: String = _study_rival_tech(play, rival)
	if tech.is_empty():
		_say("no tech the crown could study — nothing to measure")
		return
	var before: int = play.economy.economy.research.progress_of(tech)
	_say("studying %s, which %s already knows (progress %d)" % [
		TechCatalog.display_name(tech), FactionCatalog.name_of(rival), before,
	])
	_clear_toasts()
	_run_turn(play)
	_say("progress after one turn: %d -> %d" % [
		before, play.economy.economy.research.progress_of(tech),
	])
	_boost_pass(play)
	_my_toasts()


## Leaving the last spy must fog the province again at the end of that turn
## (wiki: civilian-units § Spy (1): no grace timer).
func _leave_pass(play: PlaySession, foreign: Vector2i) -> void:
	_say("")
	var spies: Array[CivilianState] = _spies(play, play.player_faction)
	if spies.is_empty():
		return
	var province: int = play.model.province_at(foreign.x, foreign.y)
	_say("--- withdraw: the last spy leaves %s ---" % play.model.province_name(province))
	var before: int = play.visibility.province_visibility(province)
	spies[0].tile = _any_land(play, play.player_faction)
	spies[0].moved = true
	_run_turn(play)
	_say("presence after leaving: %d -> %d" % [
		before, play.visibility.province_visibility(province),
	])


## Runs one whole turn, answering whatever the court is asked on the way.
func _run_turn(play: PlaySession) -> void:
	var turn: int = play.turn
	var started: int = Time.get_ticks_msec()
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn == turn and not play.campaign_over() and guard < 12:
		guard += 1
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			_say("  court asks: call to arms — stood aside")
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			_say("  court asks: intervention — did nothing")
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			_say("  court asks: a proposal — refused")
			MapPlayTurn.answer_offer(play, false)
		else:
			break
	_say("calendar: turn %d -> %d (%d ms), %d spy/spies left" % [
		turn, play.turn, Time.get_ticks_msec() - started,
		_spies(play, play.player_faction).size(),
	])
	_my_toasts()


## The share the spies actually earn, and the research panel the player opens.
func _boost_pass(play: PlaySession) -> void:
	var boost: Dictionary = MapPlayEspionage.research_boost(play)
	if boost.is_empty():
		_say("research share: none — no spy on a rival Great Power's land")
	else:
		_say("research share: %d tech(s) +%d%%" % [
			boost.size(), SpyNetworks.BOOST_PERCENT,
		])
	play.economy.open_research()
	var panel: ResearchPanel = play.hud.panels.research_panel
	for node: Node in panel._slots_body.get_children():
		var texts: Array[String] = _labels(node)
		if not " RP" in " | ".join(texts):
			continue
		_say("  research row: %s" % " | ".join(texts))
	play.hud.panels.hide_research()


## Counter-espionage: the screen goes up and stays up, and the dice are hunted
## for as many resolutions as a hand drive can afford.
func _screen_pass(play: PlaySession, spy: CivilianState) -> void:
	_say("")
	_say("--- counter-espionage ---")
	var home: Vector2i = _any_land(play, spy.owner)
	if home == CivilianState.NO_TILE:
		_say("no crown land to keep the screen on")
		return
	spy.tile = home
	spy.moved = true
	var assigned: Dictionary = CivilianWork.assign(
		play.model, spy, SpyRules.WORK_COUNTER, play.land_works,
		play.civilian_layer.units, play.stockpile()
	)
	_say("order counter_spy: %s" % ("legal" if bool(assigned.get("ok", false))
		else String(assigned.get("reason", "refused"))))
	if not bool(assigned.get("ok", false)):
		return
	_show_panel(play, spy)
	var rival: int = _rival(play, spy.owner)
	if rival < 0:
		return
	var intruder: CivilianState = play.civilian_layer.add_unit(
		rival, SPY, _any_land(play, spy.owner)
	)
	_say("screen up; hunting a %s spy for 20 resolutions" % FactionCatalog.name_of(rival))
	var found: int = 0
	for step in 20:
		var roster: Array[CivilianState] = [spy, intruder]
		var events: Array[Dictionary] = SpyRules.resolve_turn(
			play.model, roster, play.turn + step, play.map_seed
		)
		for event: Dictionary in events:
			found += 1
			_say("resolution +%d: %s in %s" % [
				step + 1, String(event.get("kind", "?")),
				play.model.province_name(int(event.get("province", -1))),
			])
		if found > 0:
			return
	_say("no kill or defection in 20 resolutions (5%/10% rolls)")


## A Minor Nation is never a qualifying rival, so its dossier must not promise
## a research share (wiki: civilian-units § Spy; DR-20261110-03).
func _minor_pass(play: PlaySession, spy: CivilianState, player: int) -> void:
	_say("")
	var minor: int = _minor(play, player)
	if minor < 0:
		_say("--- minor court: none on this world ---")
		return
	var tile: Vector2i = _any_land(play, minor)
	if tile == CivilianState.NO_TILE:
		return
	_say("--- dossier: spy on %s land ---" % FactionCatalog.name_of(minor))
	spy.tile = tile
	spy.moved = true
	_show_panel(play, spy)


# --- presentation -----------------------------------------------------------


func _show_panel(play: PlaySession, spy: CivilianState) -> void:
	play.civilian_layer.select(spy)
	MapPlayCivilians.refresh_panel(play)
	for line: String in _labels(play.hud.panels.civilian_panel):
		_say("  dossier: %s" % line)


## The toast the court actually saw, then the despatch it can read again.
func _despatch(play: PlaySession, rival: int) -> void:
	var reports: Dictionary = play.court_reports
	if reports.is_empty():
		_say("court panel: no despatch kept")
		return
	var panel := CourtReportsPanel.new()
	_screen.add_child(panel)
	panel.fill(rival, reports)
	var lines: Array[String] = _labels(panel)
	if lines.is_empty():
		_say("court panel: %s has no section" % FactionCatalog.name_of(rival))
	else:
		for line: String in lines:
			_say("  court panel: %s" % line)
	panel.queue_free()


## Only the toasts this area emits, so a turn's noise does not bury them.
func _my_toasts() -> void:
	for panel: Node in _screen.play.hud._toast_box.get_children():
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if lower.contains("spy") or lower.contains("quickened") or lower.contains("turn "):
				_say("  toast: %s" % text)


func _clear_toasts() -> void:
	for child: Node in _screen.play.hud._toast_box.get_children():
		child.queue_free()


# --- world helpers ----------------------------------------------------------


## A rival Great Power near enough to share a land border with crown land: the
## tile to walk from and the tile to walk into.
func _border_seat(play: PlaySession, player: int, rival: int) -> Dictionary:
	for y in play.model.height:
		for x in play.model.width:
			var tile := Vector2i(x, y)
			if play.model.owner_at(x, y) != rival or not play.model.is_land(x, y):
				continue
			for offset: Vector2i in CivilianMovement.NEIGHBORS:
				var from: Vector2i = tile + offset
				if not play.model.in_bounds(from.x, from.y):
					continue
				if play.model.owner_at(from.x, from.y) != player:
					continue
				if not play.model.is_land(from.x, from.y):
					continue
				return {"from": from, "to": tile}
	return {}


func _any_land(play: PlaySession, owner: int) -> Vector2i:
	for y in play.model.height:
		for x in play.model.width:
			if play.model.owner_at(x, y) == owner and play.model.is_land(x, y):
				return Vector2i(x, y)
	return CivilianState.NO_TILE


## A tech the crown lacks that the rival can be seeded with knowing (fixture).
func _study_rival_tech(play: PlaySession, rival: int) -> String:
	if play.economy == null or play.ai == null:
		return ""
	var ledger: PlayerEconomy = play.ai.economy_for(rival)
	if ledger == null:
		return ""
	for id: String in TechCatalog.ids():
		if play.has_tech(play.player_faction, id):
			continue
		var assigned: Dictionary = play.economy.economy.research.assign(id)
		if not bool(assigned.get("ok", false)):
			continue
		ledger.tech_unlocked[id] = true
		return id
	return ""


func _spies(play: PlaySession, player: int) -> Array[CivilianState]:
	var found: Array[CivilianState] = []
	for unit: CivilianState in play.civilian_layer.units:
		if unit.owner == player and unit.type_id == SPY:
			found.append(unit)
	return found


func _rival(play: PlaySession, player: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != player and _any_land(play, faction) != CivilianState.NO_TILE:
			return faction
	return -1


func _minor(play: PlaySession, player: int) -> int:
	for faction: int in FactionCatalog.minor_ids():
		if faction != player and _any_land(play, faction) != CivilianState.NO_TILE:
			return faction
	return -1


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		out.append_array(_labels(child))
	return out


# --- setup ------------------------------------------------------------------


func _open_game() -> MapScreen:
	return await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, ADVANCED)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	printerr("playtest: finishing")
	print("\n--- playtest_espionage: %d steps ---" % _steps.size())
	quit()
