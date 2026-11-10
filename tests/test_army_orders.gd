extends GdToolsTest
## Land armies end-to-end through the real map screen (wiki: military-armies,
## combat): muster, dossier, detach, march, merge and capture.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null
## The shared world as generated: combat tests shift ownership, so every case
## starts from the same map instead of the previous case's aftermath.
var _saved: Array = []


func before_all() -> void:
	_saved = Fixture.snapshot(Fixture.world())


func before_each() -> void:
	Fixture.restore(Fixture.world(), _saved)
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_home_armies_muster_at_each_capital() -> void:
	var home: ArmyState = _player_home()
	assert_not_null(home)
	assert_true(home.is_home_army())
	assert_eq(home.province, _screen.capital_province)
	assert_eq(home.owner, MapScreen.PLAYER_FACTION)
	assert_eq(home.count(), ArmyLayer.GREAT_POWER_ROSTER.size())
	for army: ArmyState in _screen.army_layer.armies:
		if army.is_home_army():
			var province: ProvinceState = _screen.model.province_data(army.province)
			assert_true(province != null and province.capital)


func test_selecting_an_army_opens_its_dossier() -> void:
	var home: ArmyState = _player_home()
	var marker: ArmyMarker = _screen.army_layer.marker_for(home)
	assert_not_null(marker)
	# Settle the opening camera first: it zooms into the capital over several
	# frames, and a tap is resolved against the live zoom. Waiting for the
	# camera to come to rest (not a fixed frame count) keeps the suite stable
	# when workers are loaded by parallel suites.
	await _settle_camera()

	MapPlayInput.on_tapped(_screen.play, marker.position)

	assert_eq(_screen.army_layer.selected_army, home)
	assert_true(_screen.hud.panels.is_army_panel_open())
	assert_false(_screen.hud.panels.is_panel_open())


## Waits until the camera's position and zoom hold for two frames (bounded).
func _settle_camera() -> void:
	var last: Vector2 = _screen.camera.zoom
	var last_position: Vector2 = _screen.camera.position
	var stable: int = 0
	for _frame in 90:
		await get_tree().process_frame
		var still: bool = (
			_screen.camera.zoom.is_equal_approx(last)
			and _screen.camera.position.is_equal_approx(last_position)
		)
		stable = stable + 1 if still else 0
		last = _screen.camera.zoom
		last_position = _screen.camera.position
		if stable >= 2:
			return


func test_the_home_army_has_no_march_options() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var none: Array[int] = []
	assert_eq(ArmyMovement.destinations(_screen.model, home), none)
	assert_eq(_screen.overlay.move_provinces.size(), 0)


func test_detaching_a_regiment_forms_a_field_army() -> void:
	var home: ArmyState = _player_home()
	var before: int = home.count()
	_screen.army_layer.select(home)

	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])

	var field: ArmyState = _screen.army_layer.selected_army
	assert_not_null(field)
	assert_ne(field, home)
	assert_false(field.is_home_army())
	assert_eq(field.count(), 1)
	assert_eq(home.count(), before - 1)
	assert_eq(field.province, home.province)
	assert_true(_screen.hud.panels.is_army_panel_open())


func test_a_field_army_marches_once_and_resets_next_turn() -> void:
	var field: ArmyState = _detach_one()
	var destination: int = ArmyMovement.destinations(_screen.model, field)[0]
	var tile: Vector2i = _screen.model.province_data(destination).tiles[0]

	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(field.province, destination)
	assert_true(field.moved)

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_false(field.moved)


func test_detach_all_moves_the_whole_army_in_one_order() -> void:
	var home: ArmyState = _player_home()
	var total: int = home.count()
	_screen.army_layer.select(home)

	MapPlayArmies.on_action(_screen.play, "detach_all")

	var field: ArmyState = _screen.army_layer.selected_army
	assert_not_null(field)
	assert_ne(field, home)
	assert_eq(field.count(), total)
	assert_eq(home.count(), 0)
	assert_true(_screen.army_layer.armies.has(home))
	assert_true(_screen.hud.panels.is_army_panel_open())


func test_combining_armies_uses_the_home_army_as_target() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])
	var first: ArmyState = _screen.army_layer.selected_army
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])
	var second: ArmyState = _screen.army_layer.selected_army
	var total: int = home.count() + first.count() + second.count()

	_screen.army_layer.select(second)
	MapPlayArmies.on_action(_screen.play, "merge")

	assert_eq(_screen.army_layer.selected_army, home)
	assert_eq(home.count(), total)
	assert_eq(_screen.army_layer.armies_in(home.province, home.owner).size(), 1)


func test_mustering_a_regiment_spends_the_ledger_and_joins_the_home_army() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	assert_true(_screen.hud.panels.army_panel._muster_button.visible)
	var before: int = home.count()
	var treasury: int = _screen.economy.economy.treasury
	var fabric: int = _screen.economy.economy.quantity("fabric")

	MapPlayArmies.on_action(_screen.play, "recruit:peasant_levies")

	assert_eq(home.count(), before + 1)
	assert_eq(home.type_of(home.regiments[home.regiments.size() - 1]), "peasant_levies")
	assert_eq(
		_screen.economy.economy.treasury,
		treasury - RegimentCatalog.treasury_cost("peasant_levies")
	)
	assert_eq(_screen.economy.economy.quantity("fabric"), fabric - 1)
	assert_eq(_screen.hud._army_label.text, str(_screen.army_layer.regiment_count_all(0)))


## The dossier's one battle-plan tap is a crown-wide standing order, named so it
## is not mistaken for this army's (wiki: quick-battle § The crown's plan;
## DR-20261110-33; REQ-P5-03).
func test_the_dossier_cycles_the_crowns_battle_plan() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	assert_eq(_screen.play.battle_plan, "balanced")
	assert_eq(panel._plan.text, "Crown battle plan: Balanced")

	panel._plan.pressed.emit()
	assert_eq(_screen.play.battle_plan, "aggressive")
	assert_eq(panel._plan.text, "Crown battle plan: Aggressive")

	panel._plan.pressed.emit()
	assert_eq(_screen.play.battle_plan, "defensive")
	panel._plan.pressed.emit()
	assert_eq(_screen.play.battle_plan, "balanced", "the cycle closes")


func test_the_drill_yard_stacks_below_the_roster() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	var panel: ArmyPanel = _screen.hud.panels.army_panel
	assert_eq(panel._muster_box.get_parent(), panel._roster.get_parent())
	assert_true(panel._muster_box.get_parent() is VBoxContainer)


func test_the_drill_yard_is_closed_on_a_field_army() -> void:
	var field: ArmyState = _detach_one()
	assert_false(_screen.hud.panels.army_panel._muster_button.visible)
	assert_eq(field.owner, MapScreen.PLAYER_FACTION)


func test_army_rations_enter_the_consumption_projection() -> void:
	var home: ArmyState = _player_home()
	var expected: int = _screen.army_layer.food_upkeep_all(MapScreen.PLAYER_FACTION)
	assert_gt(expected, 0)
	assert_eq(_screen.economy.army_food(), expected)
	var consumption: Dictionary = _screen.economy.projected()["consumption"]
	assert_eq(int(consumption["army_demand"]), expected)
	assert_eq(_screen.hud._army_label.text, str(_screen.army_layer.regiment_count_all(0)))


func test_marching_into_an_enemy_province_captures_it_unopposed() -> void:
	var field: ArmyState = _detach_one()
	var home: ArmyState = _player_home()
	var target: int = _adjacent_enemy_province(home.province)
	assert_gt(target, -1)
	var tile: Vector2i = _screen.model.province_data(target).tiles[0]
	var owner: int = _screen.model.province_owner(target)
	_screen.play.diplomacy.ensure_relation(0, owner, _screen.play.diplomacy.turn)
	DiplomacyRules.declare_war(_screen.play.diplomacy, 0, owner)

	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(field.province, target)

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_eq(_screen.model.province_owner(target), MapScreen.PLAYER_FACTION)


func test_enemy_armies_are_observed_not_ordered() -> void:
	var enemy: ArmyState = _enemy_army()
	assert_not_null(enemy)
	_screen.army_layer.select(enemy)
	assert_true(_screen.hud.panels.is_army_panel_open())
	var tile: Vector2i = _screen.model.province_data(enemy.province).tiles[0]
	assert_false(MapPlayArmies.try_order(_screen.play, tile))


func test_detaching_the_last_field_regiment_retires_its_standard() -> void:
	var field: ArmyState = _detach_one()
	_screen.army_layer.select(field)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % field.regiments[0])
	var created: ArmyState = _screen.army_layer.selected_army
	assert_false(_screen.army_layer.armies.has(field))
	assert_null(_screen.army_layer.marker_for(field))
	assert_not_null(created)
	assert_eq(created.count(), 1)


func test_army_dossier_can_dock_left_or_right() -> void:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.LEFT)
	assert_eq(_screen.hud._army_wrap.anchor_left, 0.0)
	assert_true(_screen.hud.panels.is_army_panel_open())
	# Restore the shared user://ui.cfg so parallel suites still see RIGHT.
	_screen.hud.panels.toggle_dock_side()
	assert_eq(_screen.hud.panels.dock.side, PanelDock.Side.RIGHT)


## A garrison the rules reform after mutual annihilation arrives without a
## standard: the combat pass must draw one, or the court cannot see, tap or
## order the army that is holding its province (wiki: combat § Garrison
## recovery; § Multi-Attacker Chain).
func test_a_reformed_garrison_gets_a_standard_the_court_can_tap() -> void:
	var capital: int = _screen.capital_province
	var armies: Array[ArmyState] = _screen.army_layer.armies
	var recovery: Dictionary = ArmyGarrison.recover(
		armies, capital, MapScreen.PLAYER_FACTION, 5, {}
	)
	var reformed: ArmyState = armies[armies.size() - 1]
	assert_eq(int(recovery["count"]), 1)
	assert_null(
		_screen.army_layer.marker_for(reformed),
		"the rules minted it; no standard exists until the layer reconciles"
	)

	_screen.army_layer.resolve_battles(_screen.world, {"quick_battle": false})

	var marker: ArmyMarker = _screen.army_layer.marker_for(reformed)
	assert_not_null(marker, "the combat pass draws the reformed garrison's standard")
	assert_true(marker.visible, "a province the court holds keeps its garrison on the map")


## A standard whose army left the field goes with it, so a wiped garrison leaves
## no ghost marker behind (wiki: combat § Outcomes).
func test_a_standard_leaves_with_the_army_it_belongs_to() -> void:
	var home: ArmyState = _player_home()
	var marker: ArmyMarker = _screen.army_layer.marker_for(home)
	assert_not_null(marker)

	_screen.army_layer.armies.erase(home)
	_screen.army_layer.resolve_battles(_screen.world, {"quick_battle": false})

	assert_null(_screen.army_layer.marker_for(home), "the fallen army's standard is retired")


## A battle the crown fights leaves a word at the rival's court: the event beat
## (wiki: dialogue-and-mood § Design intent — event: battle results;
## DR-20261111-01). The record is written by the real combat pass, so the beat
## can never drift from what the field decided.
func test_a_battle_leaves_a_word_at_the_rivals_court() -> void:
	var rival: int = 2
	var province: int = -1
	for entry: ProvinceState in _screen.model.provinces:
		if entry.owner == rival and not entry.capital:
			province = entry.id
			break
	assert_true(province >= 0, "the fixture seats a rival province")
	DiplomacyRules.declare_war(_screen.play.diplomacy, MapScreen.PLAYER_FACTION, rival)
	_screen.play.observer_mode = true
	_screen.model.province_data(province).fort_level = 0
	_seat_battle(province, MapScreen.PLAYER_FACTION, rival, 8, 2)

	MapPlayArmies.resolve_battles(_screen.play)

	var spoken: Dictionary = DialogueEvents.for_pair(
		_screen.play.diplomacy, MapScreen.PLAYER_FACTION, rival
	)
	assert_eq(String(spoken["category"]), DialogueCatalog.CAT_EVENT, "the field answers")
	assert_true(String(spoken["point"]).begins_with("event/"), "a battle beat")
	assert_eq(int(spoken["speaker"]), rival, "the rival speaks, never the crown")


## Seats an attacker and a defender in one province, as a march would, without
## disturbing the screen's selection.
func _seat_battle(province: int, attacker: int, defender: int, atk: int, def: int) -> void:
	_screen.army_layer.armies.clear()
	_screen.model.province_data(province).owner = defender
	var holding: ArmyState = ArmyState.muster(1, defender, province, false, _guards(def), 1)
	holding.moved = false
	var field: ArmyState = ArmyState.muster(2, attacker, province, false, _guards(atk), 100)
	field.moved = true
	_screen.army_layer.armies.append(holding)
	_screen.army_layer.armies.append(field)
	_screen.army_layer._rebuild_markers()


func _guards(count: int) -> Array[String]:
	var types: Array[String] = []
	for _index in count:
		types.append("guards")
	return types


func _player_home() -> ArmyState:
	for army: ArmyState in _screen.army_layer.armies:
		if army.owner == MapScreen.PLAYER_FACTION and army.is_home_army():
			return army
	return null


func _detach_one() -> ArmyState:
	var home: ArmyState = _player_home()
	_screen.army_layer.select(home)
	MapPlayArmies.on_action(_screen.play, "detach:%s" % home.regiments[0])
	return _screen.army_layer.selected_army


func _enemy_army() -> ArmyState:
	for army: ArmyState in _screen.army_layer.armies:
		if army.owner != MapScreen.PLAYER_FACTION and army.count() > 0:
			return army
	return null


## Turns an adjacent province over to a rival so the capture path has no
## defender; the map's own ownership layout stays untouched otherwise.
func _adjacent_enemy_province(capital: int) -> int:
	for province_id: int in MapGeo.province_neighbors(_screen.model, capital):
		var data: ProvinceState = _screen.model.province_data(province_id)
		if data == null or data.capital:
			continue
		data.owner = 1
		return province_id
	return -1

# --- Regiment detail in the army dossier (REQ-P1-07, REQ-P5-05) ---
const ArmyFixture = preload("res://tests/army_fixture.gd")


func test_roster_rows_carry_regiment_detail() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(3, 0, 1, ["guards", "pikemen"], false)

	panel.refresh(model, army, true)

	var roster: VBoxContainer = panel._roster
	assert_eq(roster.get_child_count(), 2, "one row per regiment")
	var first: VBoxContainer = roster.get_child(0)
	assert_eq((first.get_child(0).get_child(0) as Label).text, "Guards")
	var detail: Label = first.get_child(1)
	assert_eq(detail.text, RegimentCatalog.detail_line("guards"))
	assert_true(detail.text.contains("FPN 12"), detail.text)
	assert_true(detail.text.contains("food"), detail.text)
	panel.free()


func test_an_enemy_dossier_keeps_the_detail_but_no_orders() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(4, 1, 2, ["knights"], false)

	panel.refresh(model, army, false)

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq((row.get_child(0) as HBoxContainer).get_child_count(), 1, "no detach order")
	assert_true((row.get_child(1) as Label).text.contains("Spear cavalry"))
	assert_true(String(panel._status.text).contains("Enemy colours"))
	panel.free()


## The dossier shows a regiment's own record: chevrons for experience and a
## health bar while it is still mauled (wiki: combat § Strength; DR-20261110-19).
func test_roster_shows_chevrons_and_wounds() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(5, 0, 1, ["guards"], false)
	var regiment: String = army.regiments[0]
	army.regiment_medals[regiment] = 2
	army.regiment_health[regiment] = 60

	panel.refresh(model, army, true)

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(row.get_child_count(), 3, "name row, detail, condition")
	var condition: HBoxContainer = row.get_child(2)
	assert_true(condition.get_child(0) is TextureRect, "the chevron medallion")
	assert_eq((condition.get_child(1) as Label).text, "×2")
	var bar: ProgressBar = condition.get_child(2)
	assert_almost_eq(bar.value, 0.5, 0.01, "half the pool shows half the bar")
	assert_eq((condition.get_child(3) as Label).text, "50%")
	assert_true(String(panel._strength.text).contains("2 chevrons"))
	panel.free()


## An embarked army is one draft aboard a squadron, so its dossier offers no
## detach order (wiki: military-armies § Split and combine; ships-and-naval
## § Naval transport).
func test_an_embarked_dossier_offers_no_detach_order() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(6, 0, 0, ["guards", "pikemen"], false)
	var fleet := FleetState.in_port(1, 0, 0, ["ship_1", "ship_2"])
	assert_true(bool(NavalTransport.embark(model, army, fleet)["ok"]))

	panel.refresh(model, army, true)

	var row: VBoxContainer = panel._roster.get_child(0)
	assert_eq(
		(row.get_child(0) as HBoxContainer).get_child_count(),
		1,
		"no detach order while aboard"
	)
	assert_true(String(panel._status.text).contains("Aboard the fleet"))
	panel.free()


## The dossier names the stance as the crown's, never that army's: one plan
## commands every Quick Battle the human fights (wiki: quick-battle § The
## crown's plan; DR-20261110-33).
func test_the_dossier_names_the_crowns_plan() -> void:
	var panel := ArmyPanel.new()
	add_child(panel)
	var model := ArmyFixture.build()
	var army := ArmyFixture.army(8, 0, 1, ["guards"], false)

	panel.refresh(model, army, true, false, "", [], "", "aggressive")

	assert_eq(String(panel._plan.text), "Crown battle plan: Aggressive")
	assert_true(String(panel._plan.tooltip_text).contains("crown"))
	panel.refresh(model, army, true, false, "", [], "", "hammer")
	assert_eq(String(panel._plan.text), "Crown battle plan: Balanced", "an unknown stance reads balanced")
	panel.free()


## One tap on any own army's dossier cycles the whole crown's stance, and an
## unknown value starts from balanced rather than stranding the cycle
## (wiki: quick-battle § The crown's plan).
func test_cycling_the_plan_is_crown_wide() -> void:
	var play: PlaySession = _screen.play
	var army: ArmyState = _player_home()
	play.battle_plan = "balanced"

	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "aggressive")
	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "defensive", "the plan lives on the crown, not the army")
	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "balanced")

	play.battle_plan = "hammer"
	MapPlayArmies.cycle_plan(play, army)
	assert_eq(play.battle_plan, "aggressive", "an unknown stance cycles from balanced")

