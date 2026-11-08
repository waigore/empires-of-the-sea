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
	_screen.hud.panels.hide_diplomacy()
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


func _tribe_province() -> ProvinceState:
	for province: ProvinceState in _screen.play.world.region(1).provinces:
		if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
			return province
	return null
