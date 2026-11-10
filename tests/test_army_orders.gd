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
