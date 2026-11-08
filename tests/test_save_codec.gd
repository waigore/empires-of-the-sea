extends GdToolsTest
## Save/load round trip: capture a live session, write it, rebuild the world
## from the seed, and prove the mutable state came back (REQ-P3-03).

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const SEED: int = 4242
const WIDTH: int = 40
const HEIGHT: int = 32
const DIR: String = "user://test_save_codec"

## One shared preset world per worker keeps coverage runs fast; restores
## regenerate from the seed and are compared against their own fresh world.
static var _shared_world: WorldMap = null

var screen: MapScreen = null


func before_each() -> void:
	_clean_dir()
	screen = _new_screen()


func after_each() -> void:
	if is_instance_valid(screen):
		screen.free()
	screen = null
	get_tree().paused = false
	_clean_dir()


func _world() -> WorldMap:
	if _shared_world == null:
		_shared_world = MapGenerator.new().generate_world(SEED, WIDTH, HEIGHT)
	return _shared_world


func _new_screen(pending: Dictionary = {}) -> MapScreen:
	var node: MapScreen = SCREEN.instantiate()
	node.map_seed = SEED
	node.map_width = WIDTH
	node.map_height = HEIGHT
	node.save_dir = DIR
	if pending.is_empty():
		node.preset_world = _world()
	else:
		node.pending_save = pending
	add_child(node)
	return node


func test_round_trip_restores_session_world_and_layers() -> void:
	var play: PlaySession = screen.play
	MapPlayTurn.end_turn(play)
	play.economy.economy.treasury = 4321
	play.economy.economy.stockpile["grain"] = 77
	play.economy.economy.workers.set_count(1, 3)
	play.economy.economy.research.unlocked["apprentice_workers"] = true
	play.economy.market.prices["grain"] = 99
	play.prestige = 61

	var foreign: int = _foreign_province(play)
	play.model.get_province(foreign).owner = play.player_faction
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
	play.charted_provinces[foreign] = true
	play.leaders[play.player_faction] = LeaderCatalog.DEFAULT_KEY

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveCodec.is_valid(data), "captured save is valid")
	assert_true(
		SaveStore.write(DIR + "/roundtrip.sav", data), "save file is written"
	)
	var loaded: Dictionary = SaveStore.read(DIR + "/roundtrip.sav")
	assert_false(loaded.is_empty(), "save file reads back")

	screen.free()
	screen = _new_screen(loaded)
	play = screen.play
	assert_eq(play.turn, 2, "turn restored")
	assert_eq(play.prestige, 61, "prestige restored")
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
	assert_eq(play.civilian_layer.units.size(), 3, "civilians restored")
	assert_eq(play.civilian_layer.units[0].tile, tile, "civilian tile restored")
	assert_true(play.civilian_layer.units[0].is_working(), "civilian work restored")
	assert_eq(play.civilian_layer.units[0].remaining_turns(), 3, "work turns restored")
	assert_true(play.ship_layer.fleets[0].moved, "fleet orders restored")
	assert_true(play.army_layer.armies[0].moved, "army orders restored")
	assert_true(
		play.diplomacy.relation(play.player_faction, 1).at_war, "war state restored"
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

	screen.free()
	screen = _new_screen(data)
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			String(screen.play.leaders.get(faction, "")),
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
	play.ai = AiState.new()
	play.ai.agenda_for(AiConfig.build(2, 1))
	play.ai.note_war(play.player_faction, 2, play.turn)

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/generals.sav", data), "save file is written")
	var loaded: Dictionary = SaveStore.read(DIR + "/generals.sav")

	screen.free()
	screen = _new_screen(loaded)
	play = screen.play
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
	assert_not_null(play.ai, "rival-court bookkeeping restored")
	assert_true(
		play.ai.war_on_cooldown(play.player_faction, 2, play.turn, 4),
		"a load does not restart the war cooldown (wiki: diplomacy § Cooldowns)"
	)


func test_saved_region_index_reopens_that_map() -> void:
	var play: PlaySession = screen.play
	screen._cycle_region()
	assert_eq(play.region_index, 1)
	play.turn = 9
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(DIR + "/region.sav", data))
	var loaded: Dictionary = SaveStore.read(DIR + "/region.sav")

	screen.free()
	screen = _new_screen(loaded)
	assert_eq(screen.play.region_index, 1, "saved region reopened")
	assert_eq(screen.play.model.region_id, FactionCatalog.NEW_WORLD)
	assert_eq(screen.play.turn, 9)
	assert_eq(screen.play.economy.model.region_id, FactionCatalog.OLD_WORLD)


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

	screen.free()
	screen = _new_screen(loaded)
	assert_eq(
		screen.play.model.get_province(province.id).fort_level,
		FortRules.MAX_LEVEL,
		"walls are part of the world state a load restores"
	)


# --- helpers -----------------------------------------------------------------

func _foreign_province(play: PlaySession) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction:
			return province.id
	return -1


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
