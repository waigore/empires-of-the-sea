extends GdToolsTest
## Save/load round trip: capture a live session, write it, rebuild the world
## from the seed, and prove the mutable state came back (REQ-P3-03).

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const Fixture = preload("res://tests/map_fixture.gd")
const SEED: int = 4242
## Smallest side `SaveCodec.MIN_MAP_SIDE` accepts: the slot these cases write
## has to validate, and every tile is paid for twice (mount + reload).
const WIDTH: int = 32
const HEIGHT: int = 32
const DIR: String = "user://test_save_codec"

## One shared preset world per worker keeps coverage runs fast; a load applies
## the save over that same world (same seed and size) instead of regenerating.
static var _shared_world: WorldMap = null
## Owners, seats and deeds as the shared world was generated; each case starts
## from this clean snapshot (see `before_all`).
static var _pristine: Array = []

var screen: MapScreen = null


func before_all() -> void:
	_pristine = Fixture.snapshot(_world())


func before_each() -> void:
	_clean_dir()
	_restore_world()
	screen = _new_screen()


func after_each() -> void:
	_restore_world()
	if is_instance_valid(screen):
		screen.free()
	screen = null
	get_tree().paused = false
	_clean_dir()


func _world() -> WorldMap:
	if _shared_world == null:
		_shared_world = MapGenerator.new().generate_world(SEED, WIDTH, HEIGHT)
	return _shared_world


## Puts the shared world back the way generation left it, so a case that hands
## a province to the human crown or buys a deed does not leak into the next.
func _restore_world() -> void:
	Fixture.restore(_world(), _pristine)


func _new_screen(pending: Dictionary = {}) -> MapScreen:
	var node: MapScreen = SCREEN.instantiate()
	node.map_seed = SEED
	node.map_width = WIDTH
	node.map_height = HEIGHT
	node.save_dir = DIR
	# A load applies the save over this preset instead of regenerating the
	# world — same seed and size, so the map is the one the save expects.
	node.preset_world = _world()
	if not pending.is_empty():
		node.pending_save = pending
	add_child(node)
	return node


## Applies a save onto the mounted screen without tearing it down. Remounting
## MapScreen is the suite's dominant cost under coverage; most cases only need
## the PlaySession fields a load restores (preset world already matches).
func _apply_save(data: Dictionary) -> PlaySession:
	var play: PlaySession = screen.play
	assert_true(SaveCodec.restore(play, data, _world()), "save restores over the preset")
	var target: int = play.region_index
	# Economy always founds on the Old World; restore there, then return.
	play.region_index = 0
	play.model = play.world.region(0)
	SaveCodec.restore_economy(play, data)
	play.diplomacy = DiplomacyState.new()
	SaveCodec.restore_diplomacy(play, data)
	play.diplomacy.human_faction = play.human_faction_id()
	if target != play.region_index:
		screen.load_region(target)
	return play


func test_round_trip_restores_session_world_and_layers() -> void:
	var play: PlaySession = screen.play
	MapPlayTurn.end_turn(play)
	while DiplomacyProposals.has_pending(play.diplomacy, 0):
		MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, 0, "")
	play.economy.economy.treasury = 4321
	play.economy.economy.stockpile["grain"] = 77
	play.economy.economy.workers.set_count(1, 3)
	play.economy.economy.research.unlocked["apprentice_workers"] = true
	play.economy.market.prices["grain"] = 99

	var foreign: int = _foreign_province(play)
	play.model.get_province(foreign).owner = play.player_faction
	var deed_province: int = _other_foreign_province(play, foreign)
	var deed_tile: Vector2i = play.model.province_tiles(deed_province)[0]
	assert_true(play.model.purchase_tile(deed_tile, play.player_faction))
	var tile: Vector2i = play.model.province_tiles(play.capital_province)[0]
	play.land_works.set_improvement(play.model, tile, 2)
	play.land_works.set_transport(play.model, tile, LandWorks.TRANSPORT_ROAD)
	play.land_works.add_port(play.model, tile)
	play.land_works.set_prospected(play.player_faction, play.model, tile)

	var fog_tile: Vector2i = _fogged_tile(play)
	play.visibility.raise_to(
		play.model.index_of(fog_tile.x, fog_tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	var unit: CivilianState = play.civilian_layer.units[0]
	unit.tile = tile
	unit.start_work("build_improvement", tile, 3)
	play.ship_layer.fleets[0].moved = true
	play.army_layer.armies[0].moved = true
	DiplomacyRules.declare_war(play.diplomacy, play.player_faction, 1)
	Intervention.queue_human(play.diplomacy, 3, 6, play.player_faction)
	assert_true(
		DiplomacyProposals.queue(
			play.diplomacy, play.world, 2,
			DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
		)["ok"]
	)
	play.charted_provinces[foreign] = true
	play.leaders[play.player_faction] = LeaderCatalog.DEFAULT_KEY

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveCodec.is_valid(data), "captured save is valid")
	assert_false(
		(data["session"] as Dictionary).has("prestige"),
		"the dead prestige counter is no longer serialised"
	)
	assert_true(
		SaveStore.write(DIR + "/roundtrip.sav", data), "save file is written"
	)
	var loaded: Dictionary = SaveStore.read(DIR + "/roundtrip.sav")
	assert_false(loaded.is_empty(), "save file reads back")

	# Remount once: this case also proves the HUD wires the restored nation.
	screen.free()
	screen = _new_screen(loaded)
	play = screen.play
	assert_eq(play.turn, 2, "turn restored")
	assert_eq(play.player_faction, FactionCatalog.PLAYER_FACTION, "nation restored")
	assert_eq(play.economy.economy.treasury, 4321, "treasury restored")
	assert_eq(play.economy.economy.quantity("grain"), 77, "stockpile restored")
	assert_eq(play.economy.economy.workers.count(1), 3, "workers restored")
	assert_true(
		play.economy.economy.research.is_unlocked("apprentice_workers"),
		"research restored"
	)
	assert_eq(play.economy.market.price("grain"), 99, "market prices restored")
	assert_eq(
		play.model.province_owner(foreign), play.player_faction, "province owners restored"
	)
	assert_eq(
		play.model.owner_at(deed_tile.x, deed_tile.y),
		play.player_faction,
		"tile deed restored"
	)
	assert_true(play.model.is_purchased_tile(deed_tile), "deed marker restored")
	assert_eq(play.land_works.improvement_at(play.model, tile), 2, "works restored")
	assert_eq(
		play.land_works.transport_at(play.model, tile),
		LandWorks.TRANSPORT_ROAD,
		"roads restored"
	)
	assert_true(play.land_works.has_port(play.model, tile), "ports restored")
	assert_true(
		play.land_works.is_prospected(play.player_faction, play.model, tile),
		"prospect state restored"
	)
	assert_eq(
		play.visibility.level_at(fog_tile.x, fog_tile.y),
		VisibilityModel.Level.FULLY_VISIBLE,
		"fog state restored"
	)
	var player_civilians: int = 0
	for civilian: CivilianState in play.civilian_layer.units:
		if civilian.owner == play.player_faction:
			player_civilians += 1
	assert_eq(player_civilians, 3, "the human civilians restored")
	assert_true(
		play.civilian_layer.unit_count_all(1) >= 3,
		"a rival's seeded civilians restored too"
	)
	assert_eq(play.civilian_layer.units[0].tile, tile, "civilian tile restored")
	assert_true(play.civilian_layer.units[0].is_working(), "civilian work restored")
	assert_eq(play.civilian_layer.units[0].remaining_turns(), 3, "work turns restored")
	assert_true(play.ship_layer.fleets[0].moved, "fleet orders restored")
	assert_true(play.army_layer.armies[0].moved, "army orders restored")
	assert_true(
		play.diplomacy.relation(play.player_faction, 1).at_war, "war state restored"
	)
	assert_true(
		Intervention.has_pending(play.diplomacy, play.player_faction),
		"a waiting intervention restored"
	)
	assert_true(
		DiplomacyProposals.has_pending(play.diplomacy, play.player_faction),
		"a waiting rival proposal restored"
	)
	assert_true(play.charted_provinces.has(foreign), "charted provinces restored")
	assert_eq(
		String(play.leaders.get(play.player_faction, "")),
		LeaderCatalog.DEFAULT_KEY,
		"leader keys restored"
	)
	assert_eq(
		String(play.leaders.get(1, "")),
		LeaderCatalog.default_key(1),
		"rival crowns keep their leader"
	)
	assert_eq(screen.hud._nation_label.text, "SPAIN", "HUD reads the restored nation")


func test_saves_without_leaders_backfill_the_crown_roster() -> void:
	var play: PlaySession = screen.play
	var data: Dictionary = SaveCodec.capture(play)
	var session: Dictionary = data["session"]
	session.erase("leaders")
	data["session"] = session

	play = _apply_save(data)
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			String(play.leaders.get(faction, "")),
			LeaderCatalog.default_key(faction),
			"crown %d gets its configured leader" % faction
		)


func test_medals_and_feeding_survive_a_load() -> void:
	var play: PlaySession = screen.play
	var roster: GeneralRoster = play.army_layer.generals
	roster.sync(play.player_faction, {})
	roster.award(play.player_faction, "general_1")
	roster.award(play.player_faction, "general_1")
	play.feeding[play.player_faction] = 0.4
	play.economy.economy.navy_feeding = 0.5
	play.ai = AiState.new()
	play.ai.agenda_for(AiConfig.build(2, 1))
	play.ai.note_war(play.player_faction, 2, play.turn)
	play.ai.note_peace(play.player_faction, 2, play.turn)

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/generals.sav", data), "save file is written")
	var loaded: Dictionary = SaveStore.read(DIR + "/generals.sav")

	play = _apply_save(loaded)
	assert_eq(
		play.army_layer.generals.medals(play.player_faction, "general_1"),
		2,
		"medals never decrease across a load (wiki: military-generals § Medals)"
	)
	assert_eq(play.army_layer.generals.count(play.player_faction), 1, "roster size restored")
	assert_true(play.feeding.has(play.player_faction), "feeding coverage restored")
	assert_true(
		is_equal_approx(float(play.feeding[play.player_faction]), 0.4),
		"last rations feed the first battle after a load (wiki: combat § Feeding)"
	)
	assert_true(
		is_equal_approx(play.economy.economy.navy_feeding, 0.5),
		"last rations feed the first sea battle after a load"
	)
	assert_not_null(play.ai, "rival-court bookkeeping restored")
	assert_true(
		play.ai.war_on_cooldown(play.player_faction, 2, play.turn, 4),
		"a load does not restart the war cooldown (wiki: diplomacy § Cooldowns)"
	)
	assert_true(
		play.ai.peace_on_cooldown(play.player_faction, 2, play.turn, 3),
		"a load does not restart the peace-offer cooldown (DR-20261109-07)"
	)


func test_saved_region_index_reopens_that_map() -> void:
	var play: PlaySession = screen.play
	screen._cycle_region()
	assert_eq(play.region_index, 1)
	play.turn = 9
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/region.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/region.sav")

	play = _apply_save(loaded)
	assert_eq(play.region_index, 1, "saved region reopened")
	assert_eq(play.model.region_id, FactionCatalog.NEW_WORLD)
	assert_eq(play.turn, 9)
	assert_eq(play.economy.model.region_id, FactionCatalog.OLD_WORLD)


func test_invalid_and_corrupt_saves_are_refused() -> void:
	assert_false(SaveCodec.is_valid({}), "empty data is invalid")
	assert_false(SaveCodec.is_valid({"version": 999}), "future version is invalid")
	var data: Dictionary = SaveCodec.capture(screen.play)
	data["version"] = 999
	assert_false(SaveStore.save_slot(1, data, DIR), "invalid save is not written")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(DIR + "/broken.sav", FileAccess.WRITE)
	assert_not_null(file, "corrupt fixture opens")
	if file == null:
		return
	file.store_string("not a variant")
	file.close()
	assert_true(SaveStore.read(DIR + "/broken.sav").is_empty(), "corrupt read is empty")


func test_a_fort_stands_after_a_load() -> void:
	var play: PlaySession = screen.play
	var province: ProvinceState = play.model.provinces[0]
	province.fort_level = FortRules.MAX_LEVEL
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/forts.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/forts.sav")

	play = _apply_save(loaded)
	assert_eq(
		play.model.get_province(province.id).fort_level,
		FortRules.MAX_LEVEL,
		"walls are part of the world state a load restores"
	)


func test_a_waiting_call_to_arms_stays_suspended_after_a_load() -> void:
	var play: PlaySession = screen.play
	var pact: DiplomacyRelation = play.diplomacy.relation(0, 2)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(play.diplomacy)
	DiplomacyRules.declare_war(play.diplomacy, 3, 2)
	MapPlayTurn.end_turn(play)
	assert_true(play.turn_suspended, "the call holds the turn")
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/call.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/call.sav")

	play = _apply_save(loaded)
	MapPlaySetup.refresh_after_load(play)
	assert_true(CallToArms.has_pending(play.diplomacy, 0), "the call is restored")
	assert_true(play.turn_suspended, "the loaded turn is still suspended")
	assert_true(
		screen.hud.panels.diplomacy_panel._call_box.visible,
		"the court re-opens for the answer"
	)


## The crown's stance is state a battle reads this turn, so a save carries it
## and a load must not silently reset it (wiki: campaign-persistence
## § Snapshot contract — crown battle plan; DR-20261110-33).
func test_the_crowns_battle_plan_survives_a_load() -> void:
	var play: PlaySession = screen.play
	play.battle_plan = "aggressive"
	var data: Dictionary = SaveCodec.capture(play)
	assert_eq(
		String((data["session"] as Dictionary).get("battle_plan", "")),
		"aggressive",
		"the save carries the plan"
	)
	assert_true(SaveStore.write(DIR + "/plan.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/plan.sav")

	play = _apply_save(loaded)
	assert_eq(
		play.battle_plan, "aggressive",
		"the loaded crown still fights with its own plan"
	)


## A slot written before the plan was carried, or naming a script this build
## does not have, resumes on the default stance without an error (wiki:
## campaign-persistence § Load and resume — legacy defaults).
func test_a_save_without_a_readable_plan_lands_on_the_default_stance() -> void:
	var play: PlaySession = screen.play
	play.battle_plan = "defensive"
	var data: Dictionary = SaveCodec.capture(play)
	var session: Dictionary = data["session"]
	session.erase("battle_plan")
	data["session"] = session
	play = _apply_save(data)
	assert_eq(
		play.battle_plan, SaveCodec.DEFAULT_BATTLE_PLAN,
		"a legacy slot opens on the default stance"
	)

	var fresh: Dictionary = SaveCodec.capture(play)
	var fresh_session: Dictionary = fresh["session"]
	fresh_session["battle_plan"] = "reckless"
	fresh["session"] = fresh_session
	play = _apply_save(fresh)
	assert_eq(
		play.battle_plan, SaveCodec.DEFAULT_BATTLE_PLAN,
		"an unknown script falls back to the default"
	)


## The college ledger's goal is client state kept with the campaign, so a save
## carries it and a load reopens the queue on the same path instead of catalog
## order (wiki: tech-tree § Goal slot, campaign-persistence § Snapshot contract;
## DR-20261111-21).
func test_the_research_goal_survives_a_save() -> void:
	var play: PlaySession = screen.play
	play.economy.economy.research.goal = "bayonet"
	var data: Dictionary = SaveCodec.capture(play)
	assert_eq(
		String(((data["economy"] as Dictionary).get("research", {}) as Dictionary).get("goal", "")),
		"bayonet",
		"the save carries the goal"
	)
	play.economy.economy.research.goal = ""
	SaveCodec.restore_economy(play, data)
	assert_eq(
		play.economy.economy.research.goal, "bayonet",
		"a load brings the goal back to the ledger"
	)


# --- helpers -----------------------------------------------------------------

## The difficulty layer is fixed at creation, so a load must not re-roll it and
## must bring the rival ledgers back at the level they were founded on
## (wiki: ruleset-config § Layers).
func test_the_difficulty_layer_survives_a_load() -> void:
	var play: PlaySession = screen.play
	play.difficulty = "hard"
	var rival: PlayerEconomy = play.ensure_ai().economy_for(1)
	var purse: int = rival.treasury
	assert_gt(purse, PlayerEconomy.START_TREASURY, "a hard rival opens with more")

	var data: Dictionary = SaveCodec.capture(play)
	assert_eq(String((data["session"] as Dictionary).get("difficulty", "")), "hard")
	assert_true(SaveStore.write(DIR + "/difficulty.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/difficulty.sav")

	play = _apply_save(loaded)
	assert_eq(play.difficulty, "hard", "the layer is fixed for the campaign")
	assert_eq(play.ai.difficulty, "hard")
	assert_eq(play.ai.economy_for(1).treasury, purse, "the rival purse returns as saved")


func test_the_gazette_watchlist_and_archive_survive_a_load() -> void:
	var play: PlaySession = screen.play
	MapPlayTurn.end_turn(play)
	while DiplomacyProposals.has_pending(play.diplomacy, 0):
		MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, 0, "")
	assert_true(play.gazette != null, "the close founded the watchlist")
	assert_true(play.gazette.has_sheet(1), "the resolved turn is filed")
	play.gazette.set_watched(1, false)
	var filed: int = play.gazette.sheets.size()

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/gazette.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/gazette.sav")

	play = _apply_save(loaded)
	assert_true(play.gazette != null, "the sheet returns on load")
	assert_eq(play.gazette.sheets.size(), filed, "the archive comes back whole")
	assert_false(play.gazette.is_watched(1), "a struck-off court stays struck off")
	assert_true(play.gazette.removed.has(1), "and the removal is remembered")


func _foreign_province(play: PlaySession) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction:
			return province.id
	return -1


func _other_foreign_province(play: PlaySession, skip: int) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction and province.id != skip:
			return province.id
	return skip


func _fogged_tile(play: PlaySession) -> Vector2i:
	for province: ProvinceState in play.model.provinces:
		if province.owner == play.player_faction:
			continue
		for tile: Vector2i in province.tiles:
			if play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FOGGED:
				return tile
	return play.capital_tile


func _clean_dir() -> void:
	var path: String = ProjectSettings.globalize_path(DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
