extends GdToolsTest
## Great Power defeat on terminal fall (wiki: victory § Great Power defeat,
## capital-and-connectivity § Great Power fall; DR-20261109-05).
##
## The rules fixture is the shared generated world; each integration test
## strips a crown down to its seat, hands that seat to a rival and resolves the
## capital-loss pass, which is exactly how defeat happens in a real Combat phase.

const Fixture = preload("res://tests/map_fixture.gd")
const SAVE_DIR: String = "user://test_campaign_defeat"

var screen: MapScreen = null
## Ownership and seats as the shared world was generated; see `before_all`.
var saved: Array = []


## Snapshotted before any case touches the fixture, so the base is a clean world.
func before_all() -> void:
	saved = Fixture.snapshot(Fixture.world())


func after_each() -> void:
	Fixture.restore(Fixture.world(), saved)
	if is_instance_valid(screen):
		screen.free()
	screen = null
	get_tree().paused = false


## The defeat pass mutates ownership, so this suite restores the shared world
## after each case instead of regenerating it (coverage makes generation ~10x
## its play cost).
func before_each() -> void:
	Fixture.restore(Fixture.world(), saved)


func _attach() -> MapScreen:
	if screen != null:
		return screen
	screen = Fixture.attach_screen(self)
	return screen


# --- the verdict -------------------------------------------------------------


func test_a_human_terminal_fall_is_defeat() -> void:
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = _rival(player)

	var state: DefeatState = CampaignDefeat.resolve(
		[{"faction": player, "conqueror": rival, "lost": 3}], player, 12
	)

	assert_not_null(state)
	assert_eq(state.fallen_player_id, player)
	assert_eq(state.conqueror_player_id, rival)
	assert_eq(state.turn_number, 12)
	assert_eq(state.fallen_name(), FactionCatalog.name_of(player))
	assert_eq(state.conqueror_name(), FactionCatalog.name_of(rival))


func test_an_ai_fall_never_defeats_the_human_crown() -> void:
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = _rival(player)

	var state: DefeatState = CampaignDefeat.resolve(
		[{"faction": rival, "conqueror": player}], player, 12
	)

	assert_null(state, "only the human crown's fall seals the session")


func test_a_minor_or_tribe_fall_is_map_cleanup_only() -> void:
	var minor: int = FactionCatalog.minor_ids()[0]
	var tribe: int = FactionCatalog.tribe_ids()[0]

	var minor_state: DefeatState = CampaignDefeat.resolve(
		[{"faction": minor, "conqueror": 0}], minor, 4
	)
	var tribe_state: DefeatState = CampaignDefeat.resolve(
		[{"faction": tribe, "conqueror": 0}], tribe, 4
	)

	assert_null(minor_state, "Minor Nations cannot be defeated")
	assert_null(tribe_state, "Tribes cannot be defeated")


func test_a_malformed_fall_report_is_ignored() -> void:
	var player: int = FactionCatalog.PLAYER_FACTION

	assert_null(CampaignDefeat.resolve([], player, 3))
	assert_null(CampaignDefeat.resolve(["not a row"], player, 3))
	assert_null(
		CampaignDefeat.resolve([{"faction": MapModel.NO_ID, "conqueror": 1}], player, 3)
	)


# --- the session -------------------------------------------------------------


func test_a_human_terminal_fall_seals_the_session_and_mounts_the_defeat_plate() -> void:
	var target: MapScreen = _attach()
	var conqueror: int = _rival(target.play.player_faction)

	_fall_crown(target, target.play.player_faction, conqueror)

	assert_not_null(target.play.defeat)
	assert_true(target.play.campaign_over())
	assert_true(target.hud.is_victory_shown())
	assert_eq(target.hud.victory_overlay._title.text, "DEFEAT")
	assert_eq(
		target.hud.victory_overlay._winner.text,
		"%s falls to %s" % [
			FactionCatalog.name_of(target.play.player_faction),
			FactionCatalog.name_of(conqueror),
		]
	)
	assert_eq(
		target.hud.victory_overlay._tagline.text,
		"The age has ended for your court."
	)
	assert_true(target.hud._end_turn_button.disabled)
	assert_eq(target.hud._end_turn_button.text, "CAMPAIGN ENDED")


func test_a_defeated_campaign_takes_no_more_turns_and_awards_no_victory() -> void:
	var target: MapScreen = _attach()
	var conqueror: int = _rival(target.play.player_faction)
	_fall_crown(target, target.play.player_faction, conqueror)
	var turn_before: int = target.turn

	MapPlayTurn.end_turn(target.play)

	assert_eq(target.turn, turn_before, "the seal keeps the turn number")
	assert_null(target.play.victory, "defeat does not grant a military victory")
	assert_not_null(target.play.defeat)
	assert_eq(target.hud.victory_overlay._title.text, "DEFEAT")


func test_an_ai_fall_removes_the_crown_and_the_campaign_sails_on() -> void:
	var target: MapScreen = _attach()
	var rival: int = _rival(target.play.player_faction)
	var holdings_before: int = target.play.world.owned_provinces(0, rival)

	_fall_crown(target, rival, target.play.player_faction)

	assert_null(target.play.defeat, "an AI fall is not the human's defeat")
	assert_false(target.play.campaign_over(), "the campaign continues")
	assert_false(target.hud.is_victory_shown())
	assert_eq(
		target.play.world.owned_provinces(0, rival), 0, "the crown left the map"
	)
	assert_gt(holdings_before, 0)


# --- persistence -------------------------------------------------------------


func test_a_defeated_slot_reopens_on_the_defeat_plate() -> void:
	var target: MapScreen = _attach()
	target.save_dir = SAVE_DIR
	var conqueror: int = _rival(target.play.player_faction)
	_fall_crown(target, target.play.player_faction, conqueror)
	var save: Dictionary = SaveCodec.capture(target.play)
	assert_true(SaveCodec.is_valid(save))
	target.free()
	screen = null

	var reopened: MapScreen = _load(save)

	assert_not_null(reopened.play.defeat, "the defeat survives the save")
	assert_eq(reopened.play.defeat.conqueror_player_id, conqueror)
	assert_true(reopened.play.campaign_over())
	assert_true(reopened.hud.is_victory_shown(), "the plate returns on load")
	assert_eq(reopened.hud.victory_overlay._title.text, "DEFEAT")
	assert_true(reopened.hud._end_turn_button.disabled)
	var turn_before: int = reopened.turn
	MapPlayTurn.end_turn(reopened.play)
	assert_eq(reopened.turn, turn_before, "turns stay shut after a load")


func test_a_legacy_slot_without_a_defeat_field_stays_undefeated() -> void:
	var target: MapScreen = _attach()
	target.save_dir = SAVE_DIR
	var save: Dictionary = SaveCodec.capture(target.play)
	save.erase("defeat")
	target.free()
	screen = null

	var reopened: MapScreen = _load(save)

	assert_null(reopened.play.defeat, "absent -> human not defeated")
	assert_false(reopened.play.campaign_over())


func test_a_fallen_crowns_civilians_leave_play() -> void:
	var target: MapScreen = _attach()
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = _rival(player)
	var civil: CivilianLayer = target.play.civilian_layer
	var tile: Vector2i = target.play.model.province_tiles(target.play.capital_province)[0]
	var crew: CivilianState = civil.add_unit(rival, "builder", tile)
	assert_true(civil.units.has(crew), "the fixture crew musters")

	_fall_crown(target, rival, player)

	assert_eq(civil.unit_count_all(rival), 0, "its crews leave with the crown")
	assert_false(civil.units.has(crew))


# --- fixtures ----------------------------------------------------------------


func _rival(player: int) -> int:
	for faction: int in FactionCatalog.great_power_ids():
		if faction != player:
			return faction
	return MapModel.NO_ID


## Leaves `fallen` owning only its capital in its home region, hands that seat
## to `conqueror` and resolves the capital-loss pass like a Combat phase would.
func _fall_crown(target: MapScreen, fallen: int, conqueror: int) -> void:
	var play: PlaySession = target.play
	var model: MapModel = play.world.region(FactionCatalog.region_of(fallen))
	var capital: int = CapitalLoss.seat_of(model, fallen)
	assert_gte(capital, 0, "the fixture crown has a seat")
	for province: ProvinceState in model.provinces:
		if province.owner == fallen and province.id != capital:
			province.owner = MapModel.NO_ID
	var before: Array = CapitalLoss.snapshot_world(play.world)
	model.province_data(capital).owner = conqueror
	var losses: Dictionary = CapitalLoss.resolve_world(play.world, before)
	assert_eq(
		int(losses["fallen"].size()), 1, "the stripped crown falls on its lost seat"
	)
	MapPlayArmyBattles.apply_capital_loss(play, losses)


func _load(data: Dictionary) -> MapScreen:
	return Fixture.open_save(self, data, SAVE_DIR)
