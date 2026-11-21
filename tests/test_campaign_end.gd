# gdlint: disable=max-public-methods
extends GdToolsTest
## The campaign's end and the session codec that carries it: the calendar cap,
## endless mode, the campaign-complete / victory / defeat plates, and the
## SaveCodec round-trip on the real map screen (wiki: turn-time-mapping §
## Campaign calendar cap, victory § Calendar campaign end, § Victory Screen,
## § Great Power defeat; campaign-persistence; REQ-P3-03).
##
## Merged from test_campaign_end, test_victory_screen, test_campaign_defeat and
## test_save_codec: one Godot boot and one mounted chart for the whole theme.
## Every case re-seats the shared screen from the pristine save
## (`Fixture.suite_reset`), which drops a decided victory, a defeat, an open
## plate and a selection, so a case starts as the mount did. The codec cases
## used to pay a second boot and a private 32×32 world; they now ride this
## fixture chart (already ≥ `SaveCodec.MIN_MAP_SIDE`) and restore in place
## (docs/testing.md § Speed rules).

const SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")
const Fixture = preload("res://tests/map_fixture.gd")
const CAP: int = 201
const SAVE_DIR: String = "user://test_campaign_end"
const DEFEAT_SAVE_DIR: String = "user://test_campaign_defeat"
const CODEC_DIR: String = "user://test_save_codec"

## One mount for the suite: under coverage a mount costs ~0.5 s and a re-seat
## ~0.15 s, so live cases share the chart and reset the session instead. Pure
## calendar / defeat-classify cases never touch `screen`, so they skip the
## re-seat (docs/testing.md § Speed rules).
var mounted: MapScreen = null
var pristine: Dictionary = {}
## Ownership and seats as the shared world was generated: `_seat_crowns` and the
## fall cases rewrite owners, so each case starts from the same pristine world.
var saved: Array = []
## Set when this case has paid for a pristine re-seat; cleared in `before_each`.
var _chart_bound: bool = false


## Snapshotted before any case touches the fixture, so the base is a clean world.
func before_all() -> void:
	saved = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	_clean_codec_dir()
	_chart_bound = false


func after_each() -> void:
	Fixture.restore(Fixture.world(), saved)
	get_tree().paused = false
	_clean_codec_dir()


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	pristine = {}


## Live cases reach the chart through `screen` / `_attach()`; pure rule cases
## that never ask never pay `suite_reset`.
func _attach() -> MapScreen:
	if _chart_bound and is_instance_valid(mounted):
		return mounted
	Fixture.restore(Fixture.world(), saved)
	Fixture.suite_reset(mounted, pristine)
	mounted.save_dir = CODEC_DIR
	_chart_bound = true
	return mounted


var screen: MapScreen:
	get:
		return _attach()


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
	# Re-seat first: mutating the shared world before `_attach()` would be wiped
	# when the live case finally pays for its pristine chart.
	_attach()
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

# --- session codec (folded from test_save_codec) -----------------------------
## Save/load round trip on the shared mount: capture a live session, write it,
## and prove the mutable state came back without tearing MapScreen down
## (REQ-P3-03). Remounting under coverage was the codec suite's dominant cost;
## restoring over the fixture world is the same path a load uses.


## Applies a save onto the mounted screen without tearing it down.
func _apply_codec_save(data: Dictionary) -> PlaySession:
	var play: PlaySession = screen.play
	assert_true(SaveCodec.restore(play, data, Fixture.world()), "save restores over the preset")
	var target: int = play.region_index
	# Economy always founds on the Old World; restore there, then return.
	play.region_index = 0
	play.model = play.world.region(0)
	SaveCodec.restore_economy(play, data)
	play.diplomacy = DiplomacyState.new()
	SaveCodec.restore_diplomacy(play, data)
	play.diplomacy.human_faction = play.human_faction_id()
	play.region_index = target
	play.model = play.world.region(target)
	# Restore parks units in region tables and clears the live arrays; spawn
	# rebinds without rebuilding the canvas (load_region would remount the map).
	_rebind_codec_layers(play)
	return play


## Cheap post-restore: layers already hold the saved region tables, so spawn
## only reassigns the live arrays and markers.
func _rebind_codec_layers(play: PlaySession) -> void:
	var model: MapModel = play.model
	screen.army_layer.spawn(model)
	screen.ship_layer.world = play.world
	screen.ship_layer.spawn(
		model,
		MapScreen.SHIP_COUNT,
		MapScreen.MAP_SEED + 3 + play.region_index,
		play.capital_province,
		play.player_present(),
		play.player_faction
	)
	screen.civilian_layer.viewer_faction = play.player_faction
	screen.civilian_layer.spawn(
		model, play.capital_province, play.player_faction, MapScreen.STARTING_CIVILIANS
	)
	play.land_works = screen.civilian_layer.works


func test_round_trip_restores_session_world_and_layers() -> void:
	var play: PlaySession = screen.play
	MapPlayTurn.end_turn(play)
	while DiplomacyProposals.has_pending(play.diplomacy, 0):
		MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, 0, "")
	play.economy.economy.treasury = 4321
	play.economy.economy.stockpile["grain"] = 77
	play.economy.economy.workers.set_count(1, 3)
	play.economy.economy.research.unlocked["apprentice_workers"] = true
	play.economy.market.prices["grain"] = 99

	var foreign: int = _codec_foreign_province(play)
	play.model.get_province(foreign).owner = play.player_faction
	var deed_province: int = _codec_other_foreign_province(play, foreign)
	var deed_tile: Vector2i = play.model.province_tiles(deed_province)[0]
	assert_true(play.model.purchase_tile(deed_tile, play.player_faction))
	var tile: Vector2i = play.model.province_tiles(play.capital_province)[0]
	play.land_works.set_improvement(play.model, tile, 2)
	play.land_works.set_transport(play.model, tile, LandWorks.TRANSPORT_ROAD)
	play.land_works.add_port(play.model, tile)
	play.land_works.set_prospected(play.player_faction, play.model, tile)

	var fog_tile: Vector2i = _codec_fogged_tile(play)
	play.visibility.raise_to(
		play.model.index_of(fog_tile.x, fog_tile.y), VisibilityModel.Level.FULLY_VISIBLE
	)
	var unit: CivilianState = play.civilian_layer.units[0]
	unit.tile = tile
	unit.start_work("build_improvement", tile, 3)
	play.ship_layer.fleets[0].moved = true
	play.army_layer.armies[0].moved = true
	DiplomacyRules.declare_war(play.diplomacy, play.player_faction, 1)
	Intervention.queue_human(play.diplomacy, 3, 6, play.player_faction)
	assert_true(
		DiplomacyProposals.queue(
			play.diplomacy, play.world, 2,
			DiplomacyProposals.KIND_OVERTURE, DiplomacyCatalog.STAGE_NAP
		)["ok"]
	)
	play.charted_provinces[foreign] = true
	play.leaders[play.player_faction] = LeaderCatalog.DEFAULT_KEY

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveCodec.is_valid(data), "captured save is valid")
	assert_false(
		(data["session"] as Dictionary).has("prestige"),
		"the dead prestige counter is no longer serialised"
	)
	assert_true(
		SaveStore.write(CODEC_DIR + "/roundtrip.sav", data), "save file is written"
	)
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/roundtrip.sav")
	assert_false(loaded.is_empty(), "save file reads back")

	# Restore in place: the nation chip is wired at mount; refresh_after_load
	# re-reads turn/treasury so the HUD matches the slot (same path as a load).
	play = _apply_codec_save(loaded)
	MapPlaySetup.refresh_after_load(play)
	assert_eq(play.turn, 2, "turn restored")
	assert_eq(play.player_faction, FactionCatalog.PLAYER_FACTION, "nation restored")
	assert_eq(play.economy.economy.treasury, 4321, "treasury restored")
	assert_eq(play.economy.economy.quantity("grain"), 77, "stockpile restored")
	assert_eq(play.economy.economy.workers.count(1), 3, "workers restored")
	assert_true(
		play.economy.economy.research.is_unlocked("apprentice_workers"),
		"research restored"
	)
	assert_eq(play.economy.market.price("grain"), 99, "market prices restored")
	assert_eq(
		play.model.province_owner(foreign), play.player_faction, "province owners restored"
	)
	assert_eq(
		play.model.owner_at(deed_tile.x, deed_tile.y),
		play.player_faction,
		"tile deed restored"
	)
	assert_true(play.model.is_purchased_tile(deed_tile), "deed marker restored")
	assert_eq(play.land_works.improvement_at(play.model, tile), 2, "works restored")
	assert_eq(
		play.land_works.transport_at(play.model, tile),
		LandWorks.TRANSPORT_ROAD,
		"roads restored"
	)
	assert_true(play.land_works.has_port(play.model, tile), "ports restored")
	assert_true(
		play.land_works.is_prospected(play.player_faction, play.model, tile),
		"prospect state restored"
	)
	assert_eq(
		play.visibility.level_at(fog_tile.x, fog_tile.y),
		VisibilityModel.Level.FULLY_VISIBLE,
		"fog state restored"
	)
	var player_civilians: int = 0
	for civilian: CivilianState in play.civilian_layer.units:
		if civilian.owner == play.player_faction:
			player_civilians += 1
	assert_eq(player_civilians, 3, "the human civilians restored")
	assert_true(
		play.civilian_layer.unit_count_all(1) >= 3,
		"a rival's seeded civilians restored too"
	)
	assert_eq(play.civilian_layer.units[0].tile, tile, "civilian tile restored")
	assert_true(play.civilian_layer.units[0].is_working(), "civilian work restored")
	assert_eq(play.civilian_layer.units[0].remaining_turns(), 3, "work turns restored")
	assert_true(play.ship_layer.fleets[0].moved, "fleet orders restored")
	assert_true(play.army_layer.armies[0].moved, "army orders restored")
	assert_true(
		play.diplomacy.relation(play.player_faction, 1).at_war, "war state restored"
	)
	assert_true(
		Intervention.has_pending(play.diplomacy, play.player_faction),
		"a waiting intervention restored"
	)
	assert_true(
		DiplomacyProposals.has_pending(play.diplomacy, play.player_faction),
		"a waiting rival proposal restored"
	)
	assert_true(play.charted_provinces.has(foreign), "charted provinces restored")
	assert_eq(
		String(play.leaders.get(play.player_faction, "")),
		LeaderCatalog.DEFAULT_KEY,
		"leader keys restored"
	)
	assert_eq(
		String(play.leaders.get(1, "")),
		LeaderCatalog.default_key(1),
		"rival crowns keep their leader"
	)
	assert_eq(screen.hud._nation_label.text, "SPAIN", "HUD reads the restored nation")


func test_saves_without_leaders_backfill_the_crown_roster() -> void:
	var play: PlaySession = screen.play
	var data: Dictionary = SaveCodec.capture(play)
	var session: Dictionary = data["session"]
	session.erase("leaders")
	data["session"] = session

	play = _apply_codec_save(data)
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			String(play.leaders.get(faction, "")),
			LeaderCatalog.default_key(faction),
			"crown %d gets its configured leader" % faction
		)


## The temperaments bound at creation ride the save (wiki: ai-profile-overrides —
## the binding is fixed for the run): a rival comes back on the profile its run
## bound, and a save from before the binding existed resumes every rival neutral.
func test_bound_temperaments_survive_a_load() -> void:
	var play: PlaySession = screen.play
	play.ensure_ai().profiles = AiProfile.roster({2: AiProfile.AGGRESSIVE})
	var data: Dictionary = SaveCodec.capture(play)
	var ai_saved: Dictionary = data.get("ai", {})
	assert_eq(
		String((ai_saved.get("profiles", {}) as Dictionary).get(2, "")),
		AiProfile.AGGRESSIVE,
		"the save carries the temperament"
	)
	play = _apply_codec_save(data)
	assert_eq(String(play.ensure_ai().profiles.get(2, "")), AiProfile.AGGRESSIVE, "France resumes aggressive")
	assert_eq(String(play.ensure_ai().profiles.get(1, "")), AiProfile.NORMAL, "England resumes neutral")
	# A legacy save (no binding) resumes every rival on the neutral profile.
	var legacy: Dictionary = SaveCodec.capture(screen.play)
	(legacy["ai"] as Dictionary).erase("profiles")
	play = _apply_codec_save(legacy)
	for faction: int in FactionCatalog.great_power_ids():
		assert_eq(
			String(play.ensure_ai().profiles.get(faction, "")), AiProfile.NORMAL,
			"crown %d resumes neutral" % faction
		)


## The crown's watch over rival squadrons rides the save (wiki: ships-and-naval
## § Sighted strength): a read squadron stays read, a sighted one stays unread,
## and each chart's watch lands back on its own map.
func test_a_sighted_strength_read_survives_a_load() -> void:
	var play: PlaySession = screen.play
	var region: int = play.region_index
	play.naval_intel.observe([7], play.turn, region)
	play.naval_intel.observe([7, 8], play.turn + 1, region)

	var data: Dictionary = SaveCodec.capture(play)
	var session: Dictionary = data["session"]
	var watches: Dictionary = (session["naval_intel"] as Dictionary)["regions"]
	assert_eq(
		(watches[region] as Dictionary)["revealed"], [7],
		"only the watched squadron is in the read list"
	)

	play = _apply_codec_save(data)
	assert_true(play.naval_intel.is_revealed(7, region), "a read squadron stays read")
	assert_false(play.naval_intel.is_revealed(8, region), "an unread squadron stays unread")


func test_a_save_without_a_watch_resumes_unread() -> void:
	var play: PlaySession = screen.play
	var region: int = play.region_index
	play.naval_intel.observe([7], play.turn, region)
	play.naval_intel.observe([7], play.turn + 1, region)
	var data: Dictionary = SaveCodec.capture(play)
	var session: Dictionary = data["session"]
	session.erase("naval_intel")
	data["session"] = session

	play = _apply_codec_save(data)

	assert_eq(play.naval_intel.watched(region), [], "a legacy save reads no squadron")


func test_medals_and_feeding_survive_a_load() -> void:
	var play: PlaySession = screen.play
	var roster: GeneralRoster = play.army_layer.generals
	roster.sync(play.player_faction, {})
	roster.award(play.player_faction, "general_1")
	roster.award(play.player_faction, "general_1")
	play.feeding[play.player_faction] = 0.4
	play.economy.economy.navy_feeding = 0.5
	play.ai = AiState.new()
	play.ai.agenda_for(AiConfig.build(2, 1))
	play.ai.note_war(play.player_faction, 2, play.turn)
	play.ai.note_peace(play.player_faction, 2, play.turn, false)

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(CODEC_DIR + "/generals.sav", data), "save file is written")
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/generals.sav")

	play = _apply_codec_save(loaded)
	assert_eq(
		play.army_layer.generals.medals(play.player_faction, "general_1"),
		2,
		"medals never decrease across a load (wiki: military-generals § Medals)"
	)
	assert_eq(play.army_layer.generals.count(play.player_faction), 1, "roster size restored")
	assert_true(play.feeding.has(play.player_faction), "feeding coverage restored")
	assert_true(
		is_equal_approx(float(play.feeding[play.player_faction]), 0.4),
		"last rations feed the first battle after a load (wiki: combat § Feeding)"
	)
	assert_true(
		is_equal_approx(play.economy.economy.navy_feeding, 0.5),
		"last rations feed the first sea battle after a load"
	)
	assert_not_null(play.ai, "rival-court bookkeeping restored")
	assert_true(
		play.ai.war_on_cooldown(play.player_faction, 2, play.turn, 4),
		"a load does not restart the war cooldown (wiki: diplomacy § Cooldowns)"
	)
	assert_true(
		play.ai.peace_on_cooldown(play.player_faction, 2, play.turn, 3),
		"a load does not restart the peace-offer cooldown (DR-20261109-07)"
	)
	assert_eq(
		play.ai.peace_refusals_for(play.player_faction, 2), 1,
		"a load keeps the refusal the court waits on (DR-20261115-01)"
	)


func test_saved_region_index_reopens_that_map() -> void:
	var play: PlaySession = screen.play
	screen._cycle_region()
	assert_eq(play.region_index, 1)
	play.turn = 9
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(CODEC_DIR + "/region.sav", data))
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/region.sav")

	play = _apply_codec_save(loaded)
	assert_eq(play.region_index, 1, "saved region reopened")
	assert_eq(play.model.region_id, FactionCatalog.NEW_WORLD)
	assert_eq(play.turn, 9)
	assert_eq(play.economy.model.region_id, FactionCatalog.OLD_WORLD)


func test_invalid_and_corrupt_saves_are_refused() -> void:
	assert_false(SaveCodec.is_valid({}), "empty data is invalid")
	assert_false(SaveCodec.is_valid({"version": 999}), "future version is invalid")
	var data: Dictionary = SaveCodec.capture(screen.play)
	data["version"] = 999
	assert_false(SaveStore.save_slot(1, data, CODEC_DIR), "invalid save is not written")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CODEC_DIR))
	var file := FileAccess.open(CODEC_DIR + "/broken.sav", FileAccess.WRITE)
	assert_not_null(file, "corrupt fixture opens")
	if file == null:
		return
	file.store_string("not a variant")
	file.close()
	assert_true(SaveStore.read(CODEC_DIR + "/broken.sav").is_empty(), "corrupt read is empty")


func test_a_fort_stands_after_a_load() -> void:
	var play: PlaySession = screen.play
	var province: ProvinceState = play.model.provinces[0]
	province.fort_level = FortRules.MAX_LEVEL
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(CODEC_DIR + "/forts.sav", data))
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/forts.sav")

	play = _apply_codec_save(loaded)
	assert_eq(
		play.model.get_province(province.id).fort_level,
		FortRules.MAX_LEVEL,
		"walls are part of the world state a load restores"
	)


func test_a_waiting_call_to_arms_stays_suspended_after_a_load() -> void:
	var play: PlaySession = screen.play
	var pact: DiplomacyRelation = play.diplomacy.relation(0, 2)
	pact.formal_alliance = true
	pact.score = 80.0
	CallToArms.freeze_alliances(play.diplomacy)
	DiplomacyRules.declare_war(play.diplomacy, 3, 2)
	MapPlayTurn.end_turn(play)
	assert_true(play.turn_suspended, "the call holds the turn")
	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(CODEC_DIR + "/call.sav", data))
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/call.sav")

	play = _apply_codec_save(loaded)
	MapPlaySetup.refresh_after_load(play)
	assert_true(CallToArms.has_pending(play.diplomacy, 0), "the call is restored")
	assert_true(play.turn_suspended, "the loaded turn is still suspended")
	assert_true(
		screen.hud.panels.diplomacy_panel._call_box.visible,
		"the court re-opens for the answer"
	)


## The crown's stance is state a battle reads this turn, so a save carries it
## and a load must not silently reset it (wiki: campaign-persistence
## § Snapshot contract — crown battle plan; DR-20261110-33).
func test_the_crowns_battle_plan_survives_a_load() -> void:
	var play: PlaySession = screen.play
	play.battle_plan = "aggressive"
	var data: Dictionary = SaveCodec.capture(play)
	assert_eq(
		String((data["session"] as Dictionary).get("battle_plan", "")),
		"aggressive",
		"the save carries the plan"
	)
	assert_true(SaveStore.write(CODEC_DIR + "/plan.sav", data))
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/plan.sav")

	play = _apply_codec_save(loaded)
	assert_eq(
		play.battle_plan, "aggressive",
		"the loaded crown still fights with its own plan"
	)


## A slot written before the plan was carried, or naming a script this build
## does not have, resumes on the default stance without an error (wiki:
## campaign-persistence § Load and resume — legacy defaults).
func test_a_save_without_a_readable_plan_lands_on_the_default_stance() -> void:
	var play: PlaySession = screen.play
	play.battle_plan = "defensive"
	# Both payloads come from the opening screen so the case pays for two loads,
	# not a third remount just to re-capture a fresh session.
	var data: Dictionary = SaveCodec.capture(play)
	var session: Dictionary = data["session"]
	session.erase("battle_plan")
	data["session"] = session
	play = _apply_codec_save(data)
	assert_eq(
		play.battle_plan, SaveCodec.DEFAULT_BATTLE_PLAN,
		"a legacy slot opens on the default stance"
	)

	var fresh: Dictionary = SaveCodec.capture(play)
	var fresh_session: Dictionary = fresh["session"]
	fresh_session["battle_plan"] = "reckless"
	fresh["session"] = fresh_session
	play = _apply_codec_save(fresh)
	assert_eq(
		play.battle_plan, SaveCodec.DEFAULT_BATTLE_PLAN,
		"an unknown script falls back to the default"
	)


## The college ledger's goal is client state kept with the campaign, so a save
## carries it and a load reopens the queue on the same path instead of catalog
## order (wiki: tech-tree § Goal slot, campaign-persistence § Snapshot contract;
## DR-20261111-21).
func test_the_research_goal_survives_a_save() -> void:
	var play: PlaySession = screen.play
	play.economy.economy.research.goal = "bayonet"
	var data: Dictionary = SaveCodec.capture(play)
	assert_eq(
		String(((data["economy"] as Dictionary).get("research", {}) as Dictionary).get("goal", "")),
		"bayonet",
		"the save carries the goal"
	)
	play.economy.economy.research.goal = ""
	SaveCodec.restore_economy(play, data)
	assert_eq(
		play.economy.economy.research.goal, "bayonet",
		"a load brings the goal back to the ledger"
	)


## The difficulty layer is fixed at creation, so a load must not re-roll it and
## must bring the rival ledgers back at the level they were founded on
## (wiki: ruleset-config § Layers). A rival ledger is founded once, on the first
## read: raising the layer later re-stamps the planner but never re-founds a
## ledger that already stands, so this campaign (created on Normal) keeps the
## published row and a fresh run founded at Hard opens with more.
func test_the_difficulty_layer_survives_a_load() -> void:
	var play: PlaySession = screen.play
	play.difficulty = "hard"
	# Drop ledgers founded at the suite's Normal layer so Hard scales a fresh
	# start (wiki: ruleset-config § Layers — rivals open with 140% stores).
	var ai: AiState = play.ensure_ai()
	ai.economies.clear()
	var rival: PlayerEconomy = ai.economy_for(1)
	var purse: int = rival.treasury
	assert_eq(play.ai.difficulty, "hard", "the planner takes the new layer")
	assert_eq(
		purse, PlayerEconomy.START_TREASURY,
		"a ledger already founded keeps the level it was founded on"
	)
	var fresh := PlaySession.new()
	fresh.difficulty = "hard"
	assert_gt(
		fresh.ensure_ai().economy_for(1).treasury, PlayerEconomy.START_TREASURY,
		"a run founded at hard opens its rivals with more"
	)

	var data: Dictionary = SaveCodec.capture(play)
	assert_eq(String((data["session"] as Dictionary).get("difficulty", "")), "hard")
	assert_true(SaveStore.write(CODEC_DIR + "/difficulty.sav", data))
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/difficulty.sav")

	play = _apply_codec_save(loaded)
	assert_eq(play.difficulty, "hard", "the layer is fixed for the campaign")
	assert_eq(play.ai.difficulty, "hard")
	assert_eq(play.ai.economy_for(1).treasury, purse, "the rival purse returns as saved")


func test_the_gazette_watchlist_and_archive_survive_a_load() -> void:
	var play: PlaySession = screen.play
	MapPlayTurn.end_turn(play)
	while DiplomacyProposals.has_pending(play.diplomacy, 0):
		MapCourtOrders.apply(play, DiplomacyProposals.KIND_REFUSE, 0, "")
	assert_true(play.gazette != null, "the close founded the watchlist")
	assert_true(play.gazette.has_sheet(1), "the resolved turn is filed")
	play.gazette.set_watched(1, false)
	var filed: int = play.gazette.sheets.size()

	var data: Dictionary = SaveCodec.capture(play)
	assert_true(SaveStore.write(CODEC_DIR + "/gazette.sav", data))
	var loaded: Dictionary = SaveStore.read(CODEC_DIR + "/gazette.sav")

	play = _apply_codec_save(loaded)
	assert_true(play.gazette != null, "the sheet returns on load")
	assert_eq(play.gazette.sheets.size(), filed, "the archive comes back whole")
	assert_false(play.gazette.is_watched(1), "a struck-off court stays struck off")
	assert_true(play.gazette.removed.has(1), "and the removal is remembered")


func _codec_foreign_province(play: PlaySession) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction:
			return province.id
	return -1


func _codec_other_foreign_province(play: PlaySession, skip: int) -> int:
	for province: ProvinceState in play.model.provinces:
		if province.owner != play.player_faction and province.id != skip:
			return province.id
	return skip


func _codec_fogged_tile(play: PlaySession) -> Vector2i:
	for province: ProvinceState in play.model.provinces:
		if province.owner == play.player_faction:
			continue
		for tile: Vector2i in province.tiles:
			if play.visibility.level_at(tile.x, tile.y) == VisibilityModel.Level.FOGGED:
				return tile
	return play.capital_tile


func _clean_codec_dir() -> void:
	var path: String = ProjectSettings.globalize_path(CODEC_DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(CODEC_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
