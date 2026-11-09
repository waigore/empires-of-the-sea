# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the campaign-end plate on the real map screen (wiki: victory).
## A dedicated 96x64 world is cached so the Old World holds the 31 provinces a
## military victory needs; MapFixture's 64x42 map is too small for that.

const Fixture = preload("res://tests/map_fixture.gd")
const WIDTH: int = 96
const HEIGHT: int = 64

static var _world: WorldMap = null

# Seats and deeds as the shared world was generated; `_grant_old_world`
# rewrites owners, so each case starts from the same pristine world.
var pristine: Array = []

var _screen: MapScreen = null


func before_all() -> void:
	if _world == null:
		_world = MapGenerator.new().generate_world(1500, WIDTH, HEIGHT)
	pristine = Fixture.snapshot(_world)


func before_each() -> void:
	Fixture.restore(_world, pristine)
	_screen = Fixture.SCENE.instantiate()
	_screen.map_width = WIDTH
	_screen.map_height = HEIGHT
	_screen.preset_world = _world
	add_child(_screen)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	Fixture.restore(_world, pristine)


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
	_screen = Fixture.SCENE.instantiate()
	_screen.map_width = WIDTH
	_screen.map_height = HEIGHT
	_screen.pending_save = save
	add_child(_screen)

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
	return _world.region(FactionCatalog.OLD_WORLD)
