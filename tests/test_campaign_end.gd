# gdlint: disable=max-public-methods
extends GdToolsTest
## The campaign's end: the calendar cap, endless mode, the campaign-complete
## plate, the military-victory plate and the defeat plate on the real map screen
## (wiki: turn-time-mapping § Campaign calendar cap, victory § Calendar campaign
## end, § Victory Screen, § Great Power defeat).
##
## Merged from test_campaign_end, test_victory_screen and test_campaign_defeat:
## one Godot boot and one mounted chart for the whole theme. Every case re-seats
## the shared screen from the pristine save (`Fixture.suite_reset`), which drops
## a decided victory, a defeat, an open plate and a selection, so a case starts
## as the mount did.

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const Fixture = preload("res://tests/map_fixture.gd")
const CAP: int = 201
const SAVE_DIR: String = "user://test_campaign_end"
const DEFEAT_SAVE_DIR: String = "user://test_campaign_defeat"

var screen: MapScreen = null
## One mount for the suite: under coverage a mount costs ~0.5 s and a re-seat
## ~0.15 s, so the cases share the chart and reset the session instead.
var mounted: MapScreen = null
var pristine: Dictionary = {}
## Ownership and seats as the shared world was generated: `_seat_crowns` and the
## fall cases rewrite owners, so each case starts from the same pristine world.
var saved: Array = []


## Snapshotted before any case touches the fixture, so the base is a clean world.
func before_all() -> void:
	saved = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	Fixture.restore(Fixture.world(), saved)
	Fixture.suite_reset(mounted, pristine)
	screen = mounted


func after_each() -> void:
	Fixture.restore(Fixture.world(), saved)
	get_tree().paused = false


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	screen = null
	pristine = {}


## The chart is mounted once for the boot; a case that never reads it never pays
## the re-seat (the fixture is re-seated in `before_each` regardless).
func _attach() -> MapScreen:
	return screen


# --- calendar rules ----------------------------------------------------------


func test_the_cap_lands_on_the_turn_that_starts_1800() -> void:
	assert_eq(TurnTime.turn_for_year(1800), CAP)
	assert_eq(TurnTime.year_for_turn(CAP), 1800)
	assert_eq(TurnTime.cap_turn(), CAP)
	assert_true(TurnTime.is_cap_turn(CAP))


func test_a_skipped_year_starts_no_turn() -> void:
	assert_eq(TurnTime.turn_for_year(1699), -1)
	assert_eq(TurnTime.turn_for_year(1499), -1)
	assert_eq(TurnTime.turn_for_year(1601), -1)
	assert_eq(TurnTime.turn_for_year(1600), 51)
	assert_eq(TurnTime.turn_for_year(1701), 102)


func test_the_cap_only_closes_a_historical_campaign() -> void:
	assert_false(VictoryRules.calendar_halt(CAP - 1, false))
	assert_true(VictoryRules.calendar_halt(CAP, false))
	assert_false(VictoryRules.calendar_halt(CAP, true))


func test_the_strongest_crown_is_declared_when_the_calendar_closes() -> void:
	var model: MapModel = Fixture.region()
	var saved: Array[int] = []
	for province: ProvinceState in model.provinces:
		saved.append(province.owner)
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var world := WorldMap.new()
	world.add_region(model)
	var half: int = model.provinces.size() / 2
	for index in model.provinces.size():
		if index < half * 2:
			model.provinces[index].owner = crowns[0] if index < half else crowns[1]
		else:
			model.provinces[index].owner = MapModel.NO_ID
	var tie: int = VictoryRules.declared_leader(world)
	model.provinces[half].owner = crowns[0]
	var strict: int = VictoryRules.declared_leader(world)
	for index in saved.size():
		model.provinces[index].owner = saved[index]

	assert_eq(tie, MapModel.NO_ID, "an even split declares no-one")
	assert_eq(strict, crowns[0], "one province ahead is enough to lead the age")


# --- the standing reads the order of battle ----------------------------------


func test_the_strongest_order_of_battle_is_declared() -> void:
	_attach()
	var crowns: Array[int] = _seat_crowns()
	var model: MapModel = screen.play.world.region(screen.play.region_index)
	var province: int = int(model.provinces[0].id)
	var many_weak := ArmyState.muster(
		9001, crowns[0], province, false,
		["peasant_levies", "peasant_levies", "peasant_levies"]
	)
	var few_strong := ArmyState.muster(
		9002, crowns[1], province, false, ["knights", "knights"]
	)
	var armies: Array[ArmyState] = [many_weak, few_strong]
	screen.play.army_layer.armies.assign(armies)

	assert_eq(
		MapPlayCampaign.declared_leader(screen.play),
		crowns[1],
		"3 peasant levies (strength 9) fall short of 2 knights (strength 12)"
	)


func test_a_crown_is_scored_on_its_whole_order_of_battle() -> void:
	_attach()
	var crowns: Array[int] = _seat_crowns()
	var model: MapModel = screen.play.world.region(screen.play.region_index)
	var province: int = int(model.provinces[0].id)
	var here: Array[ArmyState] = [
		ArmyState.muster(
			9101, crowns[1], province, false, ["knights", "knights", "knights"]
		)
	]
	screen.play.army_layer.armies.assign(here)
	var elsewhere: int = (
		WorldMap.OLD_WORLD
		if screen.play.region_index == WorldMap.NEW_WORLD
		else WorldMap.NEW_WORLD
	)
	var far: Array[ArmyState] = [
		ArmyState.muster(
			9102, crowns[0], province, false,
			["grenadiers", "grenadiers", "grenadiers", "grenadiers"]
		)
	]
	screen.play.army_layer.regions.set_region(elsewhere, far)

	assert_eq(
		MapPlayCampaign.declared_leader(screen.play),
		crowns[0],
		"four grenadiers across the ocean outrank three knights on screen"
	)


## The cartouche seal opens the history screen on the live sheet, which keeps
## the race for the age at its foot — so the number the campaign is decided by
## stays readable on a turn that printed no news (wiki: the-gazette § History
## screen, § Purpose; DR-20261112-05).
func test_the_seal_opens_on_the_live_sheet_with_the_age() -> void:
	_attach()
	var play: PlaySession = screen.play
	play.gazette = GazetteState.new()
	play.gazette.append({
		"turn": play.turn,
		"items": [
			{
				"class": Gazette.Class.WORLD,
				"kind": "warDeclared",
				"text": "The gauntlet passes between them.",
			},
		],
	})

	MapPlayGazette.open_archive(play)
	screen.hud.gazette_plate._go(GazettePlate.Mode.SHEET)

	assert_true(_has_text(screen.hud.gazette_plate, "THE STATE OF THE AGE"))
	assert_true(_has_text(screen.hud.gazette_plate, "Old World provinces"), "the race prints")
	assert_false(_has_text(screen.hud.gazette_plate, GazettePlate.EMPTY_LINE))


## Hands `faction` Old World provinces until it holds `target`, the way a
## campaign's conquests would: the victory check reads nothing else.
func _seat_holdings(play: PlaySession, faction: int, target: int) -> void:
	var model: MapModel = play.world.region(WorldMap.OLD_WORLD)
	var held: int = VictoryRules.old_world_holdings(play.world, faction)
	for province: ProvinceState in model.provinces:
		if held >= target:
			return
		if province.owner == faction:
			continue
		province.owner = faction
		held += 1


## Splits every province of both regions evenly between the first two crowns and
## clears every fleet, so the standing depends only on the land forces a test
## gives them.
func _seat_crowns() -> Array[int]:
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var world: WorldMap = screen.play.world
	for index in world.region_count():
		var model: MapModel = world.region(index)
		var seat: int = 0
		for province: ProvinceState in model.provinces:
			province.owner = MapModel.NO_ID
		for province: ProvinceState in model.provinces:
			if seat < 20:
				province.owner = crowns[seat % 2]
			seat += 1
	var no_ships: Array[Ship] = []
	screen.play.ship_layer.ships.assign(no_ships)
	for index in screen.play.ship_layer.regions.region_ids():
		var no_fleets: Array[FleetState] = []
		screen.play.ship_layer.regions.set_region(index, no_fleets)
	return crowns


# --- end of turn -------------------------------------------------------------


func test_the_calendar_closes_an_undecided_campaign_on_its_last_turn() -> void:
	_attach()
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_true(screen.play.campaign_halted)
	assert_null(screen.play.victory)
	assert_eq(screen.turn, CAP, "the turn number stays on the last full turn")
	assert_true(screen.hud.is_victory_shown())
	assert_eq(screen.hud.victory_overlay._title.text, "CAMPAIGN COMPLETE")
	assert_eq(
		screen.hud.victory_overlay._detail.text,
		"1800  ·  Turn 201",
		"the plate reads year then turn (wiki: victory § Victory Screen)"
	)
	assert_true(screen.hud._end_turn_button.disabled)
	assert_eq(screen.hud._end_turn_button.text, "CAMPAIGN ENDED")


func test_a_closed_calendar_takes_no_more_turns() -> void:
	_attach()
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
	var turn_before: int = screen.turn

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_eq(screen.turn, turn_before)
	assert_true(screen.play.campaign_halted)


func test_a_closed_calendar_takes_no_orders() -> void:
	_attach()
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	MapPlayCivilians.on_action(screen.play, "move")
	MapPlayFleets.try_order(screen.play, Vector2i(0, 0))
	MapPlayDiplomacy.on_order(screen.play, "war", 1, "")

	assert_true(screen.play.campaign_over())
	assert_false(screen.hud.panels.is_panel_open())


func test_the_complete_plate_speaks_the_wikis_calendar_copy() -> void:
	_attach()
	var overlay: VictoryOverlay = screen.hud.victory_overlay
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = crowns[1] if crowns[1] != player else crowns[0]

	overlay.show_campaign_complete(rival, CAP, player)
	assert_eq(overlay._detail.text, "1800  ·  Turn 201", "year then turn")
	assert_true(
		overlay._tagline.text.ends_with("holds the age."),
		"a rival's standing reads '<Name> holds the age.'"
	)

	overlay.show_campaign_complete(player, CAP, player)
	assert_eq(overlay._tagline.text, "The age belongs to your crown.")

	overlay.show_campaign_complete(MapModel.NO_ID, CAP, player)
	assert_eq(overlay._tagline.text, "The age is divided — no crown is declared.")


## The turn that decides the age still files its sheet: the archive has no gap
## and the final turn's news stays readable once the plate steps aside (wiki:
## the-gazette § When it appears; victory § Victory Screen).
func test_the_deciding_turn_still_files_its_sheet() -> void:
	_attach()
	var play: PlaySession = screen.play
	var crowns: Array[int] = FactionCatalog.great_power_ids()
	var rival: int = crowns[0] if crowns[0] != play.player_faction else crowns[1]
	_seat_holdings(play, rival, VictoryRules.MILITARY_THRESHOLD)

	MapPlayTurn.end_turn(play)
	Fixture.settle(play)

	assert_not_null(play.victory, "the rival takes the age")
	assert_not_null(play.gazette)
	assert_true(
		play.gazette.has_sheet(play.turn),
		"the deciding turn's sheet is filed under its own turn"
	)
	assert_false(
		play.hud.gazette_plate.is_shown(),
		"the campaign-end plate keeps the screen; the sheet waits in the archive"
	)


## The calendar's last full turn is a resolved turn too: its sheet is filed on
## the cap, so the archive does not stop a turn short of the end.
func test_the_calendar_cap_turn_still_files_its_sheet() -> void:
	_attach()
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_true(screen.play.campaign_halted)
	assert_not_null(screen.play.gazette)
	assert_true(screen.play.gazette.has_sheet(CAP), "the cap turn's sheet is filed")
	assert_false(screen.play.gazette.has_sheet(CAP - 1), "no sheet is filed twice")


## The turn that ends the crown's age is still a turn: its sheet is filed under
## its own number, so the archive holds the capital's fall and does not stop one
## turn short of the end, while the defeat plate keeps the screen (wiki:
## the-gazette § When it appears; victory § Great Power defeat, § Victory Screen).
func test_the_fallen_turn_still_files_its_sheet() -> void:
	var target: MapScreen = _attach()
	var play: PlaySession = target.play
	var rival: int = _defeat_rival(play.player_faction)
	DiplomacyRules.declare_war(play.diplomacy, rival, play.player_faction)
	_fall_crown(target, play.player_faction, rival)
	assert_not_null(play.defeat, "the crown fell")
	assert_true(
		play.diplomacy.has_relation(play.player_faction, rival),
		"the fall keeps the dealings its last sheet has to name"
	)

	var closed: bool = MapPlayTurnFinish._close_if_decided(
		play, MapPlayTurnFinish.TurnBook.new()
	)

	assert_true(closed, "the turn that lost the crown closes the campaign")
	assert_not_null(play.gazette)
	assert_true(
		play.gazette.has_sheet(play.turn),
		"the fallen turn's sheet is filed under its own turn"
	)
	assert_false(
		play.diplomacy.has_relation(play.player_faction, rival),
		"the close drops the fallen crown's dealings once the sheet is written"
	)
	assert_true(
		target.hud.victory_overlay.is_shown(),
		"the defeat plate keeps the screen; the sheet waits in the archive"
	)


func test_an_endless_campaign_sails_past_the_cap() -> void:
	_attach()
	screen.play.infinite_mode = true
	screen.play.turn = CAP

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_false(screen.play.campaign_halted)
	assert_false(screen.hud.is_victory_shown())
	assert_eq(screen.turn, CAP + 1)
	assert_eq(TurnTime.year_for_turn(screen.turn), 1801)
	assert_false(screen.hud._end_turn_button.disabled)


# --- setup -------------------------------------------------------------------


func test_setup_carries_the_campaign_choice_into_the_config() -> void:
	var setup: GameSetupScreen = load("res://scenes/game_setup.tscn").instantiate()
	add_child(setup)
	var started: Array[GameConfig] = []
	setup.start_requested.connect(func(config: GameConfig) -> void:
		started.append(config)
	)
	setup.campaign_option.select(1)

	setup._on_start()

	assert_eq(started.size(), 1)
	assert_true(started[0].infinite_mode, "endless setup flags the config")
	assert_eq(setup.campaign_option.item_count, 2, "historical and endless on offer")


## DR-20261111-02: setup names both lengths' endings and the ready summary
## repeats the chosen horizon, so the choice is never blind (REQ-P5-03).
func test_the_setup_names_both_campaign_lengths_and_their_horizon() -> void:
	var setup: GameSetupScreen = load("res://scenes/game_setup.tscn").instantiate()
	add_child(setup)

	assert_eq(setup.campaign_option.item_count, 2, "Historical and Endless are the lengths")
	assert_true(
		setup.campaign_option.get_item_text(0).contains("1800"),
		"Historical names its ending",
	)
	assert_true(
		setup.campaign_option.get_item_text(1).contains("military victory"),
		"Endless names its only ending",
	)

	setup.campaign_option.select(0)
	setup.campaign_option.item_selected.emit(0)
	assert_true(setup._summary.text.contains("to 1800"), "the summary repeats Historical")

	setup.campaign_option.select(1)
	setup.campaign_option.item_selected.emit(1)
	assert_true(setup._summary.text.contains("endless"), "the summary repeats Endless")


func test_the_config_round_trips_the_campaign_choice() -> void:
	var config: GameConfig = GameConfig.make(7, 0, 1, "", true)

	var restored: GameConfig = GameConfig.from_dict(config.to_dict())

	assert_true(restored.infinite_mode)
	assert_eq(restored.map_seed, 7)


# --- persistence -------------------------------------------------------------


func test_a_calendar_closed_slot_reopens_on_the_complete_plate() -> void:
	_attach()
	screen.save_dir = SAVE_DIR
	screen.play.turn = CAP
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
	assert_true(screen.play.campaign_halted)
	var save: Dictionary = SaveCodec.capture(screen.play)
	assert_true(SaveCodec.is_valid(save))

	var reopened: MapScreen = _load(save)

	assert_true(reopened.play.campaign_halted, "the closed calendar survives the save")
	assert_null(reopened.play.victory)
	assert_eq(reopened.turn, CAP)
	assert_true(reopened.hud.is_victory_shown(), "the plate returns on load")
	assert_eq(reopened.hud.victory_overlay._title.text, "CAMPAIGN COMPLETE")
	assert_true(reopened.hud._end_turn_button.disabled)
	var turn_before: int = reopened.turn
	MapPlayTurn.end_turn(reopened.play)
	Fixture.settle(reopened.play)
	assert_eq(reopened.turn, turn_before, "turns stay shut after a load")
	reopened.free()


func test_an_endless_choice_survives_the_save() -> void:
	_attach()
	screen.save_dir = SAVE_DIR
	screen.play.infinite_mode = true
	var save: Dictionary = SaveCodec.capture(screen.play)

	var reopened: MapScreen = _load(save)

	assert_true(reopened.play.infinite_mode, "endless campaigns stay endless")
	reopened.free()


func _load(data: Dictionary) -> MapScreen:
	var node: MapScreen = SCREEN.instantiate()
	node.save_dir = SAVE_DIR
	# The save came from the shared world: hand it back so the load applies the
	# save over that map instead of regenerating and repainting a fresh one.
	node.map_width = Fixture.WORLD_WIDTH
	node.map_height = Fixture.WORLD_HEIGHT
	node.preset_world = Fixture.world()
	node.pending_save = data
	add_child(node)
	return node


## Any label or button on the plate carrying `needle` (the Gazette prints as
## labels, its tabs as buttons).
func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false


# --- the military-victory plate ---------------------------------------------
## Merged from test_victory_screen: the campaign-end plate on the real map
## screen (wiki: victory). The shared Old World holds 60 provinces, so the 31 a
## military victory needs are always there.


func test_end_turn_crowns_the_player_and_stops_the_calendar() -> void:
	_grant_old_world(MapScreen.PLAYER_FACTION)
	var turn_before: int = screen.turn

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_not_null(screen.play.victory)
	assert_true(screen.play.victory.won_by(MapScreen.PLAYER_FACTION))
	assert_eq(screen.play.victory.turn_number, turn_before)
	assert_eq(screen.turn, turn_before, "the campaign stops on the deciding turn")
	assert_true(screen.hud.is_victory_shown())
	assert_true(screen.hud._end_turn_button.disabled)
	assert_eq(screen.hud._end_turn_button.text, "CAMPAIGN ENDED")
	assert_eq(screen.hud.victory_overlay._title.text, "MILITARY VICTORY")
	assert_true(String(screen.hud.victory_overlay._winner.text).contains("SPAIN"))


func test_a_rival_crown_wins_and_the_map_stops_taking_orders() -> void:
	_grant_old_world(1)

	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)

	assert_not_null(screen.play.victory)
	assert_true(screen.play.victory.won_by(1))
	assert_true(String(screen.hud.victory_overlay._tagline.text).contains("England"))
	var capital: Vector2 = (
		screen.model.province_center(screen.capital_province) * MapScreen.TILE_SIZE
	)
	MapPlayInput.on_tapped(screen.play, capital)
	assert_eq(screen.selected_province, -1, "a decided campaign takes no orders")
	assert_false(screen.hud.panels.is_panel_open())


func test_the_plate_steps_aside_for_a_final_view_but_turns_stay_shut() -> void:
	_grant_old_world(MapScreen.PLAYER_FACTION)
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
	assert_true(screen.hud.is_victory_shown())

	screen.hud.victory_overlay.dismiss()

	assert_false(screen.hud.is_victory_shown())
	var turn_before: int = screen.turn
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
	assert_eq(screen.turn, turn_before, "dismissing the plate does not reopen play")
	assert_false(screen.hud.is_victory_shown(), "no second plate; the campaign stays decided")


func test_a_decided_campaign_loads_decided_with_the_seal_shut() -> void:
	_grant_old_world(MapScreen.PLAYER_FACTION)
	MapPlayTurn.end_turn(screen.play)
	Fixture.settle(screen.play)
	var decided: VictoryState = screen.play.victory
	assert_not_null(decided)
	var save: Dictionary = SaveCodec.capture(screen.play)
	assert_true(SaveCodec.is_valid(save), "a decided save is valid")

	var reopened: MapScreen = Fixture.open_save(self, save)

	assert_not_null(reopened.play.victory, "the decided campaign survives the save")
	assert_eq(reopened.play.victory.winner_player_id, decided.winner_player_id)
	assert_eq(reopened.play.victory.turn_number, decided.turn_number)
	assert_true(reopened.hud.is_victory_shown(), "the plate returns on load")
	assert_true(reopened.hud._end_turn_button.disabled)
	assert_eq(reopened.hud._end_turn_button.text, "CAMPAIGN ENDED")
	var turn_before: int = reopened.turn
	MapPlayTurn.end_turn(reopened.play)
	Fixture.settle(reopened.play)
	assert_eq(reopened.turn, turn_before, "turns stay shut after a load")
	reopened.free()


func _grant_old_world(faction_id: int) -> void:
	for province: ProvinceState in _old_world().provinces:
		province.owner = faction_id


func _old_world() -> MapModel:
	return Fixture.world().region(FactionCatalog.OLD_WORLD)


# --- the defeat plate --------------------------------------------------------
## Merged from test_campaign_defeat: Great Power defeat on terminal fall (wiki:
## victory § Great Power defeat, capital-and-connectivity § Great Power fall;
## DR-20261109-05). Each case strips a crown down to its seat, hands that seat to
## a rival and resolves the capital-loss pass, which is exactly how defeat
## happens in a real Combat phase.


func test_a_human_terminal_fall_is_defeat() -> void:
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = _defeat_rival(player)

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
	var rival: int = _defeat_rival(player)

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


func test_a_human_terminal_fall_seals_the_session_and_mounts_the_defeat_plate() -> void:
	var target: MapScreen = _attach()
	var conqueror: int = _defeat_rival(target.play.player_faction)

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
	var conqueror: int = _defeat_rival(target.play.player_faction)
	_fall_crown(target, target.play.player_faction, conqueror)
	var turn_before: int = target.turn

	MapPlayTurn.end_turn(target.play)

	assert_eq(target.turn, turn_before, "the seal keeps the turn number")
	assert_null(target.play.victory, "defeat does not grant a military victory")
	assert_not_null(target.play.defeat)
	assert_eq(target.hud.victory_overlay._title.text, "DEFEAT")


func test_an_ai_fall_removes_the_crown_and_the_campaign_sails_on() -> void:
	var target: MapScreen = _attach()
	var rival: int = _defeat_rival(target.play.player_faction)
	var holdings_before: int = target.play.world.owned_provinces(0, rival)

	_fall_crown(target, rival, target.play.player_faction)

	assert_null(target.play.defeat, "an AI fall is not the human's defeat")
	assert_false(target.play.campaign_over(), "the campaign continues")
	assert_false(target.hud.is_victory_shown())
	assert_eq(
		target.play.world.owned_provinces(0, rival), 0, "the crown left the map"
	)
	assert_gt(holdings_before, 0)


func test_a_defeated_slot_reopens_on_the_defeat_plate() -> void:
	var target: MapScreen = _attach()
	target.save_dir = DEFEAT_SAVE_DIR
	var conqueror: int = _defeat_rival(target.play.player_faction)
	_fall_crown(target, target.play.player_faction, conqueror)
	var save: Dictionary = SaveCodec.capture(target.play)
	assert_true(SaveCodec.is_valid(save))

	var reopened: MapScreen = _open_defeated(save)

	assert_not_null(reopened.play.defeat, "the defeat survives the save")
	assert_eq(reopened.play.defeat.conqueror_player_id, conqueror)
	assert_true(reopened.play.campaign_over())
	assert_true(reopened.hud.is_victory_shown(), "the plate returns on load")
	assert_eq(reopened.hud.victory_overlay._title.text, "DEFEAT")
	assert_true(reopened.hud._end_turn_button.disabled)
	var turn_before: int = reopened.turn
	MapPlayTurn.end_turn(reopened.play)
	assert_eq(reopened.turn, turn_before, "turns stay shut after a load")
	reopened.free()


func test_a_legacy_slot_without_a_defeat_field_stays_undefeated() -> void:
	var target: MapScreen = _attach()
	target.save_dir = DEFEAT_SAVE_DIR
	var save: Dictionary = SaveCodec.capture(target.play)
	save.erase("defeat")

	var reopened: MapScreen = _open_defeated(save)

	assert_null(reopened.play.defeat, "absent -> human not defeated")
	assert_false(reopened.play.campaign_over())
	reopened.free()


func test_a_fallen_crowns_civilians_leave_play() -> void:
	var target: MapScreen = _attach()
	var player: int = FactionCatalog.PLAYER_FACTION
	var rival: int = _defeat_rival(player)
	var civil: CivilianLayer = target.play.civilian_layer
	var tile: Vector2i = target.play.model.province_tiles(target.play.capital_province)[0]
	var crew: CivilianState = civil.add_unit(rival, "builder", tile)
	assert_true(civil.units.has(crew), "the fixture crew musters")

	_fall_crown(target, rival, player)

	assert_eq(civil.unit_count_all(rival), 0, "its crews leave with the crown")
	assert_false(civil.units.has(crew))


func _defeat_rival(player: int) -> int:
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
	MapPlayLandTurn.apply_capital_loss(play, losses)


func _open_defeated(data: Dictionary) -> MapScreen:
	return Fixture.open_save(self, data, DEFEAT_SAVE_DIR)
