extends SceneTree
## Multi-turn playtest probe: boots the real game, plays N turns as the human
## crown (civilians, navy, army, ledger, diplomacy decisions) and asserts the
## campaign stays coherent each turn.
##   godot --headless --path . --script res://tools/playtest_turns.gd -- turns=24 seed=1500 size=1
##
## Prints one line per turn (turn, year, treasury, income, holdings, forces,
## AI trace, feeding, rival ledgers) plus PASS/FAIL for each invariant, and a
## final summary. Exit code 1 when any invariant breaks.

const BOOT_FRAMES: int = 8
const SAVE_DIR: String = "user://playtest_saves"
const SAVE_SLOT: int = 3

var _failures: PackedStringArray = []
var _turns: int = 24
var _seed: int = 1500
var _size_index: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _report: Array[String] = []
var _start_ms: int = 0
var _deadline_ms: int = 300000
var _debug: bool = false
var _faction: int = -1
var _answers: Dictionary = {
	"call_join": 0, "call_refuse": 0,
	"intervene": 0, "protest": 0, "nothing": 0,
	"offer_accept": 0, "offer_refuse": 0,
}
var _shot: bool = false
var _pace_ms: int = 0
var _start_region: int = 0


func _initialize() -> void:
	_start_ms = Time.get_ticks_msec()
	_parse_args()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _start_ms < _deadline_ms:
		return false
	_fail("probe hit its %d s deadline" % (_deadline_ms / 1000))
	quit(1)
	return true


func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = raw.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"turns":
				_turns = maxi(1, parts[1].to_int())
			"seed":
				_seed = parts[1].to_int()
			"size":
				_size_index = clampi(parts[1].to_int(), 0, 2)
			"debug":
				_debug = parts[1] == "1"
			"deadline":
				_deadline_ms = maxi(30, parts[1].to_int()) * 1000
			"faction":
				_faction = parts[1].to_int()
			"shot":
				_shot = parts[1] == "1"
			"pace":
				_pace_ms = maxi(0, parts[1].to_int())
			"region":
				_start_region = clampi(parts[1].to_int(), 0, 1)
	_rng.seed = _seed


func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main.tscn loads")
	if packed == null:
		_finish()
		return
	_clean_save_dir()
	var main: Node = packed.instantiate()
	root.add_child(main)
	for _frame in BOOT_FRAMES:
		await process_frame
	var menu: MainMenu = main.current_page as MainMenu
	if menu == null:
		_fail("main menu boots")
		_finish()
		return
	menu.new_game_button.emit_signal("pressed")
	await process_frame
	var setup: GameSetupScreen = main.current_page as GameSetupScreen
	if setup == null:
		_fail("setup screen opens")
		_finish()
		return
	setup.seed_field.text = str(_seed)
	setup.size_option.select(_size_index)
	if _faction >= 0 and setup.nation_option != null:
		for index in setup.nation_option.item_count:
			if setup.nation_option.get_item_id(index) != _faction:
				continue
			setup.nation_option.select(index)
			setup.nation_option.item_selected.emit(index)
			break
	setup.start_button.emit_signal("pressed")
	await process_frame
	# The capital-choice phase sits between setup and turn 1: confirm the
	# auto-chosen seat (the documented default) once the chart is ready.
	var seat_guard: int = 0
	while main.current_page is CapitalChoiceScreen and seat_guard < 600:
		seat_guard += 1
		var page: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
		if page.confirm_button != null and not page.confirm_button.disabled:
			_check(page.confirm(), "the capital choice seats the court")
			break
		await process_frame
	await process_frame
	var screen: MapScreen = main.current_screen
	if screen == null:
		_fail("map screen boots")
		_finish()
		return
	screen.save_dir = SAVE_DIR
	if _start_region > 0 and screen.play.world.region_count() > _start_region:
		screen._cycle_region()
		await process_frame
	print(
		"playtest: seed=%d size=%d turns=%d faction=%s provinces=%d"
		% [
			_seed, _size_index, _turns,
			FactionCatalog.name_of(screen.play.player_faction),
			screen.world.total_provinces(),
		]
	)

	var campaign_ended: bool = false
	var saved_once: bool = false
	for step in _turns:
		if screen.play.campaign_over():
			campaign_ended = true
			break
		_player_turn(screen)
		var turn_before: int = screen.turn
		_end_turn_and_answer(screen)
		var advanced: bool = _settle_turn(screen, turn_before)
		_line(screen)
		if screen.play.campaign_over():
			campaign_ended = true
			print(
				"playtest: campaign over on turn %d — %s"
				% [screen.turn, _outcome(screen)]
			)
			break
		if not advanced:
			if screen.play.campaign_over():
				_line(screen)
				print(
					"playtest: campaign closed on turn %d — %s"
					% [screen.turn, _outcome(screen)]
				)
				campaign_ended = true
				break
			_fail("turn %d failed to advance" % turn_before)
			break
		# Tour the New World every few turns: the view swap must not reset or
		# duplicate units, works or fog.
		if step % 4 == 3 and _start_region == 0 and screen.play.world.region_count() > 1:
			screen._cycle_region()
			await process_frame
			_check(
				screen.play.region_index == 1,
				"turn %d: region switch reaches the New World" % screen.turn
			)
			_line(screen)
			screen._cycle_region()
			await process_frame
			_check(
				screen.play.region_index == 0,
				"turn %d: region switch returns to the Old World" % screen.turn
			)
		# Mid-run save/load: the campaign must resume identically.
		if not saved_once and screen.turn >= 6:
			saved_once = true
			await _check_save_load(main, screen)
			screen = main.current_screen
			if screen == null:
				_fail("map screen survives a mid-run load")
				_finish()
				return
		if _pace_ms > 0:
			await create_timer(_pace_ms / 1000.0).timeout

	if not campaign_ended:
		print("playtest: survived %d turns without a campaign end" % _turns)
	if _shot:
		await _capture()
	_check(screen.play.turn >= 1, "calendar holds a turn")
	_finish()


## Saves the live frame for a visual pass (needs a real GL context, not
## --headless).
func _capture() -> void:
	# Let the opening fade (0.9 s) and any layout tweens finish before the shot.
	for _frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "/tmp/eots_playtest.png"
	image.save_png(path)
	print("playtest: screenshot %s (%dx%d)" % [path, image.get_width(), image.get_height()])


# --- player -------------------------------------------------------------------


## One human turn: civilian work, navy orders, army recruiting, ledger staffing.
func _player_turn(screen: MapScreen) -> void:
	_player_civilians(screen)
	_player_navy(screen)
	_player_army(screen)
	_player_economy(screen)


func _player_civilians(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	for unit: CivilianState in screen.civilian_layer.units.duplicate():
		if unit == null or unit.owner != play.player_faction or unit.is_working():
			continue
		var options: Array[Dictionary] = CivilianWork.options(
			play.model, unit, play.land_works, screen.civilian_layer.units,
			play.stockpile(), play.visibility, play.tech_caps(), play.tech_unlocked(),
			_civ_context(play)
		)
		var action: String = ""
		for option: Dictionary in options:
			if bool(option.get("ok", false)):
				action = String(option["action"])
				break
		if action.is_empty():
			if unit.moved:
				continue
			var tiles: Array[Vector2i] = CivilianMovement.valid_tiles(play.model, unit)
			if tiles.is_empty():
				continue
			var dest: Vector2i = tiles[_rng.randi_range(0, tiles.size() - 1)]
			screen.civilian_layer.select(unit)
			MapPlayCivilians.try_move(
				play, MapGeo.tile_center(dest.x, dest.y, MapScreen.TILE_SIZE)
			)
			continue
		screen.civilian_layer.select(unit)
		MapPlayCivilians.on_action(play, action)


func _civ_context(play: PlaySession) -> Dictionary:
	return {
		"treasury": play.treasury(),
		"capital_province": play.capital_province,
		"capital_tile": play.capital_tile,
		"at_war": _player_at_war(play),
	}


func _player_at_war(play: PlaySession) -> bool:
	if play.diplomacy == null:
		return false
	for record: DiplomacyRelation in play.diplomacy.relations_of(play.player_faction):
		if record.at_war:
			return true
	return false


func _player_navy(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var layer: ShipLayer = screen.ship_layer
	for ship: Ship in layer.ships:
		var fleet: FleetState = layer.fleet_of(ship)
		if fleet == null or fleet.owner != play.player_faction or fleet.moved:
			continue
		var zones: Array = NavalMovement.destination_zones(play.model, fleet)
		if zones.is_empty():
			continue
		var zone: int = int(zones[_rng.randi_range(0, zones.size() - 1)])
		var tiles: Array = play.model.sea_zones[zone].tiles
		if tiles.is_empty():
			continue
		var tile: Vector2i = tiles[0]
		MapPlayFleets.try_order(play, tile)


func _player_army(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var home: ArmyState = null
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == play.player_faction and army.is_home_army():
			home = army
			break
	if home == null:
		return
	for type_id: String in ["peasant_levies", "pikemen", "squires"]:
		if not RegimentCatalog.has_type(type_id):
			continue
		if play.treasury() < RegimentCatalog.treasury_cost(type_id):
			continue
		var before: int = home.count()
		var result: Dictionary = screen.army_layer.recruit(
			play.player_faction, type_id, play.economy.economy
		)
		if home.count() > before:
			break
		if _debug:
			print("debug: T%d recruit %s refused: %s" % [play.turn, type_id, str(result)])
	# Field one small army outside the capital so land combat is exercised.
	var field: ArmyState = _field_army(screen)
	if field == null and home.count() >= 3:
		var ids: Array[String] = []
		for index in mini(2, home.regiments.size()):
			ids.append(home.regiments[index])
		var split: Dictionary = screen.army_layer.split(home, ids)
		if bool(split.get("ok", false)):
			field = split["army"] as ArmyState
	# Pick a fight with a neighbouring minor once, so battles resolve.
	if screen.turn == 3:
		var target: int = _neighbour_minor(screen)
		if target >= 0:
			MapPlayDiplomacy.on_order(play, DiplomacyOrders.KIND_WAR, target, "")
			print("playtest: declared war on %s" % FactionCatalog.name_of(target))
	# ...and with a Great Power, so alliance calls and peace offers are exercised.
	if screen.turn == 4:
		for faction: int in FactionCatalog.great_power_ids():
			if faction == play.player_faction:
				continue
			MapPlayDiplomacy.on_order(play, DiplomacyOrders.KIND_WAR, faction, "")
			print("playtest: declared war on %s" % FactionCatalog.name_of(faction))
			break
	if field == null or field.moved or field.embarked_fleet >= 0:
		return
	screen.army_layer.select(field)
	var attack: int = -1
	var neutral: int = -1
	for province_id: int in ArmyMovement.destinations(play.model, field):
		var owner: int = play.model.province_owner(province_id)
		if owner == play.player_faction:
			continue
		if (
			owner != MapModel.NO_ID
			and DiplomacyRules.at_war_with(play.diplomacy, play.player_faction, owner)
		):
			attack = province_id
			break
		if neutral < 0:
			neutral = province_id
	var march: int = attack if attack >= 0 else neutral
	if march < 0:
		return
	var tiles: Array = play.model.province_tiles(march)
	if tiles.is_empty():
		return
	MapPlayArmies.try_order(play, tiles[0])


func _field_army(screen: MapScreen) -> ArmyState:
	var play: PlaySession = screen.play
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == play.player_faction and not army.is_home_army():
			return army
	return null


## A Minor Nation or Tribe bordering the player's land, or -1.
func _neighbour_minor(screen: MapScreen) -> int:
	var play: PlaySession = screen.play
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction:
			continue
		for neighbour: int in MapGeo.province_neighbors(play.model, province.id):
			var owner: int = play.model.province_owner(neighbour)
			if owner == MapModel.NO_ID or owner == play.player_faction:
				continue
			if FactionCatalog.type_of(owner) == FactionCatalog.Type.GREAT_POWER:
				continue
			return owner
	return -1


func _player_economy(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var state: PlayerEconomy = play.economy.economy
	if state == null:
		return
	# Staff the next Production phase: one run per basic good while labour lasts.
	state.clear_assignments()
	var order: Array[String] = ["fabric_from_wool", "paper", "lumber"]
	for recipe: String in order:
		if state.workers.labour() < state.assigned_labour() + ProductionRecipes.labour(recipe):
			break
		state.set_assignment(recipe, 1)
	# Keep the three research slots working through the tree.
	for slot in state.research.slot_count():
		if not state.research.tech_at(slot).is_empty():
			continue
		var techs: Array[String] = state.research.researchable()
		if techs.is_empty():
			break
		state.research.assign(techs[0], ResearchFunding.DEFAULT, slot)


# --- turn ---------------------------------------------------------------------


## Dismiss every waiting Quick Battle plate (the player presses Skip then
## Continue) so the calendar may advance.
func _resolve_quick_battles(screen: MapScreen) -> void:
	var guard: int = 0
	while (
		screen.hud != null and screen.hud.is_quick_battle_shown() and guard < 8
	):
		guard += 1
		var overlay: QuickBattleOverlay = screen.hud.quick_battle_overlay
		overlay.skip()
		overlay._on_continue()


## End the turn, answering every court decision that suspends it, until the
## calendar actually advances (or the campaign closes).
func _end_turn_and_answer(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var guard: int = 0
	while guard < 12:
		guard += 1
		var turn_before: int = play.turn
		_resolve_quick_battles(screen)
		if _debug:
			print(
				"debug: pre end_turn T%d quick=%s call=%s interv=%s offer=%s suspended=%s"
				% [
					turn_before,
					str(screen.hud != null and screen.hud.is_quick_battle_shown()),
					str(CallToArms.has_pending(play.diplomacy, play.player_faction)),
					str(Intervention.has_pending(play.diplomacy, play.player_faction)),
					str(DiplomacyProposals.has_pending(play.diplomacy, play.player_faction)),
					str(play.turn_suspended),
				]
			)
		MapPlayTurn.end_turn(play)
		_resolve_quick_battles(screen)
		if _debug:
			print(
				"debug: post end_turn T%d quick=%s over=%s"
				% [
					play.turn,
					str(screen.hud != null and screen.hud.is_quick_battle_shown()),
					str(play.campaign_over()),
				]
			)
		var pending: bool = _answer_pending(screen)
		if play.turn != turn_before or screen.play.campaign_over():
			return
		if not pending:
			# No decision to answer and no advance: a real stall.
			_fail("turn %d stalls with no pending court decision" % turn_before)
			return


## Answer whichever court decision holds the calendar. Returns true when one
## was answered.
func _answer_pending(screen: MapScreen) -> bool:
	var play: PlaySession = screen.play
	var accept: bool = play.turn % 2 == 0
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapCourtOrders.apply(
			play, CallToArms.KIND_JOIN if accept else CallToArms.KIND_REFUSE, -1, ""
		)
		_answers["call_join" if accept else "call_refuse"] += 1
		return true
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		var kind: String = Intervention.KIND_PROTEST if accept else Intervention.KIND_NOTHING
		MapCourtOrders.apply(play, kind, -1, "")
		_answers["protest" if accept else "nothing"] += 1
		return true
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		var offer_kind: String = (
			DiplomacyProposals.KIND_ACCEPT if accept else DiplomacyProposals.KIND_REFUSE
		)
		MapCourtOrders.apply(play, offer_kind, -1, "")
		_answers["offer_accept" if accept else "offer_refuse"] += 1
		return true
	return false


## Invariants after one resolved turn. Returns false when the calendar did not
## advance. Prints one per-turn telemetry line.
func _settle_turn(screen: MapScreen, turn_before: int) -> bool:
	var play: PlaySession = screen.play
	var advanced: bool = play.turn == turn_before + 1
	if not advanced:
		if not play.campaign_over():
			_line(screen)
			_fail("turn %d -> %d did not advance by one" % [turn_before, play.turn])
		return false
	_check(
		play.treasury() >= 0,
		"turn %d: treasury is not negative (%d)" % [play.turn, play.treasury()]
	)
	for commodity: Variant in play.stockpile().keys():
		var amount: int = int(play.stockpile()[commodity])
		_check(
			amount >= 0,
			"turn %d: stockpile %s is not negative (%d)"
			% [play.turn, String(commodity), amount]
		)
	_check(
		play.income >= -5000,
		"turn %d: projected income is sane (%d)" % [play.turn, play.income]
	)
	_check(
		play.ai != null and play.ai_trace.size() == FactionCatalog.great_power_ids().size() - 1,
		"turn %d: every rival court took its turn (%d)"
		% [play.turn, play.ai_trace.size() if play.ai != null else -1]
	)
	var feeding: float = float(play.feeding.get(play.player_faction, 1.0))
	_check(
		feeding >= 0.0 and feeding <= 1.0001,
		"turn %d: feeding coverage in range (%.2f)" % [play.turn, feeding]
	)
	_check(
		screen.civilian_layer.units.size() > 0 or not play.player_present(),
		"turn %d: human civilians still exist" % play.turn
	)
	_check_rivals(play)
	_check_units(screen)
	_check_provinces(play)
	if _debug:
		_debug_turn(screen)
	return true


func _debug_turn(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	if play.economy == null or play.economy.economy == null:
		return
	var state: PlayerEconomy = play.economy.economy
	print(
		"debug: T%d workers=%d labour=%d assign=%s ext=%s income=%d"
		% [
			play.turn, state.workers.total(), state.workers.labour(),
			str(state.assignments()), str(play.economy.extraction().keys()),
			play.income,
		]
	)
	if play.ai == null:
		return
	var rivals: PackedStringArray = []
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		rivals.append(
			"%s gold=%d workers=%d prov=%d civ=%d rgts=%d hulls=%d"
			% [
				FactionCatalog.name_of(faction).substr(0, 4),
				economy.treasury,
				economy.workers.total(),
				play.world.owned_provinces(play.region_index, faction),
				play.civilian_layer.unit_count_all(faction),
				play.army_layer.regiment_count_all(faction),
				play.ship_layer.hull_count_all(faction),
			]
		)
	print("debug:   rivals %s" % " | ".join(rivals))
	var acts: PackedStringArray = []
	for record: Dictionary in play.ai_trace:
		var action: Dictionary = record.get("action", {})
		acts.append(
			"%s:%s>%d"
			% [
				FactionCatalog.name_of(int(record.get("faction", -1))).substr(0, 4),
				String(action.get("kind", "-")),
				int(action.get("target", -1)),
			]
		)
	print("debug:   ai %s" % ", ".join(acts))


func _check_rivals(play: PlaySession) -> void:
	if play.ai == null:
		return
	for faction: int in FactionCatalog.great_power_ids():
		if faction == play.player_faction:
			continue
		var economy: PlayerEconomy = play.ai.economy_for(faction)
		_check(
			economy.treasury >= 0,
			"turn %d: %s treasury is not negative (%d)"
			% [play.turn, FactionCatalog.name_of(faction), economy.treasury]
		)
		for commodity: Variant in economy.stockpile.keys():
			_check(
				int(economy.stockpile[commodity]) >= 0,
				"turn %d: %s %s is not negative (%d)"
				% [
					play.turn, FactionCatalog.name_of(faction),
					String(commodity), int(economy.stockpile[commodity]),
				]
			)


func _check_units(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var working_tiles: Dictionary = {}
	for unit: CivilianState in screen.civilian_layer.units:
		if unit == null:
			_fail("turn %d: null civilian in the roster" % play.turn)
			continue
		if unit.is_embarked():
			continue
		if unit.is_working():
			var work_key: String = "%d:%d" % [unit.work_tile().x, unit.work_tile().y]
			if working_tiles.has(work_key):
				_fail(
					"turn %d: two crews work tile %s (%s + %s)"
					% [play.turn, work_key, working_tiles[work_key], unit.display_name()]
				)
			working_tiles[work_key] = unit.display_name()
		_check(
			play.model.in_bounds(unit.tile.x, unit.tile.y),
			"turn %d: %s stands on the map" % [play.turn, unit.display_name()]
		)
		_check(
			play.model.is_land(unit.tile.x, unit.tile.y),
			"turn %d: %s stands on land" % [play.turn, unit.display_name()]
		)
		if not CivilianMovement.may_enter(
			play.model, unit.type_id, unit.owner, unit.tile
		):
			var province: int = play.model.province_at(unit.tile.x, unit.tile.y)
			_fail(
				"turn %d: %s (owner %d) stranded at %s tile_owner=%d province=%d/%d working=%s"
				% [
					play.turn, unit.display_name(), unit.owner, str(unit.tile),
					play.model.owner_at(unit.tile.x, unit.tile.y), province,
					play.model.province_owner(province), str(unit.is_working()),
				]
			)
	for army: ArmyState in screen.army_layer.armies:
		if army == null or army.home:
			continue
		_check(
			army.count() > 0,
			"turn %d: field army %d keeps regiments" % [play.turn, army.id]
		)


func _check_provinces(play: PlaySession) -> void:
	var owned: int = play.world.owned_provinces(play.region_index, play.player_faction)
	_check(
		owned >= 0,
		"turn %d: province holdings readable (%d)" % [play.turn, owned]
	)
	if play.capital_province >= 0 and play.player_present():
		var owner: int = play.model.provinces[play.capital_province].owner
		if play.defeat == null:
			_check(
				owner == play.player_faction or owned > 0,
				"turn %d: capital province still answers to a crown" % play.turn
			)


# --- save/load ----------------------------------------------------------------


func _check_save_load(main: Node, screen: MapScreen) -> void:
	var civilians_before: Array[String] = _civilian_fingerprints(screen)
	var state_before: Array[String] = _state_fingerprint(screen)
	_check(
		SaveStore.save_slot(SAVE_SLOT, SaveCodec.capture(screen.play), SAVE_DIR),
		"mid-run save writes"
	)
	var before_turn: int = screen.turn
	var before_treasury: int = screen.treasury
	var before_region: int = screen.play.region_index
	var before_provinces: int = screen.play.world.owned_provinces(
		screen.play.region_index, screen.play.player_faction
	)
	screen.game_menu.open()
	screen.game_menu.open_load()
	screen.game_menu.browser.slot_chosen.emit(SAVE_SLOT)
	await process_frame
	var loaded: MapScreen = main.current_screen
	_check(loaded != null and loaded != screen, "mid-run load rebuilds the screen")
	if loaded == null:
		return
	loaded.save_dir = SAVE_DIR
	_check(loaded.turn == before_turn, "mid-run load restores turn %d" % before_turn)
	_check(loaded.treasury == before_treasury, "mid-run load restores treasury")
	_check(
		loaded.play.region_index == before_region,
		"mid-run load restores the region on screen (%d)" % before_region
	)
	_check(
		loaded.world.owned_provinces(loaded.region_index, loaded.player_faction)
		== before_provinces,
		"mid-run load restores province holdings"
	)
	var civilians_after: Array[String] = _civilian_fingerprints(loaded)
	_check(
		civilians_after == civilians_before,
		"mid-run load restores civilian orders (%s vs %s)"
		% [str(civilians_before), str(civilians_after)]
	)
	var state_after: Array[String] = _state_fingerprint(loaded)
	_check(
		state_after == state_before,
		"mid-run load restores the full rules state (diff %s)"
		% str(_fingerprint_diff(state_before, state_after))
	)
	_clean_save_dir()


## Rules state that a save must round-trip exactly, sorted for stable compares.
func _state_fingerprint(screen: MapScreen) -> Array[String]:
	var play: PlaySession = screen.play
	var out: Array[String] = []
	out.append(
		"campaign turn=%d region=%d halted=%s"
		% [play.turn, play.region_index, str(play.campaign_halted)]
	)
	if play.economy != null and play.economy.economy != null:
		var state: PlayerEconomy = play.economy.economy
		out.append("economy treasury=%d" % state.treasury)
		out.append_array(_tagged("stock", state.stockpile))
		for tier in WorkerPool.TIER_COUNT:
			out.append("workers:%d=%d" % [tier, state.workers.count(tier)])
		for tech: Variant in state.research.unlocked.keys():
			out.append("tech:%s=%s" % [String(tech), str(state.research.unlocked[tech])])
		for tech: Variant in state.research.progress.keys():
			out.append("rp:%s=%d" % [String(tech), int(state.research.progress[tech])])
	if play.land_works != null:
		out.append_array(_tagged("improvement", play.land_works.improvement))
		out.append_array(_tagged("transport", play.land_works.transport))
		out.append_array(_tagged("ports", play.land_works.ports))
		out.append_array(_tagged("prospected", play.land_works.prospected))
	for region in play.world.region_count():
		if play.army_layer != null:
			var armies: Array = play.army_layer.regions.value(region, [])
			for army: ArmyState in armies:
				if army == null:
					continue
				out.append(
					"army r%d id=%d owner=%d prov=%d home=%s moved=%s n=%d regs=%s embarked=%d"
					% [
						region, army.id, army.owner, army.province, str(army.home),
						str(army.moved), army.count(), ",".join(army.regiments),
						army.embarked_fleet,
					]
				)
		if play.ship_layer != null:
			var fleets: Array = play.ship_layer.regions.value(region, [])
			for fleet: FleetState in fleets:
				if fleet == null:
					continue
				out.append(
					"fleet r%d id=%d owner=%d loc=%d prov=%d zone=%d moved=%s hulls=%s"
					% [
						region, fleet.id, fleet.owner, fleet.location, fleet.province,
						fleet.sea_zone, str(fleet.moved), ",".join(fleet.hulls),
					]
				)
	if play.ai != null:
		for faction: int in FactionCatalog.great_power_ids():
			if faction == play.player_faction:
				continue
			var economy: PlayerEconomy = play.ai.economy_for(faction)
			out.append(
				"ai:%d treasury=%d workers=%d assign=%s"
				% [
					faction, economy.treasury, economy.workers.total(),
					str(economy.assignments()),
				]
			)
			out.append_array(_tagged("ai:%d stock" % faction, economy.stockpile))
	if play.diplomacy != null:
		out.append(
			"diplomacy human=%d relations=%d"
			% [play.diplomacy.human_faction, play.diplomacy.relations.size()]
		)
	out.sort()
	return out


func _tagged(prefix: String, source: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		out.append("%s %s=%s" % [prefix, str(key), str(source[key])])
	return out


func _fingerprint_diff(before: Array[String], after: Array[String]) -> Array[String]:
	var diff: Array[String] = []
	for line: String in before:
		if not after.has(line):
			diff.append("lost:" + line)
	for line: String in after:
		if not before.has(line):
			diff.append("gained:" + line)
	if diff.is_empty():
		return diff
	return diff.slice(0, 8)


## Stable per-unit description of the player's civilians in the live region.
func _civilian_fingerprints(screen: MapScreen) -> Array[String]:
	var out: Array[String] = []
	for unit: CivilianState in screen.civilian_layer.units:
		if unit == null or unit.owner != screen.play.player_faction:
			continue
		out.append(
			"%d:%s@%d,%d/%d/%s/%d/%d,%d"
			% [
				unit.id, unit.type_id, unit.tile.x, unit.tile.y, unit.status,
				unit.work_action(), unit.remaining_turns(),
				unit.assigned_tile.x, unit.assigned_tile.y,
			]
		)
	out.sort()
	return out


# --- output -------------------------------------------------------------------


func _line(screen: MapScreen) -> void:
	var play: PlaySession = screen.play
	var rival_treasuries: PackedStringArray = []
	if play.ai != null:
		for faction: int in FactionCatalog.great_power_ids():
			if faction == play.player_faction:
				continue
			rival_treasuries.append(
				"%s=%d" % [
					FactionCatalog.name_of(faction).substr(0, 4),
					play.ai.economy_for(faction).treasury,
				]
			)
	var line: String = (
		"playtest: T%-3d %d  gold=%-5d inc=%-4d provinces=%-2d "
		+ "civ=%-2d ships=%-2d rgts=%-3d ext=%-2d stock=%-3d dev=%-2d pdev=%-2d "
		+ "feed=%.2f ai=%d rivals[%s]"
	) % [
		play.turn,
		TurnTime.year_for_turn(play.turn),
		play.treasury(),
		play.income,
		play.world.owned_provinces(play.region_index, play.player_faction),
		screen.civilian_layer.unit_count_all(play.player_faction),
		screen.ship_layer.hull_count_all(play.player_faction),
		screen.army_layer.regiment_count_all(play.player_faction),
		play.economy.extraction().size() if play.economy != null else 0,
		play.economy.economy.total_units() if play.economy != null else 0,
		play.land_works.developed_tiles(play.model).size() if play.land_works != null else 0,
		_player_dev(screen),
		float(play.feeding.get(play.player_faction, 1.0)),
		play.ai_trace.size(),
		", ".join(rival_treasuries),
	]
	print(line)
	_report.append(line)


## Developed tiles in the live region that belong to the human crown.
func _player_dev(screen: MapScreen) -> int:
	var play: PlaySession = screen.play
	if play.land_works == null or play.model == null:
		return 0
	var total: int = 0
	for tile: Vector2i in play.land_works.developed_tiles(play.model):
		if play.model.owner_at(tile.x, tile.y) == play.player_faction:
			total += 1
	return total


func _outcome(screen: MapScreen) -> String:
	var play: PlaySession = screen.play
	if play.defeat != null:
		return "defeat"
	if play.victory != null:
		return "victory by %s" % play.victory.winner_name()
	if play.campaign_halted:
		return "calendar cap"
	return "undecided"


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)


func _fail(label: String) -> void:
	printerr("playtest: FAIL %s" % label)
	_failures.append(label)


func _finish() -> void:
	print("playtest: court answers %s" % str(_answers))
	if _failures.is_empty():
		print("playtest: all invariants held over %d turn(s)" % _turns)
		quit(0)
	else:
		printerr("playtest: %d invariant failure(s)" % _failures.size())
		quit(1)


func _clean_save_dir() -> void:
	var path: String = ProjectSettings.globalize_path(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
