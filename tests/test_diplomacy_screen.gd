extends GdToolsTest
## Integration: the map screen's court panel, orders and diplomacy phase.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_map_screen_starts_with_a_relation_web() -> void:
	assert_not_null(_screen.play.diplomacy)
	assert_eq(_screen.play.diplomacy.relations.size(), 81)
	assert_eq(
		_screen.play.diplomacy.overture(0, 1), DiplomacyCatalog.STAGE_EMBASSY
	)


func test_court_panel_opens_and_closes() -> void:
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	MapPlayDiplomacy.open(_screen.play)
	assert_true(_screen.hud.panels.is_diplomacy_open())
	assert_false(_screen.hud.panels.is_panel_open())
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before)
	DiplomacyHud.hide(_screen.hud.panels)
	assert_false(_screen.hud.panels.is_diplomacy_open())


func test_orders_from_the_court_change_relations_and_toast() -> void:
	MapPlayDiplomacy.open(_screen.play)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(_screen.play.diplomacy.relation(0, 1).at_war)
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)
	assert_true(_screen.hud.panels.is_diplomacy_open())
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_PEACE, 1, "")
	assert_false(_screen.play.diplomacy.relation(0, 1).at_war)


func test_grant_aid_spends_treasury_and_refreshes_the_chip() -> void:
	var economy: PlayerEconomy = _screen.economy.economy
	var before: int = economy.treasury
	MapPlayDiplomacy.open(_screen.play)
	MapPlayDiplomacy.on_order(_screen.play, DiplomacyOrders.KIND_AID, 1, "1000")
	assert_eq(economy.treasury, before - 1000)
	assert_eq(_screen.hud._treasury_value, economy.treasury)
	assert_eq(_screen.play.diplomacy.relation(0, 1).score, 55.0)


func test_end_turn_runs_relation_decay_and_keeps_turn_in_sync() -> void:
	_screen.play.diplomacy.relation(0, 1).score = 40.0
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.play.diplomacy.relation(0, 1).score, 44.0)
	assert_eq(_screen.play.diplomacy.turn, _screen.play.turn)


func test_first_contact_requires_tile_visibility_in_a_tribe_province() -> void:
	assert_eq(_screen.play.diplomacy.relations_of(0).size(), 8)
	assert_true(MapPlayDiplomacy.sync_first_contact(_screen.play).is_empty())
	_screen._cycle_region()
	var province: ProvinceState = _tribe_province()
	assert_not_null(province)
	_screen.play.diplomacy.relations.erase(
		_screen.play.diplomacy.pair_key(0, province.owner)
	)
	assert_false(_screen.play.diplomacy.has_relation(0, province.owner))
	var visibility: VisibilityModel = _screen.play.visibility_by_region[1]
	var tile: Vector2i = province.tiles[0]
	visibility.raise_to(
		visibility.model.index_of(tile.x, tile.y), VisibilityModel.Level.FOGGED
	)
	var contacted: Array[int] = MapPlayDiplomacy.sync_first_contact(_screen.play)
	assert_true(contacted.has(province.owner))
	assert_true(_screen.play.diplomacy.has_relation(0, province.owner))


func test_a_march_into_foreign_land_needs_a_declared_war() -> void:
	var army: ArmyState = _field_army()
	assert_not_null(army, "a field army can be detached from the Home Army")
	var origin: int = army.province
	var target: int = _adjacent_foreign_province(army)
	assert_gt(target, -1, "the capital borders foreign land")
	var owner: int = _screen.play.model.province_owner(target)
	_screen.play.diplomacy.ensure_relation(0, owner)

	_screen.play.army_layer.select(army)
	MapPlayArmies.select(_screen.play, army)
	var toasts_before: int = _screen.hud._toast_box.get_child_count()
	var tile: Vector2i = _screen.play.model.province_data(target).tiles[0]
	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(army.province, origin, "peace refuses the invasion")
	assert_eq(_screen.hud._toast_box.get_child_count(), toasts_before + 1)

	DiplomacyRules.declare_war(_screen.play.diplomacy, 0, owner)
	_screen.play.army_layer.select(army)
	MapPlayArmies.select(_screen.play, army)
	assert_true(MapPlayArmies.try_order(_screen.play, tile))
	assert_eq(army.province, target, "war lets the same march through")


func test_join_empire_takes_the_absorbed_crowns_regiments() -> void:
	var play: PlaySession = _screen.play
	var state: DiplomacyState = play.diplomacy
	var minor: int = 6
	state.set_overture(0, minor, DiplomacyCatalog.STAGE_NAP)
	state.relation(0, minor).score = 80.0
	play.economy.economy.treasury = 200000
	var player_before: int = play.army_layer.regiment_count_all(0)
	var minor_before: int = play.army_layer.regiment_count_all(minor)
	assert_gt(minor_before, 0, "the Minor holds a garrison")
	var absorbed_ids: Array[int] = []
	for army: ArmyState in play.army_layer.armies:
		if army.owner == minor:
			absorbed_ids.append(army.id)

	MapCourtOrders.apply(
		play, DiplomacyOrders.KIND_OVERTURE, minor, DiplomacyCatalog.STAGE_JOIN_EMPIRE
	)

	assert_eq(play.army_layer.regiment_count_all(minor), 0, "no stranded regiments")
	assert_eq(
		play.army_layer.regiment_count_all(0),
		player_before + minor_before,
		"the winner takes every regiment"
	)
	var home_armies: int = 0
	for army: ArmyState in play.army_layer.armies:
		if army.owner != 0:
			continue
		if army.home:
			home_armies += 1
		if absorbed_ids.has(army.id):
			assert_false(army.home, "an absorbed Home Army becomes a field army")
			var marker: ArmyMarker = play.army_layer.marker_for(army)
			assert_not_null(marker, "the standard follows the regiments")
			assert_eq(marker.faction, 0, "the standard changes colours")
	assert_eq(home_armies, 1, "the winner still keeps exactly one Home Army")


func test_call_to_arms_suspends_the_turn_until_answered() -> void:
	var state: DiplomacyState = _screen.play.diplomacy
	var pact: DiplomacyRelation = state.relation(0, 2)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 3, 2)
	assert_true(CallToArms.has_pending(state, 0))
	MapPlayDiplomacy.open(_screen.play)
	assert_true(_screen.hud.panels.diplomacy_panel._call_box.visible, "the court asks")
	var turn_before: int = _screen.play.turn
	MapPlayTurn.end_turn(_screen.play)
	assert_eq(_screen.play.turn, turn_before, "the calendar waits for the answer")
	assert_true(_screen.play.turn_suspended)
	MapPlayTurn.answer_call(_screen.play, true)
	assert_true(state.relation(0, 3).at_war, "joining means war on the aggressor")
	assert_eq(_screen.play.turn, turn_before + 1)
	assert_false(CallToArms.has_pending(state, 0))


func test_court_intent_router_sends_orders_and_call_answers() -> void:
	MapCourtOrders.apply(_screen.play, DiplomacyOrders.KIND_WAR, 1, "")
	assert_true(_screen.play.diplomacy.relation(0, 1).at_war, "orders reach the court")
	var state: DiplomacyState = _screen.play.diplomacy
	var pact: DiplomacyRelation = state.relation(0, 4)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(state)
	DiplomacyRules.declare_war(state, 5, 4)
	MapCourtOrders.apply(_screen.play, CallToArms.KIND_JOIN, 5, "")
	assert_true(state.relation(0, 5).at_war, "a call answer reaches the turn resolver")


func _field_army() -> ArmyState:
	for army: ArmyState in _screen.play.army_layer.armies.duplicate():
		if army.owner == 0 and army.home and army.count() > 1:
			var ids: Array[String] = []
			for regiment: String in army.regiments:
				ids.append(regiment)
			_screen.play.army_layer.split(army, ids.slice(0, 1))
	for army: ArmyState in _screen.play.army_layer.armies:
		if army.owner == 0 and not army.home:
			return army
	return null


func _adjacent_foreign_province(army: ArmyState) -> int:
	var model: MapModel = _screen.play.model
	for neighbor: int in MapGeo.province_neighbors(model, army.province):
		var owner: int = model.province_owner(neighbor)
		if owner != 0 and owner != MapModel.NO_ID:
			return neighbor
	return -1


func _tribe_province() -> ProvinceState:
	for province: ProvinceState in _screen.play.world.region(1).provinces:
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			return province
	return null
