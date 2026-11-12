extends SceneTree
## Headless free-playtest drive for the rival half of espionage (wiki:
## civilian-units § Spy (3)(4); diplomacy § Spy-death penalty): the spies the AI
## courts send into the human's land, the counter-espionage screen the crown
## keeps at home, and what the human is actually told about either.
##
## Not a CI gate — run it by hand:
##   godot --headless --path . --script res://tests/playtest_ai_spycraft.gd

const Launch = preload("res://tests/playtest_launch.gd")
const SEED_TEXT: String = "1500"
const SETUP_SIZE_INDEX: int = 0
const ADVANCED: String = "turns100"
const SPY: String = "spy"
const MAX_TURNS: int = 6

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
	_inventory(play, player)
	_watch_pass(play, player)
	_screen_pass(play, player)
	_theft_pass(play, player)
	_finish()


## Who holds spies, and where they stand.
func _inventory(play: PlaySession, player: int) -> void:
	_say("")
	_say("--- spy inventory ---")
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		var roster: Array[CivilianState] = _roster(play, region)
		var counts: Dictionary = {}
		for unit: CivilianState in roster:
			if unit.type_id != SPY:
				continue
			counts[unit.owner] = int(counts.get(unit.owner, 0)) + 1
		for owner: Variant in counts.keys():
			_say("  region %d: %s holds %d spy/spies" % [
				region, FactionCatalog.name_of(int(owner)), int(counts[owner]),
			])
		for unit: CivilianState in roster:
			if unit.type_id != SPY:
				continue
			var host: int = model.owner_at(unit.tile.x, unit.tile.y)
			_say("    %s spy at %s on %s land%s" % [
				FactionCatalog.name_of(unit.owner), unit.tile,
				FactionCatalog.name_of(host),
				" (foreign)" if SpyRules.is_foreign(model, unit) else "",
			])


## Play real turns and watch what the rival spies do to the human's land.
func _watch_pass(play: PlaySession, player: int) -> void:
	_say("")
	_say("--- rival spies against the crown, no screen up ---")
	for step in MAX_TURNS:
		_clear_toasts()
		_run_turn(play)
		var intruders: int = 0
		for region in play.world.region_count():
			var model: MapModel = play.world.region(region)
			if model == null:
				continue
			for unit: CivilianState in _roster(play, region):
				if unit.type_id != SPY or unit.owner == player:
					continue
				if model.owner_at(unit.tile.x, unit.tile.y) == player:
					intruders += 1
		_say("turn %d: %d rival spy/spies on crown land" % [play.turn, intruders])
		_my_toasts()
		if play.campaign_over():
			_say("campaign over")
			return


## The crown keeps a screen at home and plays on: what the court is told when a
## rival spy is caught, and whether the order survives the turns.
func _screen_pass(play: PlaySession, player: int) -> void:
	_say("")
	_say("--- counter-espionage screen ---")
	var spy: CivilianState = _home_spy(play, player)
	if spy == null:
		_say("no spy at home — the drive cannot raise a screen")
		return
	var assigned: Dictionary = CivilianWork.assign(
		play.model, spy, SpyRules.WORK_COUNTER, play.land_works,
		play.civilian_layer.units, play.stockpile()
	)
	_say("order counter_spy: %s" % (
		"legal" if bool(assigned.get("ok", false))
		else String(assigned.get("reason", "refused"))
	))
	if not bool(assigned.get("ok", false)):
		return
	play.civilian_layer.select(spy)
	MapPlayCivilians.refresh_panel(play)
	for line: String in _labels(play.hud.panels.civilian_panel):
		_say("  dossier: %s" % line)
	var caught: int = 0
	var kills: int = 0
	var turns: int = 40
	for step in turns:
		_clear_toasts()
		# A rival agent already ashore is a state, not a rule: the dice still
		# decide whether the screen takes it, and the turn is the real one.
		var seated: int = 0
		while _intruders(play, player) < 3 and seated < 3:
			_seat_intruder(play, player)
			seated += 1
		var before: Dictionary = _relations(play, player)
		var spies_before: int = _crown_spies(play, player)
		_run_turn(play)
		var intruders: int = _intruders(play, player)
		_say("turn %d: %d rival spy/spies on crown land, screen %s" % [
			play.turn, intruders,
			"up" if SpyRules.has_counter_spy(play.civilian_layer.units, player) else "gone",
		])
		_my_toasts()
		caught += _caught_this_turn()
		for faction: Variant in _relations(play, player).keys():
			var score: int = int(_relations(play, play.player_faction)[faction])
			var was: int = int(before.get(faction, score))
			if score != was:
				kills += 1
				_say("  relations %s: %d -> %d" % [
					FactionCatalog.name_of(int(faction)), was, score,
				])
				_chronicle(play, player, int(faction))
		if _crown_spies(play, player) > spies_before:
			_turned_pass(play, player)
		if kills > 0 and caught > kills:
			break
		if play.campaign_over():
			_say("campaign over")
			return
	_say("events in %d turns: %d heard, %d with a relation cost" % [turns, caught, kills])


## What the court's own history page says about the pair afterwards.
func _chronicle(play: PlaySession, player: int, other: int) -> void:
	var lines: Array[Dictionary] = DiplomacyHistory.entries(play.diplomacy, player, other)
	var shown: int = 0
	for line: Dictionary in lines:
		_say("  chronicle: %s" % String(line.get("text", "")))
		shown += 1
		if shown >= 3:
			return
	if shown == 0:
		_say("  chronicle: nothing recorded with %s" % FactionCatalog.name_of(other))


## A spy that came over: is it on the roster, and does its dossier read right?
func _turned_pass(play: PlaySession, player: int) -> void:
	var turned: CivilianState = null
	for unit: CivilianState in play.civilian_layer.units:
		if unit.owner == player and unit.type_id == SPY and unit.moved:
			turned = unit
	if turned == null:
		_say("  turned spy: not in the shown region's roster")
		return
	_say("  turned spy: id %d at %s, on %s land, work %s" % [
		turned.id, turned.tile,
		FactionCatalog.name_of(play.model.owner_at(turned.tile.x, turned.tile.y)),
		turned.work_action() if turned.is_working() else "none",
	])
	play.civilian_layer.select(turned)
	MapPlayCivilians.refresh_panel(play)
	for line: String in _labels(play.hud.panels.civilian_panel):
		_say("  dossier: %s" % line)


## What the rival courts take from the crown's own studies: a spy of theirs on
## crown land earns them a share of every tech the crown already knows.
func _theft_pass(play: PlaySession, player: int) -> void:
	_say("")
	_say("--- rival research share from crown land ---")
	if play.ai == null:
		_say("no rival ledgers")
		return
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		var ledger: PlayerEconomy = play.ai.economy_for(faction)
		if ledger == null:
			continue
		var bonus: Dictionary = MapPlaySpyAi.research_bonus(play, faction, ledger)
		if bonus.is_empty():
			continue
		var known: int = 0
		for tech: Variant in bonus.keys():
			if play.has_tech(player, String(tech)):
				known += 1
		_say("  %s: %d tech(s) +%d%%, %d of them the crown's own" % [
			FactionCatalog.name_of(faction), bonus.size(),
			SpyNetworks.BOOST_PERCENT, known,
		])


# --- turn driving ------------------------------------------------------------


func _run_turn(play: PlaySession) -> void:
	var turn: int = play.turn
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn == turn and not play.campaign_over() and guard < 12:
		guard += 1
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_offer(play, false)
		else:
			break


# --- helpers -----------------------------------------------------------------


func _roster(play: PlaySession, region: int) -> Array[CivilianState]:
	if play.model != null and region == play.model.region_id:
		return play.civilian_layer.units
	var roster: Array[CivilianState] = []
	roster.assign(play.civilian_layer.regions.value(region, []))
	return roster


## Relation score between the crown and each Great Power, by faction id.
func _relations(play: PlaySession, player: int) -> Dictionary:
	var scores: Dictionary = {}
	if play.diplomacy == null:
		return scores
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		var relation: DiplomacyRelation = play.diplomacy.relation(player, faction)
		if relation != null:
			scores[faction] = relation.score
	return scores


## Put one rival agent ashore on crown land (fixture state for the screen pass).
## A court the crown is at peace with is preferred: at war the relation score is
## floored, so a kill's diplomatic price would be swallowed and unseen.
func _seat_intruder(play: PlaySession, player: int) -> void:
	var rival: int = -1
	var fallback: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if faction == player:
			continue
		if fallback < 0:
			fallback = faction
		var relation: DiplomacyRelation = play.diplomacy.relation(player, faction)
		if relation != null and not relation.at_war:
			rival = faction
			break
	if rival < 0:
		rival = fallback
	if rival < 0:
		return
	var tile: Vector2i = _any_land(play, player)
	if tile == CivilianState.NO_TILE:
		return
	var intruder: CivilianState = play.civilian_layer.add_unit(rival, SPY, tile)
	intruder.moved = true
	_say("  seated a spy of %s in %s" % [
		FactionCatalog.name_of(rival), play.model.province_name(play.model.province_at(tile.x, tile.y)),
	])


## A crown spy standing on crown land, ready to take the screen order.
func _home_spy(play: PlaySession, player: int) -> CivilianState:
	for unit: CivilianState in play.civilian_layer.units:
		if unit.owner != player or unit.type_id != SPY:
			continue
		if play.model.owner_at(unit.tile.x, unit.tile.y) == player:
			return unit
	return null


## First land tile the crown holds.
func _any_land(play: PlaySession, owner: int) -> Vector2i:
	for y in play.model.height:
		for x in play.model.width:
			if play.model.owner_at(x, y) == owner and play.model.is_land(x, y):
				return Vector2i(x, y)
	return CivilianState.NO_TILE


## Crown spies on the roster, in every region.
func _crown_spies(play: PlaySession, player: int) -> int:
	var found: int = 0
	for region in play.world.region_count():
		for unit: CivilianState in _roster(play, region):
			if unit.owner == player and unit.type_id == SPY:
				found += 1
	return found


## Rival spies standing on crown land, in every region.
func _intruders(play: PlaySession, player: int) -> int:
	var found: int = 0
	for region in play.world.region_count():
		var model: MapModel = play.world.region(region)
		if model == null:
			continue
		for unit: CivilianState in _roster(play, region):
			if unit.type_id != SPY or unit.owner == player:
				continue
			if model.owner_at(unit.tile.x, unit.tile.y) == player:
				found += 1
	return found


## Toasts that say a rival spy was caught or came over this turn.
func _caught_this_turn() -> int:
	var found: int = 0
	for panel: Node in _screen.play.hud._toast_box.get_children():
		for text: String in _labels(panel):
			if text.contains("Counter-espionage caught") or text.contains("now serves your crown"):
				found += 1
	return found


func _my_toasts() -> void:
	for panel: Node in _screen.play.hud._toast_box.get_children():
		for text: String in _labels(panel):
			var lower: String = text.to_lower()
			if lower.contains("spy") or lower.contains("espionage") or lower.contains("coat"):
				_say("  toast: %s" % text)


func _clear_toasts() -> void:
	for child: Node in _screen.play.hud._toast_box.get_children():
		_screen.play.hud._toast_box.remove_child(child)
		child.free()


func _labels(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child: Node in node.get_children():
		var label: Label = child as Label
		if label != null and not label.text.is_empty():
			out.append(label.text)
		out.append_array(_labels(child))
	return out


func _open_game() -> MapScreen:
	return await Launch.open_map(self, SEED_TEXT, SETUP_SIZE_INDEX, ADVANCED)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_ai_spycraft: %d steps ---" % _steps.size())
	quit()
