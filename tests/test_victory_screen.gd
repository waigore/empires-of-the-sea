# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the campaign-end plate on the real map screen (wiki: victory).
## Reuses the shared two-region world: its Old World holds 60 provinces, so the
## 31 a military victory needs are always there, and the chart is already baked
## for every case in this suite.

const Fixture = preload("res://tests/map_fixture.gd")

# Seats and deeds as the shared world was generated; `_grant_old_world`
# rewrites owners, so each case starts from the same pristine world.
var pristine: Array = []

var _screen: MapScreen = null


func before_all() -> void:
	pristine = Fixture.snapshot(Fixture.world())


func before_each() -> void:
	Fixture.restore(Fixture.world(), pristine)
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	Fixture.restore(Fixture.world(), pristine)


func test_end_turn_crowns_the_player_and_stops_the_calendar() -> void:
	_grant_old_world(MapScreen.PLAYER_FACTION)
	var turn_before: int = _screen.turn

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_not_null(_screen.play.victory)
	assert_true(_screen.play.victory.won_by(MapScreen.PLAYER_FACTION))
	assert_eq(_screen.play.victory.turn_number, turn_before)
	assert_eq(_screen.turn, turn_before, "the campaign stops on the deciding turn")
	assert_true(_screen.hud.is_victory_shown())
	assert_true(_screen.hud._end_turn_button.disabled)
	assert_eq(_screen.hud._end_turn_button.text, "CAMPAIGN ENDED")
	assert_eq(_screen.hud.victory_overlay._title.text, "MILITARY VICTORY")
	assert_true(String(_screen.hud.victory_overlay._winner.text).contains("SPAIN"))


func test_a_rival_crown_wins_and_the_map_stops_taking_orders() -> void:
	_grant_old_world(1)

	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)

	assert_not_null(_screen.play.victory)
	assert_true(_screen.play.victory.won_by(1))
	assert_true(String(_screen.hud.victory_overlay._tagline.text).contains("England"))
	var capital: Vector2 = (
		_screen.model.province_center(_screen.capital_province) * MapScreen.TILE_SIZE
	)
	MapPlayInput.on_tapped(_screen.play, capital)
	assert_eq(_screen.selected_province, -1, "a decided campaign takes no orders")
	assert_false(_screen.hud.panels.is_panel_open())


func test_the_plate_steps_aside_for_a_final_view_but_turns_stay_shut() -> void:
	_grant_old_world(MapScreen.PLAYER_FACTION)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_true(_screen.hud.is_victory_shown())

	_screen.hud.victory_overlay.dismiss()

	assert_false(_screen.hud.is_victory_shown())
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.turn, turn_before, "dismissing the plate does not reopen play")
	assert_false(_screen.hud.is_victory_shown(), "no second plate; the campaign stays decided")


func test_a_decided_campaign_loads_decided_with_the_seal_shut() -> void:
	_grant_old_world(MapScreen.PLAYER_FACTION)
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	var decided: VictoryState = _screen.play.victory
	assert_not_null(decided)
	var save: Dictionary = SaveCodec.capture(_screen.play)
	assert_true(SaveCodec.is_valid(save), "a decided save is valid")

	_screen.free()
	_screen = Fixture.open_save(self, save)

	assert_not_null(_screen.play.victory, "the decided campaign survives the save")
	assert_eq(_screen.play.victory.winner_player_id, decided.winner_player_id)
	assert_eq(_screen.play.victory.turn_number, decided.turn_number)
	assert_true(_screen.hud.is_victory_shown(), "the plate returns on load")
	assert_true(_screen.hud._end_turn_button.disabled)
	assert_eq(_screen.hud._end_turn_button.text, "CAMPAIGN ENDED")
	var turn_before: int = _screen.turn
	MapPlayTurn.end_turn(_screen.play)
	Fixture.settle(_screen.play)
	assert_eq(_screen.turn, turn_before, "turns stay shut after a load")


func _grant_old_world(faction_id: int) -> void:
	for province: ProvinceState in _old_world().provinces:
		province.owner = faction_id


func _old_world() -> MapModel:
	return Fixture.world().region(FactionCatalog.OLD_WORLD)
