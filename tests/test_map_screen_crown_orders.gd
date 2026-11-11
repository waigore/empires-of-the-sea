extends GdToolsTest
## Integration: crown orders through the real map screen — civilians, training,
## estates and setup leaders. The world view (map build, camera, chart/fog,
## turn flow) lives in test_map_screen, so each native suite stays inside the
## coverage runner's per-suite timeout.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	# Free immediately: queue_free leaves prior screens processing fog/ships and
	# starves the suite under coverage (process timeout).
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null

func test_civilians_muster_at_the_capital() -> void:
	assert_eq(
		_screen.civilian_layer.units.size(), MapScreen.STARTING_CIVILIANS.size()
	)
	assert_eq(
		_screen.hud._civilian_label.text, str(MapScreen.STARTING_CIVILIANS.size())
	)
	for unit: CivilianState in _screen.civilian_layer.units:
		assert_eq(unit.owner, MapScreen.PLAYER_FACTION)
		assert_eq(
			_screen.model.province_at(unit.tile.x, unit.tile.y), _screen.capital_province
		)


func test_tapping_a_civilian_opens_its_dossier() -> void:
	var unit: CivilianState = _screen.civilian_layer.units[0]
	MapPlayInput.on_tapped(
		_screen.play, MapGeo.tile_center(unit.tile.x, unit.tile.y, MapScreen.TILE_SIZE)
	)
	assert_eq(_screen.civilian_layer.selected_unit, unit)
	assert_true(_screen.hud.panels.is_civilian_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())


func test_a_work_order_costs_materials_and_completes_on_end_turn() -> void:
	var tile: Vector2i = _buildable_owned_resource_tile()
	assert_true(tile.x >= 0, "map has an owned resource a Builder can raise")
	var builder: CivilianState = _screen.civilian_layer.units[1]
	assert_eq(builder.type_id, "builder")
	builder.tile = tile
	_screen.civilian_layer.select(builder)
	var lumber_before: int = int(_screen.stockpile["lumber"])
	MapPlayCivilians.on_action(_screen.play, "build_improvement")
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	assert_true(builder.is_working())
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 1)
	assert_true(builder.is_idle())


func test_training_a_civilian_spends_treasury_and_paper() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	var treasury_before: int = _screen.treasury
	var paper_before: int = int(_screen.stockpile["paper"])
	MapPlayInput.on_panel_action(_screen.play, "train_explorer")
	assert_eq(_screen.treasury, treasury_before - 1000)
	assert_eq(int(_screen.stockpile["paper"]), paper_before - 2)
	assert_eq(_screen.civilian_layer.units.size(), units_before + 1)


func test_training_is_refused_outside_the_capital() -> void:
	var province_id: int = Fixture.foreign_province(_screen.model)
	MapPlayInput.select_province(
		_screen.play, province_id, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	var units_before: int = _screen.civilian_layer.units.size()
	var treasury_before: int = _screen.treasury
	MapPlayInput.on_panel_action(_screen.play, "train_explorer")
	assert_eq(_screen.civilian_layer.units.size(), units_before)
	assert_eq(_screen.treasury, treasury_before)


func test_training_a_rail_builder_waits_for_early_steam_engine() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	MapPlayInput.on_panel_action(_screen.play, "train_rail_builder")
	assert_eq(_screen.civilian_layer.units.size(), units_before)

	_screen.play.economy.economy.research.unlock("early_steam_engine")
	var treasury_before: int = _screen.treasury
	MapPlayInput.on_panel_action(_screen.play, "train_rail_builder")
	assert_eq(_screen.civilian_layer.units.size(), units_before + 1)
	assert_eq(_screen.civilian_layer.units.back().type_id, "rail_builder")
	assert_eq(_screen.treasury, treasury_before - 2000)


func test_unknown_civilian_orders_do_not_train() -> void:
	MapPlayInput.select_province(_screen.play, _screen.capital_province, _capital_point())
	var units_before: int = _screen.civilian_layer.units.size()
	MapPlayInput.on_panel_action(_screen.play, "train_dragon")
	assert_eq(_screen.civilian_layer.units.size(), units_before)


func test_region_switch_keeps_the_civilian_roster_and_works() -> void:
	var builder: CivilianState = _screen.civilian_layer.units[1]
	var resource: Vector2i = _buildable_owned_resource_tile()
	assert_true(resource.x >= 0, "map has an owned resource a Builder can raise")
	builder.tile = resource
	_screen.civilian_layer.select(builder)
	MapPlayCivilians.on_action(_screen.play, "build_improvement")
	var works: LandWorks = _screen.land_works

	_screen._cycle_region()
	assert_eq(_screen.civilian_layer.units.size(), 0, "no crown holdings in the New World")

	_screen._cycle_region()
	assert_eq(_screen.civilian_layer.units.size(), MapScreen.STARTING_CIVILIANS.size())
	assert_true(_screen.civilian_layer.units.has(builder))
	assert_eq(builder.tile, resource)
	assert_true(builder.is_working())
	assert_eq(_screen.land_works, works)


func test_each_region_keeps_its_own_fleets() -> void:
	var old_fleet: FleetState = _screen.ship_layer.fleets[0]
	var old_zone: int = old_fleet.sea_zone

	_screen._cycle_region()
	for fleet: FleetState in _screen.ship_layer.fleets:
		assert_false(fleet == old_fleet, "the New World fields its own squadrons")

	_screen._cycle_region()
	assert_eq(_screen.ship_layer.fleets[0], old_fleet)
	assert_eq(old_fleet.sea_zone, old_zone)


func test_end_turn_restores_orders_in_the_region_off_screen() -> void:
	var fleet: FleetState = _screen.ship_layer.fleets[0]
	fleet.moved = true
	_screen._cycle_region()
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_false(fleet.moved, "a fleet must be ready when its map reopens")


func test_battles_resolve_in_the_region_off_screen() -> void:
	_screen._cycle_region()
	assert_eq(_screen.region_index, 1)
	var zone: int = _screen.model.sea_zones[0].id
	var first: FleetState = null
	var second: FleetState = null
	for fleet: FleetState in _screen.ship_layer.fleets:
		if first == null:
			first = fleet
		elif second == null and fleet.owner != first.owner:
			second = fleet
		else:
			fleet.location = FleetState.Location.IN_PORT
			fleet.province = _screen.model.provinces[0].id
	assert_not_null(first)
	assert_not_null(second)
	for fleet: FleetState in [first, second]:
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = zone
	first.set_hulls(["a"], {"a": "carrack"})
	second.set_hulls(["b"], {"b": "fluyte"})
	DiplomacyRules.declare_war(_screen.play.diplomacy, first.owner, second.owner)
	var hulls_before: int = first.ship_count() + second.ship_count()
	var toasts_before: int = _screen.hud.despatches.lane.get_child_count()

	_screen._cycle_region()
	assert_eq(_screen.region_index, 0)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	var hulls_after: int = first.ship_count() + second.ship_count()
	if hulls_after == hulls_before:
		assert_ne(
			first.sea_zone, second.sea_zone,
			"a beaten squadron that survives withdraws to adjacent water"
		)
	else:
		assert_lt(hulls_after, hulls_before)
	assert_gt(_screen.hud.despatches.lane.get_child_count(), toasts_before)


func test_empire_counters_survive_a_region_switch() -> void:
	var ships: int = _screen.economy.fleet_ships()
	assert_gt(ships, 0)
	_screen._cycle_region()
	assert_eq(_screen.economy.fleet_ships(), ships, "navy upkeep follows the empire")
	assert_eq(_screen.hud._fleet_label.text, str(ships))
	assert_eq(
		_screen.hud._civilian_label.text, str(MapScreen.STARTING_CIVILIANS.size())
	)
	var need: int = int(_screen.economy.projected()["consumption"]["navy_demand"])
	assert_eq(need, ships * ShipEconomy.FOOD_UPKEEP_PER_SHIP)


func test_the_civilian_chip_opens_the_whole_empire_roster() -> void:
	_screen.hud.civilian_roster_pressed.emit()
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	assert_not_null(roster)
	assert_true(roster.is_open())
	assert_eq(int(roster._snapshot["total"]), MapScreen.STARTING_CIVILIANS.size())
	assert_eq(roster._head.region, CivilianRoster.REGION_ALL)
	assert_eq(roster._head.type_id, CivilianRosterHead.TYPE_ALL)
	roster.close()
	assert_false(roster.is_open())


func test_the_roster_filters_the_new_world_and_visits_its_civilian() -> void:
	_screen._cycle_region()
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	var tile: Vector2i = _screen.model.provinces[0].tiles[0]
	var unit: CivilianState = _screen.civilian_layer.add_unit(
		_screen.play.player_faction, "merchant", tile
	)
	_screen._cycle_region()
	assert_eq(_screen.region_index, FactionCatalog.OLD_WORLD)

	_screen.hud.civilian_roster_pressed.emit()
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	roster._head.filter_changed.emit(CivilianRoster.REGION_NEW, "merchant")
	assert_eq(
		CivilianRoster.count(roster._snapshot, CivilianRoster.REGION_NEW, "merchant"), 1
	)
	var row: CivilianRosterRow = _first_row(roster)
	assert_not_null(row)
	assert_eq(int(row.data["unit_id"]), unit.id)
	assert_eq(String(row.data["province_name"]), _screen.world.region(1).province_name(
		_screen.world.region(1).province_at(tile.x, tile.y)
	))

	row._visit_unit()
	assert_false(roster.is_open(), "visiting closes the ledger")
	assert_eq(_screen.region_index, FactionCatalog.NEW_WORLD)
	assert_eq(_screen.civilian_layer.selected_unit, unit)
	assert_true(_screen.hud.panels.is_civilian_panel_open())


func test_the_roster_filters_by_region_craft_and_empty_view() -> void:
	_screen.hud.civilian_roster_pressed.emit()
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	var head: CivilianRosterHead = roster._head
	head._region_buttons[CivilianRoster.REGION_OLD].pressed.emit()
	assert_eq(roster._region, CivilianRoster.REGION_OLD)
	assert_eq(CivilianRoster.count(roster._snapshot, roster._region), 3)
	head._type_buttons["explorer"].pressed.emit()
	assert_eq(roster._type, "explorer")
	assert_eq(CivilianRoster.count(roster._snapshot, roster._region, roster._type), 1)
	head._type_buttons["explorer"].pressed.emit()
	assert_eq(roster._type, CivilianRosterHead.TYPE_ALL, "tapping the craft clears it")
	head._type_buttons[CivilianRosterHead.TYPE_ALL].pressed.emit()
	head._region_buttons[CivilianRoster.REGION_NEW].pressed.emit()
	assert_true(roster._empty.visible, "an empty world gets an explanation")
	assert_true(String(roster._empty.text).contains("No civilians"))
	assert_true(roster.is_open())


func test_the_roster_opens_and_closes_from_the_keyboard() -> void:
	var roster: CivilianRosterPanel = _screen.hud.civilian_roster
	var toggle := InputEventAction.new()
	toggle.action = InputActions.CIVILIAN_ROSTER
	toggle.pressed = true
	roster._unhandled_input(toggle)
	assert_true(roster.is_open())
	roster._unhandled_input(toggle)
	assert_false(roster.is_open())
	var cancel := InputEventAction.new()
	cancel.action = InputActions.CANCEL
	cancel.pressed = true
	roster._unhandled_input(toggle)
	roster._input(cancel)
	assert_false(roster.is_open(), "Escape closes the ledger")


## The summary's door opens the full sheet, and back closes the sheet before the
## court hears the press (REQ-P5-01, REQ-P5-07; DR-20261110-25).
func test_the_full_dossier_opens_from_the_court_and_back_closes_it() -> void:
	_screen.play.diplomacy.apply_delta(0, 1, 22.0, "dossierSample")
	MapPlayDiplomacy.open(_screen.play)
	var panel: DiplomacyPanel = _screen.hud.panels.diplomacy_panel
	assert_true(panel.selected_faction() >= 0, "the court opens on a known crown")
	var button: Button = _find_button(panel._detail, "dossier")
	assert_not_null(button, "the summary says it has a full copy")
	button.pressed.emit()
	var sheet: CourtDossierScreen = _screen.hud.dossier_screen
	assert_true(sheet.is_open(), "the sheet is up over the court")
	assert_true(_has_text(sheet._body, "SUSPICION"))
	assert_true(_has_text(sheet._body, "BEHAVIOUR & BUILD NOTES"))
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS
	assert_true(BackRequest.handle(_screen.play, _screen.improvements))
	assert_false(sheet.is_open(), "back closes the sheet")
	assert_true(DiplomacyHud.is_open(_screen.hud.panels), "the court stays open")


func test_the_back_gesture_closes_the_roster_first() -> void:
	_screen.hud.civilian_roster.open()
	assert_true(_screen.hud.civilian_roster.is_open())
	BackRequest._last_ms = -BackRequest.DEBOUNCE_MS
	assert_true(BackRequest.handle(_screen.play, _screen.improvements))
	assert_false(_screen.hud.civilian_roster.is_open(), "back closes the ledger only")


func _find_button(node: Node, needle: String) -> Button:
	if node is Button and String((node as Button).text).contains(needle):
		return node as Button
	for child: Node in node.get_children():
		var found: Button = _find_button(child, needle)
		if found != null:
			return found
	return null


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false


func _first_row(roster: CivilianRosterPanel) -> CivilianRosterRow:
	for child: Node in roster._rows.get_children():
		if child is CivilianRosterRow:
			return child
	return null


func test_estates_ledger_dispatches_a_builder_and_shows_the_yield() -> void:
	var tile: Vector2i = _capital_estate_tile()
	assert_true(tile.x >= 0, "capital has an owned neighbouring land tile")
	_screen.improvements.open()
	assert_true(_screen.improvements.is_open())
	assert_true(int(_screen.improvements._data["counts"]["estates"]) > 0)
	var builder: CivilianState = _screen.civilian_layer.units[1]
	assert_eq(builder.type_id, "builder")
	var lumber_before: int = int(_screen.stockpile["lumber"])
	var timber_before: int = int(_screen.stockpile.get("timber", 0))
	MapPlayImprovements.on_action(_screen.play, "build", tile)
	assert_true(builder.is_working())
	assert_eq(builder.work_tile(), tile)
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	var row: Dictionary = ImprovementLedger.estate_row(
		_screen.model, _screen.land_works, _screen.civilian_layer.units,
		_screen.stockpile, MapScreen.PLAYER_FACTION, tile, _screen.capital_tile
	)
	assert_eq(String(row["status"]), "building")

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 1)
	assert_true(builder.is_idle())
	assert_eq(int(_screen.stockpile["lumber"]), lumber_before - 1)
	assert_eq(int(_screen.stockpile.get("timber", 0)), timber_before + 1)


func test_estates_ledger_cancels_a_build_and_returns_the_builder() -> void:
	var tile: Vector2i = _capital_estate_tile()
	assert_true(tile.x >= 0, "capital has an owned neighbouring land tile")
	var builder: CivilianState = _screen.civilian_layer.units[1]
	var origin: Vector2i = builder.tile
	MapPlayImprovements.on_action(_screen.play, "build", tile)
	assert_true(builder.is_working())
	MapPlayImprovements.on_action(_screen.play, "cancel", tile)
	assert_true(builder.is_idle())
	assert_eq(builder.tile, origin)
	assert_eq(_screen.land_works.improvement_at(_screen.model, tile), 0)


func test_tapping_a_survey_mark_starts_the_survey() -> void:
	var play: PlaySession = _screen.play
	var explorer: CivilianState = _explorer()
	assert_not_null(explorer, "the crown fields an Explorer")
	if explorer == null:
		return
	var province: int = _screen.model.province_at(explorer.tile.x, explorer.tile.y)
	var ground: Array[Vector2i] = MineralSurvey.unsurveyed_in_province(
		_screen.model, _screen.land_works, play.player_faction, province,
		_screen.visibility
	)
	if ground.size() < 2:
		return
	var stand: Vector2i = ground[0]
	var target: Vector2i = stand
	for tile: Vector2i in ground:
		if absi(tile.x - stand.x) + absi(tile.y - stand.y) > 1:
			target = tile
			break
	if target == stand:
		return
	explorer.tile = stand
	_screen.civilian_layer.select(explorer)
	assert_true(_screen.overlay.survey_tiles.has(stand), "the marks cover the province")
	assert_true(_detail_text().contains("Survey"), "the dossier carries the survey row")
	# A tap on marked ground starts the survey without a march.
	assert_true(
		MapPlayCivilians.try_move(
			play, MapGeo.tile_center(target.x, target.y, MapScreen.TILE_SIZE)
		),
		"the tap is consumed by the survey"
	)
	assert_true(explorer.is_working())
	assert_eq(explorer.work_action(), "prospect")
	assert_eq(explorer.work_tile(), target)
	# A working Explorer takes no second survey.
	assert_false(MapPlayCivilians.try_survey(play, explorer, stand))
	await get_tree().process_frame
	# Ending the turn uncovers the ground for the court that paid for it.
	MapPlayTurn.end_turn(play)
	Fixture.settle(play)
	assert_true(
		_screen.land_works.is_prospected(play.player_faction, _screen.model, target),
		"the survey lands on end turn"
	)


func test_a_rivals_survey_never_names_its_find() -> void:
	var play: PlaySession = _screen.play
	var rival: int = -1
	for faction: int in FactionCatalog.great_power_ids():
		if faction != play.player_faction:
			rival = faction
			break
	assert_true(rival >= 0, "the chart seats more than one Great Power")
	var report: Dictionary = {"owner": rival, "find": "iron"}
	var line: String = MapPlayCivilians._survey_line(play, report, "Explorer", "Cádiz")
	assert_false(line.contains("iron"), "a rival's uncover is never ours to read")
	assert_true(line.contains("Explorer"))
	# The court that paid for the survey does hear what it found.
	report = {"owner": play.player_faction, "find": "iron"}
	line = MapPlayCivilians._survey_line(play, report, "Explorer", "Cádiz")
	assert_true(line.contains("iron"))
	assert_true(line.contains("Cádiz"))
	# An empty find is a real answer, not silence (DR-20261111-26).
	report = {"owner": play.player_faction, "find": ""}
	line = MapPlayCivilians._survey_line(play, report, "Explorer", "Cádiz")
	assert_true(line.contains("no mineral"))


func test_new_game_assigns_a_leader_to_every_great_power() -> void:
	var play: PlaySession = _screen.play
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			String(play.leaders.get(faction, "")),
			LeaderCatalog.default_key(faction),
			"crown %d fields its config leader" % faction
		)
	assert_eq(String(play.leaders.get(play.player_faction, "")), "isabella")


func test_setup_leader_choice_reaches_land_combat() -> void:
	_screen.free()
	_screen = Fixture.attach_screen(self, 2, "napoleon")
	var play: PlaySession = _screen.play
	assert_eq(play.player_faction, 2)
	assert_eq(String(play.leaders.get(2, "")), "napoleon", "the human crown keeps its choice")
	var context: Dictionary = MapPlayLandTurn.battle_context(play)
	var leaders: Dictionary = context["leaders"]
	assert_eq(String(leaders.get(2, "")), "napoleon", "combat reads the chosen leader")
	MapPlayTurn.end_turn(play)
	Fixture.settle(play)
	assert_eq(String(play.leaders.get(2, "")), "napoleon", "leaders never change mid-game")


func test_the_home_fleet_carries_a_field_army_across_its_port() -> void:
	var play: PlaySession = _screen.play
	var home: ArmyState = ArmyTraining.home_army(
		_screen.army_layer.armies, play.player_faction
	)
	assert_not_null(home)
	var detach: Dictionary = _screen.army_layer.split(home, [home.regiments[0]])
	assert_true(bool(detach.get("ok", false)))
	var army: ArmyState = detach["army"] as ArmyState
	var fleet: FleetState = _screen.ship_layer.home_fleet(_screen.capital_province)
	assert_not_null(fleet)
	_screen.army_layer.select(army)
	MapPlayArmies.on_action(play, "embark")
	assert_true(army.is_embarked())
	assert_eq(fleet.embarked_army, army.id)
	assert_eq(army.province, MapModel.NO_ID)

	var ship: Ship = _screen.ship_layer.ship_for(fleet)
	_screen.ship_layer.select(ship)
	MapPlayFleets.select(play, ship)
	assert_eq(MapPlayFleets.carried(play, fleet), army.count())
	assert_eq(MapPlayFleets.landing_rows(play, fleet).size(), 1)

	MapPlayFleets.land(play, _screen.capital_province)
	assert_false(army.is_embarked())
	assert_eq(army.province, _screen.capital_province)
	assert_eq(fleet.embarked_army, -1)


func test_a_crew_caught_in_a_captured_province_withdraws_or_is_lost() -> void:
	var play: PlaySession = _screen.play
	var pair: Array = _border_tiles(play)
	assert_gte(pair.size(), 2, "the fixture has a land border")
	var foreign: Vector2i = pair[1]
	var crew: CivilianState = _screen.civilian_layer.add_unit(
		play.player_faction, "builder", foreign
	)

	var reports: Array[Dictionary] = CivilianStrandingPass.settle_stranding(
		_screen.civilian_layer, play.world
	)

	assert_true(reports.size() >= 1, "the stranded crew is reported")
	if _screen.civilian_layer.units.has(crew):
		assert_ne(crew.tile, foreign, "withdraws off the lost ground")
		assert_true(CivilianMovement.may_enter(
			_screen.model, crew.type_id, crew.owner, crew.tile
		), "the new tile is legal")
	else:
		assert_true(bool(reports[0].get("lost", false)), "or is lost with the province")


func test_the_human_court_is_told_when_a_crew_withdraws() -> void:
	var play: PlaySession = _screen.play
	var pair: Array = _border_tiles(play)
	assert_gte(pair.size(), 2, "the fixture has a land border")
	var crew: CivilianState = _screen.civilian_layer.add_unit(
		play.player_faction, "builder", pair[1]
	)
	var toasts_before: int = _screen.hud.despatches.lane.get_child_count()

	MapPlayCivilians.settle_stranding(play)

	assert_gt(
		_screen.hud.despatches.lane.get_child_count(), toasts_before,
		"the court hears the crew's fate"
	)
	if _screen.civilian_layer.units.has(crew):
		assert_ne(crew.tile, pair[1])


## A signed deed develops the seller's town, and the crown is told the level it
## now stands at (DR-20261112-01; RUB-P5-05).
func test_a_signed_deed_names_the_town_it_raised() -> void:
	var play: PlaySession = _screen.play
	var model: MapModel = play.model
	var found: Array = _minor_estate(model)
	assert_eq(found.size(), 2, "the chart seats a Minor with an estate")
	var province: ProvinceState = found[0]
	var tile: Vector2i = found[1]
	var saved: Array = Fixture.snapshot(play.world)
	var town_before: int = province.town_development

	var report: Dictionary = {}
	assert_true(LandPurchase.complete(
		model, tile, play.player_faction, play.economy.economy, report
	), "the deed is signed")
	MapPlayCivilians._settle_purchase(play, {
		"owner": play.player_faction,
		"region": model.region_id,
		"tile": tile,
		"province": province.id,
		"town_level": int(report.get("town_level", 0)),
	})

	assert_eq(province.town_level(), 2, "one deed lifts the seller's town")
	assert_true(
		_last_toast_text().ends_with("The town rises to level 2."),
		"the court hears the deed and the level it bought: %s" % _last_toast_text()
	)
	# A town already at its deed ceiling must not announce a rise it never took.
	province.town_development = 4
	MapPlayCivilians._settle_purchase(play, {
		"owner": play.player_faction,
		"region": model.region_id,
		"tile": tile,
		"province": province.id,
		"town_level": 0,
	})
	assert_false(
		_last_toast_text().contains("town"),
		"a fully grown town is not announced as rising: %s" % _last_toast_text()
	)
	Fixture.restore(play.world, saved)
	province.town_development = town_before


## The text of the most recent despatch plate, or "" when none is on screen.
func _last_toast_text() -> String:
	var box: Node = _screen.hud.despatches.lane
	if box.get_child_count() == 0:
		return ""
	return _label_text(box.get_child(box.get_child_count() - 1))


func _label_text(node: Node) -> String:
	for child: Node in node.get_children():
		if child is Label:
			return (child as Label).text
		var inner: String = _label_text(child)
		if not inner.is_empty():
			return inner
	return ""


## A Minor or Tribe province and one of its resource tiles.
func _minor_estate(model: MapModel) -> Array:
	for province: ProvinceState in model.provinces:
		var kind: int = FactionCatalog.type_of(province.owner)
		if kind != FactionCatalog.Type.MINOR_NATION and kind != FactionCatalog.Type.TRIBE:
			continue
		for tile: Vector2i in province.tiles:
			if model.resource_at(tile.x, tile.y) != MapModel.NO_ID:
				return [province, tile]
	return []


## An owned land tile and a foreign neighbour across the border.
func _border_tiles(play: PlaySession) -> Array:
	var model: MapModel = play.model
	for province: ProvinceState in model.provinces:
		if province.owner != play.player_faction:
			continue
		for tile: Vector2i in province.tiles:
			for offset: Vector2i in [
				Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
			]:
				var other: Vector2i = tile + offset
				if not model.is_land(other.x, other.y):
					continue
				var province_id: int = model.province_at(other.x, other.y)
				if province_id == MapModel.NO_ID:
					continue
				if model.province_owner(province_id) == play.player_faction:
					continue
				return [tile, other]
	return []


func _capital_estate_tile() -> Vector2i:
	var capital: Vector2i = _screen.capital_tile
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var tile: Vector2i = capital + offset
		if not _screen.model.is_land(tile.x, tile.y):
			continue
		var province: int = _screen.model.province_at(tile.x, tile.y)
		if _screen.model.province_owner(province) != MapScreen.PLAYER_FACTION:
			continue
		var index: int = _screen.model.index_of(tile.x, tile.y)
		_screen.model.resource[index] = 0
		# The setup post-pass may have raised a bootstrap farm here.
		_screen.land_works.set_improvement(_screen.model, tile, 0)
		return tile
	return Vector2i(-1, -1)


func _capital_point() -> Vector2:
	return _screen.model.province_center(_screen.capital_province) * MapScreen.TILE_SIZE


## The crown's Explorer (the starting roster carries exactly one).
func _explorer() -> CivilianState:
	for unit: CivilianState in _screen.civilian_layer.units:
		if unit.type_id == "explorer":
			return unit
	return null


## Every caption and value printed on the civilian dossier's detail grid.
func _detail_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var panel: CivilianPanel = _screen.hud.panels.civilian_panel
	for node: Node in panel._detail.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return " ".join(parts)


## Prefer a crown resource a Builder can raise without an Explorer first. The
## shared seed's first owned tile can be tin/iron; skipping those keeps work
## orders stable without widening `map_fixture` (which forces a full suite).
func _buildable_owned_resource_tile() -> Vector2i:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != FactionCatalog.PLAYER_FACTION:
			continue
		for tile: Vector2i in province.tiles:
			var resource: int = _screen.model.resource_at(tile.x, tile.y)
			if resource < 0:
				continue
			if _screen.land_works.improvement_at(_screen.model, tile) > 0:
				continue
			if ImprovementCatalog.needs_prospecting(resource):
				continue
			return tile
	return Vector2i(-1, -1)
