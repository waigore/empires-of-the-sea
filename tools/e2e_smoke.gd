extends SceneTree
## Headless e2e smoke: boot main.tscn, exercise one player turn across every
## unit type (civilian / navy / army), quit. Budget ≤2 minutes.
##   godot --headless --path . --script res://tools/e2e_smoke.gd

const BOOT_FRAMES: int = 8
## The smoke drives the real title -> setup -> map flow. Small keeps it fast.
const SETUP_SIZE_INDEX: int = 0
const SETUP_SEED: String = "1500"
const SAVE_DIR: String = "user://e2e_smoke_saves"
const SAVE_SLOT: int = 1

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("e2e_smoke: loading main scene")
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

	_check(GameVersion.as_string() != "", "GameVersion.as_string non-empty")
	_check(GameVersion.is_compatible_with(GameVersion.MAJOR), "GameVersion major compatible")

	var menu: MainMenu = main.current_page as MainMenu
	_check(menu != null, "main menu boots first")
	_check(menu != null and menu.settings_button.disabled, "settings is dimmed")
	_check(main.current_screen == null, "no map runs behind the title screen")
	if menu == null:
		_finish()
		return
	menu.new_game_button.emit_signal("pressed")
	await process_frame

	var setup: GameSetupScreen = main.current_page as GameSetupScreen
	_check(setup != null, "new game opens the setup screen")
	if setup == null:
		_finish()
		return
	setup.seed_field.text = SETUP_SEED
	setup.size_option.select(SETUP_SIZE_INDEX)
	_check(setup.leader_option.item_count > 0, "leader choices offered at setup")
	_check(
		setup.advanced_option != null and setup.advanced_option.item_count == 3,
		"setup offers the advanced-start openings"
	)
	# The difficulty row names the bar the chosen level sets, so the choice is
	# never blind (wiki: victory § Military victory; DR-20261111-28).
	_check(
		_has_text(setup, "hold %d Old World provinces" % VictoryRules.MILITARY_THRESHOLD),
		"setup states the crown's win bar"
	)
	setup.start_button.emit_signal("pressed")
	await process_frame

	# Capital-choice phase: the chart is generated on the next idle frame, then
	# the crown's seat is confirmed (wiki: capital-choice-phase § Player choice).
	var chart: CapitalChoiceScreen = main.current_page as CapitalChoiceScreen
	_check(chart != null, "new game opens the capital chart")
	if chart == null:
		_finish()
		return
	var waited: int = 0
	while chart.model == null and waited < 120:
		await process_frame
		waited += 1
	_check(chart.model != null, "the capital chart is generated")
	_check(chart.selected_province >= 0, "the crown's recommended seat is marked")
	var seat: int = chart.selected_province
	var seat_tile: Vector2i = chart.selected_tile
	chart.confirm_button.emit_signal("pressed")
	await process_frame

	# The crown's charge is the gate before the first turn (wiki: dialogue-management
	# § Kinds, `game_start_intro`): no campaign runs behind it, and one press opens
	# the age.
	var charge: IntroScreen = main.current_page as IntroScreen
	_check(charge != null, "the crown's charge follows the capital chart")
	_check(main.current_screen == null, "no campaign runs behind the charge")
	if charge == null:
		_finish()
		return
	_check(
		_has_text(charge, FactionCatalog.name_of(0)) or _has_text(charge, "THE CROWN'S CHARGE"),
		"the charge names the crown and its title"
	)
	_check(
		_has_text(charge, str(VictoryRules.MILITARY_THRESHOLD)),
		"the charge publishes the win condition"
	)
	charge.begin_button.emit_signal("pressed")
	await process_frame

	var screen: MapScreen = main.current_screen
	_check(screen != null, "main hosts MapScreen")
	if screen == null:
		_finish()
		return
	screen.save_dir = SAVE_DIR

	_check(screen.model != null, "map model built")
	_check(screen.model.province_count() > 0, "provinces generated")
	_check(screen.capital_province == seat, "the chart's seat starts the campaign")
	_check(screen.capital_tile == seat_tile, "the chart's tile is the seat")
	_check(screen.ship_layer != null, "ship layer present")
	_check(
		screen.ship_layer.ships.size() == MapScreen.SHIP_COUNT,
		"ships spawned (%d)" % MapScreen.SHIP_COUNT
	)
	_check(screen.capital_province >= 0, "capital province chosen")
	_check(screen.canvas != null and screen.canvas.model == screen.model, "map canvas wired")
	_check(screen.hud != null, "HUD present")
	_check(screen.world != null and screen.world.region_count() == 2, "world has two regions")
	_check(
		screen.overlay._country_borders.size() >= 4,
		"country borders built for every nation"
	)
	_check(screen.play.map_seed == SETUP_SEED.to_int(), "setup seed reaches the world")
	var leaders: Dictionary = screen.play.leaders
	_check(
		leaders.size() == FactionCatalog.great_power_ids().size(),
		"every Great Power fields a leader"
	)
	_check(
		String(leaders.get(screen.player_faction, ""))
		== LeaderCatalog.default_key(screen.player_faction),
		"the human crown fields its configured leader"
	)
	_check(screen.play.court_charts != null, "every rival court holds a chart")
	_check(
		screen.play.court_charts.model_for(screen.player_faction, screen.region_index)
		== screen.visibility,
		"the human grid is the one the charts route to"
	)
	_check(
		screen.play.court_charts.known_zones(
			FactionCatalog.great_power_ids()[1], FactionCatalog.NEW_WORLD
		).is_empty(),
		"no rival has charted the New World on turn one"
	)
	_check(screen.game_menu != null, "in-game menu present")
	screen.game_menu.open()
	_check(screen.game_menu.is_open(), "in-game menu opens")
	_check(paused, "in-game menu pauses the tree")
	_check(screen.game_menu.settings_button.disabled, "in-game settings is dimmed")
	screen.game_menu.open_save()
	_check(screen.game_menu.browser.visible, "save browser opens")
	screen.game_menu.browser.slot_chosen.emit(SAVE_SLOT)
	_check(SaveStore.has_slot(SAVE_SLOT, SAVE_DIR), "in-game save writes the slot")
	_check(screen.game_menu._status.text.contains("Saved"), "save is acknowledged")
	screen.game_menu.close()
	_check(not paused, "in-game menu resumes the tree")

	screen._cycle_region()
	await process_frame
	_check(screen.region_index == 1, "region switch reaches the New World")
	_check(
		screen.model.region_id == FactionCatalog.NEW_WORLD and screen.canvas.model == screen.model,
		"New World map is drawn"
	)
	_check(
		screen.ship_layer.ships.size() == MapScreen.SHIP_COUNT,
		"New World fleets spawned"
	)
	screen._cycle_region()
	await process_frame
	_check(screen.region_index == 0, "region switch returns to the Old World")

	_check(screen.civilian_layer != null, "civilian layer present")
	_check(
		screen.civilian_layer.units.size() == MapScreen.STARTING_CIVILIANS.size(),
		"civilians muster at the capital"
	)
	_check(screen.improvements != null, "estates ledger present")

	var home_army: ArmyState = _home_army(screen)
	_check(home_army != null, "Home Army musters at the capital")
	if home_army != null:
		_check(home_army.province == screen.capital_province, "Home Army stands at the capital")
		screen.army_layer.select(home_army)
		await process_frame
		_check(screen.hud.panels.is_army_panel_open(), "army dossier opens")
		var field_before: int = home_army.count()
		MapPlayArmies.on_action(screen.play, "detach:%s" % home_army.regiments[0])
		await process_frame
		var field: ArmyState = screen.army_layer.selected_army
		_check(field != null and not field.is_home_army(), "detached army becomes a field army")
		_check(home_army.count() == field_before - 1, "Home Army keeps its remaining regiments")
		_check(
			field != null and not RegimentNames.of(field, field.regiments[0]).is_empty(),
			"the detached regiment keeps its title"
		)
		# The train (DR-20261112-07): the dossier names the offer or its refusal,
		# and a pitched train reads on the strength line.
		if field != null:
			MapPlayArmies.show_panel(screen.play, field)
			await process_frame
			_check(
				screen.hud.panels.army_panel._hospital.visible,
				"the dossier offers the field hospital train"
			)
			_check(
				not String(screen.hud.panels.army_panel._hospital.text).is_empty(),
				"the train order names itself"
			)
			HospitalTrain.apply(field)
			MapPlayArmies.show_panel(screen.play, field)
			await process_frame
			_check(
				String(screen.hud.panels.army_panel._strength.text).contains("field hospital"),
				"the strength line names the train"
			)
			_check(
				not screen.hud.panels.army_panel._hospital.visible,
				"a served train order is gone"
			)
		_check(
			screen.hud._army_label.text
			== str(screen.army_layer.regiment_count_all(MapScreen.PLAYER_FACTION)),
			"troop chip counts every region"
		)

	var estates_toggle: Button = screen.improvements._toggle
	_check(estates_toggle != null, "estates toggle present")
	screen.improvements.open()
	await process_frame
	_check(screen.improvements.is_open(), "estates ledger opens")
	_check(
		screen.improvements._data.has("counts"),
		"estates ledger builds a snapshot"
	)
	screen.improvements.close()

	MapPlayDiplomacy.open(screen.play)
	await process_frame
	_check(screen.play.diplomacy != null, "diplomacy state seeded")
	_check(
		screen.play.diplomacy.relations.size() >= 81,
		"same-region relations seeded"
	)
	_check(screen.hud.panels.is_diplomacy_open(), "court ledger opens")
	MapPlayDiplomacy.on_order(screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	_check(screen.play.diplomacy.relation(0, 1).at_war, "war order applies")
	screen.hud.panels.diplomacy_panel.select_faction(1)
	_check(
		_has_text(screen.hud.panels.diplomacy_panel._detail, "THEIR ENVOY"),
		"the court answers a declaration in its own voice"
	)
	_check(
		_has_text(screen.hud.panels.diplomacy_panel._detail, "DOSSIER"),
		"the court carries its intelligence reading"
	)
	_check(
		_has_text(screen.hud.panels.diplomacy_panel._detail, "Holds "),
		"the dossier counts the court's public behaviour"
	)
	MapPlayDiplomacy.on_order(screen.play, DiplomacyOrders.KIND_PEACE, 1, "")
	_check(not screen.play.diplomacy.relation(0, 1).at_war, "peace order applies")
	DiplomacyHud.hide(screen.hud.panels)
	_check(not screen.hud.panels.is_diplomacy_open(), "court ledger closes")

	var cues_before: int = 0
	var audio: AudioDirector = main.get_node_or_null("Audio") as AudioDirector
	var controls: AudioControls = screen.hud.get_node_or_null("AudioControls") as AudioControls
	_check(audio != null, "audio director present")
	_check(controls != null, "sound seal present")
	if audio != null:
		_check(audio.current_track_id() == MusicPlaylist.AGE_OF_DISCOVERY, "opening bed playing")
		_check(audio._ambience.playing, "sea ambience playing")
		cues_before = audio.sfx_played
		_check(audio.play_event(AudioEvents.UI_CLICK), "ui cue fires")
		_check(audio.sfx_played == cues_before + 1, "ui cue counted")
		audio.set_muted(true)
		_check(audio._active_player().volume_db == AudioDirector.SILENT_DB, "mute silences music")
		audio.set_muted(false)

	var province_id: int = _inland_province(screen)
	_check(province_id >= 0, "inland province available")
	if province_id >= 0:
		var world: Vector2 = screen.model.province_center(province_id) * MapScreen.TILE_SIZE
		MapPlayInput.on_tapped(screen.play, world)
		await process_frame
		_check(screen.selected_province == province_id, "province selection sticks")
		_check(screen.hud.panels.is_panel_open(), "province panel opens")

	await _smoke_crown_road_lens(screen)
	await _smoke_defence_lens(screen)
	var works: Dictionary = await _smoke_civilians(screen)
	await _smoke_colonists(screen)
	await _smoke_navy(screen)
	_smoke_army_recruit(screen)
	await _smoke_end_turn(screen, audio, cues_before, works)
	await _smoke_victory(screen)

	var old_screen: MapScreen = screen
	screen.game_menu.open()
	screen.game_menu.open_load()
	screen.game_menu.browser.slot_chosen.emit(SAVE_SLOT)
	var loaded: MapScreen = main.current_screen
	_check(loaded != null and loaded != old_screen, "load rebuilds the whole screen")
	if loaded == null:
		_finish()
		return
	_check(old_screen.get_parent() == null, "load clears the previous game")
	_check(loaded.play.turn == 1, "load restores the saved turn")
	_check(
		loaded.play.economy.economy.treasury == PlayerEconomy.START_TREASURY,
		"load restores the saved treasury"
	)
	_check(loaded.save_dir == SAVE_DIR, "load keeps the slot directory")
	_check(not paused, "load resumes the tree")
	loaded.game_menu.main_menu_chosen.emit()
	await process_frame
	_check(main.current_page is MainMenu, "main menu returns from play")
	_check(main.current_screen == null, "no map survives the return")
	_clean_save_dir()
	_finish()


## Map readings: the crown-road lens mounts on the real map, fills its survey
## and hands the key cartouche back when it closes.
func _smoke_crown_road_lens(screen: MapScreen) -> void:
	MapPlayInput.set_crown_lens(screen.play, true)
	await process_frame
	var lens: CrownRoadLens = screen.play.crown_lens
	_check(lens != null and lens.active, "crown road lens raises")
	_check(screen.hud.lens_legend.visible, "crown road key shown")
	_check(
		screen.hud.lens_legend.kind == LensLegend.KIND_CROWN_ROAD,
		"crown road key reads the lens"
	)
	var road: int = int(lens.survey.get("tiles", {}).get(CrownRoadSurvey.STATE_ROAD, 0))
	_check(road > 0, "crown road surveyed")
	MapPlayInput.set_crown_lens(screen.play, false)
	await process_frame
	_check(not screen.hud.lens_legend.visible, "crown road key closes")


## The defence reading mounts on the real map: the key follows it and closes
## with it, and every charted province carries a garrison or a wall line.
func _smoke_defence_lens(screen: MapScreen) -> void:
	MapPlayInput.set_defence_lens(screen.play, true)
	await process_frame
	var lens: DefenceLens = screen.play.defence_lens
	_check(lens != null and lens.active, "defence lens raises")
	_check(screen.hud.lens_legend.visible, "defence key shown")
	_check(
		screen.hud.lens_legend.kind == LensLegend.KIND_DEFENCE,
		"defence key reads the lens"
	)
	_check(
		(lens.survey.get("provinces", []) as Array).size() > 0,
		"defence reading covers the chart"
	)
	MapPlayInput.set_defence_lens(screen.play, false)
	await process_frame
	_check(not screen.hud.lens_legend.visible, "defence key closes")


## Player civilian path: select → march → work per type → cancel → train.
## Returns tiles that must resolve on end turn for post-asserts.
func _smoke_civilians(screen: MapScreen) -> Dictionary:
	var works: Dictionary = {
		"improvement": Vector2i(-1, -1),
		"road": Vector2i(-1, -1),
		"prospect": Vector2i(-1, -1),
	}
	var explorer: CivilianState = _civilian_of(screen, "explorer")
	var builder: CivilianState = _civilian_of(screen, "builder")
	var engineer: CivilianState = _civilian_of(screen, "engineer")
	_check(explorer != null and builder != null and engineer != null, "starting civilians present")
	if explorer == null or builder == null or engineer == null:
		return works

	MapPlayInput.on_tapped(
		screen.play, MapGeo.tile_center(explorer.tile.x, explorer.tile.y, MapScreen.TILE_SIZE)
	)
	await process_frame
	_check(screen.civilian_layer.selected_unit == explorer, "explorer selection sticks")
	_check(screen.hud.panels.is_civilian_panel_open(), "civilian dossier opens")

	var march_tiles: Array[Vector2i] = CivilianMovement.valid_tiles(screen.model, explorer)
	_check(not march_tiles.is_empty(), "explorer has a march tile")
	if not march_tiles.is_empty():
		var dest: Vector2i = march_tiles[0]
		var from: Vector2i = explorer.tile
		_check(
			MapPlayCivilians.try_move(
				screen.play, MapGeo.tile_center(dest.x, dest.y, MapScreen.TILE_SIZE)
			),
			"explorer marches"
		)
		_check(explorer.tile == dest and explorer.tile != from, "explorer tile advances")

	var explore_tile: Vector2i = _uncharted_land_tile(screen)
	_check(explore_tile.x >= 0, "uncharted land available")
	if explore_tile.x >= 0:
		explorer.tile = explore_tile
		explorer.moved = false
		screen.civilian_layer.select(explorer)
		MapPlayCivilians.on_action(screen.play, "explore")
		_check(explorer.is_working() and explorer.work_action() == "explore", "explore order starts")
		MapPlayCivilians.on_cancel(screen.play)
		_check(explorer.is_idle(), "explore order cancels")

	var mineral: Vector2i = _mineral_tile(screen)
	_check(mineral.x >= 0, "survey ground available")
	if mineral.x >= 0:
		explorer.tile = mineral
		screen.civilian_layer.select(explorer)
		_check(
			screen.overlay.survey_tiles.has(mineral),
			"explorer marks the survey ground"
		)
		MapPlayCivilians.on_action(screen.play, "prospect")
		_check(explorer.is_working() and explorer.work_action() == "prospect", "prospect order starts")
		works["prospect"] = mineral

	var work_tile: Vector2i = _owned_resource_tile(screen, mineral)
	_check(work_tile.x >= 0, "owned resource tile for builder")
	if work_tile.x >= 0:
		builder.tile = work_tile
		var resource: int = screen.model.resource_at(work_tile.x, work_tile.y)
		if ImprovementCatalog.needs_prospecting(resource):
			screen.land_works.set_prospected(
				MapScreen.PLAYER_FACTION, screen.model, work_tile
			)
		screen.civilian_layer.select(builder)
		MapPlayCivilians.on_action(screen.play, "build_improvement")
		_check(builder.is_working(), "builder improvement starts")
		works["improvement"] = work_tile

	var road_tile: Vector2i = _owned_roadable_tile(screen, [work_tile, mineral])
	_check(road_tile.x >= 0, "owned roadable tile for engineer")
	if road_tile.x >= 0:
		engineer.tile = road_tile
		screen.civilian_layer.select(engineer)
		var options: Array[Dictionary] = CivilianWork.options(
			screen.model, engineer, screen.land_works, screen.civilian_layer.units,
			screen.stockpile, screen.visibility
		)
		_check(_options_has(options, "build_road"), "engineer offers build_road")
		_check(_options_has(options, "build_port"), "engineer offers build_port")
		_check(_options_has(options, "build_fort"), "engineer offers build_fort")
		MapPlayCivilians.on_action(screen.play, "build_road")
		_check(engineer.is_working() and engineer.work_action() == "build_road", "road order starts")
		works["road"] = road_tile

	var units_before: int = screen.civilian_layer.units.size()
	var capital_world: Vector2 = screen.model.province_center(screen.capital_province) * MapScreen.TILE_SIZE
	MapPlayInput.select_province(screen.play, screen.capital_province, capital_world)
	await process_frame
	MapPlayInput.on_panel_action(screen.play, "train_explorer")
	_check(
		screen.civilian_layer.units.size() == units_before + 1,
		"capital trains an explorer"
	)
	return works


## Colonist path: the home squadron takes an idle civilian aboard and puts it
## ashore again (DR-20261109-17). The sortie itself stays in unit tests: sailing
## the home fleet would zero the trade holds the turn check below needs.
func _smoke_colonists(screen: MapScreen) -> void:
	var capital: int = screen.play.capital_province
	var home: FleetState = screen.ship_layer.home_fleet(capital)
	_check(home != null, "home squadron waits at the capital")
	var colonist: CivilianState = _idle_civilian(screen, capital)
	_check(colonist != null, "an idle colonist is available")
	if home == null or colonist == null:
		return
	screen.ship_layer.select(screen.ship_layer.ship_for(home))
	await process_frame
	_check(screen.hud.panels.is_fleet_panel_open(), "fleet dossier opens for the crew")
	var crew: Dictionary = MapPlayCivilianVoyage.crew(screen.play, home)
	_check(not (crew["embark"] as Array).is_empty(), "the dossier offers the colonist")
	MapPlayCivilianVoyage.on_action(screen.play, "crew:embark:%d" % colonist.id)
	_check(colonist.is_embarked(), "the colonist boards")
	_check(colonist.tile.x < 0, "an embarked civilian leaves the map")
	MapPlayCivilianVoyage.on_action(screen.play, "crew:land:%d" % capital)
	_check(not colonist.is_embarked(), "the colonist goes ashore")
	_check(colonist.tile.x >= 0, "the colonist holds a shore tile")
	await process_frame


## Player navy path: select a fleet and spend its one move.
func _smoke_navy(screen: MapScreen) -> void:
	var ship: Ship = _player_ship_at_sea(screen)
	_check(ship != null, "player fleet at sea")
	if ship == null:
		return
	var fleet: FleetState = screen.ship_layer.fleet_of(ship)
	screen.ship_layer.select(ship)
	await process_frame
	_check(screen.ship_layer.selected() == ship, "fleet selection sticks")
	_check(screen.hud.panels.is_fleet_panel_open(), "fleet dossier opens")
	_check(
		MapPlayFleetMissions.rows(screen.play, fleet).size() > 0,
		"fleet dossier offers a station"
	)
	# The dossier prints the combat maths the resolver fights with, and the map
	# marker flies the squadron's hulls (wiki: ships-and-naval § Naval Strength).
	_check(screen.hud._fleet_panel._strength.visible, "fleet strength block shows")
	_check(
		screen.hud._fleet_panel._strength._strength.text.contains("FRP"),
		"fleet strength names its weights"
	)
	_check(
		screen.ship_layer.ship_for(fleet).hull_count == fleet.ship_count(),
		"fleet marker flies the squadron's hulls"
	)
	MapPlayFleets.on_action(screen.play, "mission:patrol")
	_check(
		fleet.mission == FleetState.Mission.PATROL and fleet.moved,
		"patrol station applies and spends the move"
	)
	# Give the move back so the smoke also proves the sail path.
	fleet.moved = false
	var zones: Array = NavalMovement.destination_zones(screen.model, fleet)
	_check(not zones.is_empty(), "fleet has a sail destination")
	if zones.is_empty():
		return
	var zone: int = int(zones[0])
	var tile: Vector2i = screen.model.sea_zones[zone].tiles[0]
	_check(MapPlayFleets.try_order(screen.play, tile), "fleet sails")
	_check(fleet.sea_zone == zone and fleet.moved, "fleet spends its move")
	_check(fleet.mission == FleetState.Mission.NONE, "sailing clears the station")


## Army training is live: the recruit order musters a regiment into the Home
## Army and spends the ledger.
func _smoke_army_recruit(screen: MapScreen) -> void:
	var home: ArmyState = _home_army(screen)
	if home == null:
		return
	var before: int = home.count()
	# The civilian drills earlier in the smoke spent the opening purse; top it
	# up so the muster row is payable, then prove the order debits it.
	screen.economy.economy.add_treasury(RegimentCatalog.treasury_cost("peasant_levies"))
	var treasury: int = screen.economy.economy.treasury
	var fabric: int = screen.economy.economy.quantity("fabric")
	MapPlayArmyMuster.recruit(screen.play, "peasant_levies")
	_check(home.count() == before + 1, "recruit musters a regiment")
	_check(
		not home.name_of(home.regiments[home.count() - 1]).is_empty(),
		"the mustered regiment is christened"
	)
	_check(screen.economy.economy.treasury < treasury, "recruit spends treasury")
	_check(screen.economy.economy.quantity("fabric") < fabric, "recruit spends fabric")
	_check(
		screen.hud._army_label.text
		== str(screen.army_layer.regiment_count_all(MapScreen.PLAYER_FACTION)),
		"troop chip counts the new regiment"
	)


func _smoke_end_turn(
	screen: MapScreen, audio: AudioDirector, cues_before: int, works: Dictionary
) -> void:
	var turn_before: int = screen.turn
	MapPlayTurn.end_turn(screen.play)
	await process_frame
	# A rival proposal suspends the phase until the court answers; accept it so
	# the calendar can close (wiki: diplomacy § Court proposals).
	if DiplomacyProposals.has_pending(screen.play.diplomacy, MapScreen.PLAYER_FACTION):
		_check(screen.turn == turn_before, "a rival proposal holds the calendar")
		_check(
			screen.hud.panels.diplomacy_panel._call_box.visible,
			"the court opens for the proposal"
		)
		MapCourtOrders.apply(
			screen.play, DiplomacyProposals.KIND_ACCEPT, MapScreen.PLAYER_FACTION, ""
		)
		await process_frame
		_check(
			not DiplomacyProposals.has_pending(
				screen.play.diplomacy, MapScreen.PLAYER_FACTION
			),
			"the court answer closes the proposal"
		)
	_check(screen.turn == turn_before + 1, "end turn advances calendar")
	# The crown's sheet files the resolved turn and opens when it has news
	# (wiki: the-gazette § When it appears).
	_check(screen.play.gazette != null, "the gazette keeps its watchlist")
	_check(screen.play.gazette.has_sheet(turn_before), "the resolved turn is filed")
	if not Gazette.is_empty(screen.play.gazette.sheet_for(turn_before)):
		_check(screen.hud.gazette_plate.is_shown(), "news opens the soft plate")
		screen.hud.gazette_plate.dismiss()
		_check(not screen.hud.gazette_plate.is_shown(), "one press sets the sheet aside")
	_check(screen.play.ai_trace.size() == 5, "rival AI courts took their turn")
	_check(_rival_research_started(screen), "rivals filled their research slots")
	_check(screen.economy != null, "economy wired")
	_check(
		screen.treasury == screen.economy.economy.treasury,
		"treasury reads from the economy ledger"
	)
	_check(screen.economy.economy.total_units() > 0, "stockpile holds goods")
	_check(
		screen.economy.extraction().size() > 0,
		"owned provinces yield commodities"
	)
	screen.economy.open_panel()
	await process_frame
	_check(screen.hud.panels.is_economy_open(), "ledger opens")
	_check(
		int(screen.economy.trade_cargo().get("holds", 0)) > 0,
		"the home fleet carries trade cargo"
	)
	var grain_before: int = screen.economy.economy.quantity("grain")
	screen.economy._on_trade("grain", 1, true)
	_check(
		screen.economy.market.book.pending_buy_units(screen.player_faction) == 1,
		"the ledger stages imports against cargo holds"
	)
	_clear_market(screen)
	_check(
		screen.economy.economy.quantity("grain") == grain_before + 1,
		"the turn-end auction fills the import"
	)
	var offers: Array[Dictionary] = screen.economy.market.minor_offers
	_check(not offers.is_empty(), "the minor courts publish their harvest")
	if not offers.is_empty():
		var offer: Dictionary = offers[0]
		var offer_id: String = String(offer["id"])
		var offer_good: String = String(offer["commodity"])
		var offer_stock: int = screen.economy.economy.quantity(offer_good)
		screen.hud.panels.economy_panel.emit_signal("offer_requested", offer_id, 1)
		_check(
			screen.economy.market.book.pending_buy_units(screen.player_faction) == 1,
			"the ledger stages a bid on a court's offer"
		)
		_clear_market(screen)
		_check(
			screen.economy.economy.quantity(offer_good) == offer_stock + 1,
			"the turn-end auction fills the offer bid"
		)
	screen.economy._on_production("lumber", 1)
	_check(
		screen.economy.economy.production.assignment_units("lumber") == 1,
		"production assignment sticks"
	)
	# A two-turn alloy names its wait on the row, so a phone player is not left
	# wondering why the stockpile did not move (DR-20261112-11).
	var production_body: Node = screen.hud.panels.economy_panel.page_body(
		EconomyPanel.TAB_PRODUCTION
	)
	_check(_has_text(production_body, "2t"), "the alloy rows name their two-turn wait")
	screen.hud.panels.hide_economy()
	_check(not screen.hud.panels.is_economy_open(), "ledger closes")
	_check(
		TurnTime.year_for_turn(screen.turn) == TurnTime.START_YEAR + 2,
		"turn maps to expected year"
	)

	var improvement: Vector2i = works.get("improvement", Vector2i(-1, -1))
	if improvement.x >= 0:
		_check(
			screen.land_works.improvement_at(screen.model, improvement) == 1,
			"builder work resolves on end turn"
		)
	var road: Vector2i = works.get("road", Vector2i(-1, -1))
	if road.x >= 0:
		_check(
			screen.land_works.transport_at(screen.model, road) >= LandWorks.TRANSPORT_ROAD,
			"engineer road resolves on end turn"
		)
	var prospect: Vector2i = works.get("prospect", Vector2i(-1, -1))
	if prospect.x >= 0:
		_check(
			screen.land_works.is_prospected(MapScreen.PLAYER_FACTION, screen.model, prospect),
			"prospect completes on end turn"
		)

	if audio != null:
		_check(audio.sfx_played >= cues_before + 3, "turn cues fired")
		# Only war resolves a battle now; either bed is fine, silence is not.
		var bed: String = audio.current_track_id()
		_check(
			bed == MusicPlaylist.AGE_OF_DISCOVERY or bed == MusicPlaylist.BROADSIDES,
			"music keeps a bed after the turn (%s)" % bed
		)


## Campaign end on the live scene: the plate appears and turns stay shut. The
## smoke map is too small to win by province count, so the record is seeded.
func _smoke_victory(screen: MapScreen) -> void:
	screen.play.victory = VictoryState.military(MapScreen.PLAYER_FACTION, screen.turn)
	screen.hud.show_victory(
		screen.play.victory,
		MapScreen.PLAYER_FACTION,
		VictoryRules.old_world_holdings(screen.world, MapScreen.PLAYER_FACTION)
	)
	await process_frame
	_check(screen.hud.is_victory_shown(), "campaign plate shows")
	_check(screen.hud._end_turn_button.disabled, "end turn seal closes")
	var turn_before: int = screen.turn
	MapPlayTurn.end_turn(screen.play)
	_check(screen.turn == turn_before, "decided campaign refuses another turn")
	screen.hud.victory_overlay.dismiss()
	_check(not screen.hud.is_victory_shown(), "final view dismisses the plate")
	# Calendar cap: an undecided age closes on its last full turn, with the same
	# sealed plate (wiki: turn-time-mapping § Campaign calendar cap).
	screen.play.victory = null
	screen.play.infinite_mode = false
	screen.play.turn = TurnTime.cap_turn()
	MapPlayTurn.end_turn(screen.play)
	await process_frame
	if DiplomacyProposals.has_pending(screen.play.diplomacy, MapScreen.PLAYER_FACTION):
		MapCourtOrders.apply(
			screen.play, DiplomacyProposals.KIND_ACCEPT, MapScreen.PLAYER_FACTION, ""
		)
		await process_frame
	_check(screen.play.campaign_halted, "calendar cap closes an undecided age")
	_check(screen.turn == TurnTime.cap_turn(), "cap keeps the last full turn")
	_check(screen.hud.is_victory_shown(), "campaign-complete plate shows")
	_check(
		screen.hud.victory_overlay._title.text == "CAMPAIGN COMPLETE",
		"plate names the calendar end"
	)
	_check(screen.hud._end_turn_button.disabled, "cap keeps the turn seal shut")


func _map_screen(main: Node) -> MapScreen:
	for child in main.get_children():
		if child is MapScreen:
			return child as MapScreen
	return null


func _civilian_of(screen: MapScreen, type_id: String) -> CivilianState:
	for unit: CivilianState in screen.civilian_layer.units:
		if unit != null and unit.type_id == type_id and unit.owner == MapScreen.PLAYER_FACTION:
			return unit
	return null


## First idle civilian of the crown standing in this province.
func _idle_civilian(screen: MapScreen, province_id: int) -> CivilianState:
	for unit: CivilianState in screen.civilian_layer.units:
		if unit == null or unit.owner != MapScreen.PLAYER_FACTION:
			continue
		if unit.is_embarked() or unit.is_working():
			continue
		if screen.model.province_at(unit.tile.x, unit.tile.y) == province_id:
			return unit
	return null


func _player_ship_at_sea(screen: MapScreen) -> Ship:
	for ship: Ship in screen.ship_layer.ships:
		var fleet: FleetState = screen.ship_layer.fleet_of(ship)
		if fleet != null and fleet.owner == MapScreen.PLAYER_FACTION and fleet.is_at_sea():
			return ship
	return null


func _home_army(screen: MapScreen) -> ArmyState:
	for army: ArmyState in screen.army_layer.armies:
		if army.owner == MapScreen.PLAYER_FACTION and army.is_home_army():
			return army
	return null


func _inland_province(screen: MapScreen) -> int:
	for province: ProvinceState in screen.model.provinces:
		if not province.coastal and province.area > 30:
			return province.id
	if screen.model.provinces.is_empty():
		return -1
	return int(screen.model.provinces[0].id)


func _uncharted_land_tile(screen: MapScreen) -> Vector2i:
	if screen.visibility == null:
		return Vector2i(-1, -1)
	for province: ProvinceState in screen.model.provinces:
		if screen.visibility.is_province_fully_visible(int(province.id)):
			continue
		# Exploring a Minor/Tribe province needs a Consulate (wiki:
		# civilian-units § Work Order Summary, Refs #3753 R4).
		if (
			province.owner != MapScreen.PLAYER_FACTION
			and FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER
		):
			continue
		if province.tiles.is_empty():
			continue
		return province.tiles[0]
	return Vector2i(-1, -1)


func _mineral_tile(screen: MapScreen) -> Vector2i:
	for province: ProvinceState in screen.model.provinces:
		# Explorer work in a Minor/Tribe province needs a Consulate, so the
		# smoke needs a tile the crown may actually work on turn one (wiki:
		# civilian-units § Work Order Summary, Refs #3753 R4).
		if (
			province.owner != MapScreen.PLAYER_FACTION
			and FactionCatalog.type_of(province.owner) != FactionCatalog.Type.GREAT_POWER
		):
			continue
		for tile: Vector2i in province.tiles:
			# A survey target: charted prospectable ground this crown has not
			# read yet (wiki: fog-and-exploration § Prospecting;
			# DR-20261111-26).
			if MineralSurvey.can_prospect(
				screen.model, screen.land_works, MapScreen.PLAYER_FACTION, tile,
				screen.visibility
			):
				return tile
	return Vector2i(-1, -1)


func _owned_resource_tile(screen: MapScreen, avoid: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var fallback: Vector2i = Vector2i(-1, -1)
	for province: ProvinceState in screen.model.provinces:
		if province.owner != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if tile == avoid:
				continue
			var resource: int = screen.model.resource_at(tile.x, tile.y)
			if resource < 0:
				continue
			if screen.land_works.improvement_at(screen.model, tile) > 0:
				continue
			if not ImprovementCatalog.needs_prospecting(resource):
				return tile
			if fallback.x < 0:
				fallback = tile
	return fallback


func _owned_roadable_tile(screen: MapScreen, avoid: Array[Vector2i]) -> Vector2i:
	for province: ProvinceState in screen.model.provinces:
		if province.owner != MapScreen.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			if avoid.has(tile):
				continue
			if screen.land_works.transport_at(screen.model, tile) >= LandWorks.TRANSPORT_ROAD:
				continue
			return tile
	return Vector2i(-1, -1)


func _options_has(options: Array[Dictionary], action: String) -> bool:
	for option: Dictionary in options:
		if String(option.get("action", "")) == action:
			return true
	return false


## Runs one world-market clearing pass for the human ledger, as the turn does.
func _clear_market(screen: MapScreen) -> void:
	var cargo: Dictionary = screen.economy.trade_cargo()
	MarketClearing.clear(
		screen.economy.market,
		screen.play.world,
		{screen.player_faction: screen.economy.economy},
		{screen.player_faction: int(cargo.get("clear_free", cargo.get("free", 0)))},
		{"diplomacy": screen.play.diplomacy}
	)


## True when at least one rival court put a tech into a research slot, proving
## the economy adapter wired AiResearchPlanner (DR-20261109-20).
func _rival_research_started(screen: MapScreen) -> bool:
	if screen.play.ai == null:
		return false
	for faction: int in FactionCatalog.great_power_ids():
		if faction == screen.play.player_faction:
			continue
		var rival: PlayerEconomy = screen.play.ai.economy_for(faction)
		for slot in rival.research.slots.size():
			if not rival.research.tech_at(slot).is_empty():
				return true
	return false


## Recursive label text search: the smoke reads what the player would read.
func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("e2e_smoke: PASS %s" % label)
	else:
		printerr("e2e_smoke: FAIL %s" % label)
		_failures.append(label)


func _clean_save_dir() -> void:
	var path: String = ProjectSettings.globalize_path(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _finish() -> void:
	if _failures.is_empty():
		print("e2e_smoke: all asserts passed")
		quit(0)
	else:
		printerr(
			"e2e_smoke: %d assert(s) failed: %s"
			% [_failures.size(), ", ".join(_failures)]
		)
		quit(1)
