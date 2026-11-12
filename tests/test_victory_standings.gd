# gdlint: disable=max-public-methods
extends GdToolsTest
## The age's race as the court reads it (wiki: victory § Military victory,
## § Victory Check): Old World holdings per crown against the bar that crown
## must clear, the leader, the calendar and the turn's warning.

const Fixture = preload("res://tests/map_fixture.gd")
const SPAIN: int = FactionCatalog.PLAYER_FACTION
const ENGLAND: int = 1
const FRANCE: int = 2
const HARD: String = "hard"

var saved_world: Array = []
var saved_region: Array = []


## Snapshotted before any case touches the fixtures: they are shared per worker.
func before_all() -> void:
	saved_world = Fixture.snapshot(Fixture.world())
	saved_region = Fixture.snapshot(_wrap(Fixture.region()))


func before_each() -> void:
	Fixture.restore(Fixture.world(), saved_world)
	Fixture.restore(_wrap(Fixture.region()), saved_region)


func after_each() -> void:
	Fixture.restore(Fixture.world(), saved_world)
	Fixture.restore(_wrap(Fixture.region()), saved_region)


# --- the rows ----------------------------------------------------------------


func test_every_great_power_is_ranked_by_old_world_holdings() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 4, ENGLAND: 9, FRANCE: 2})
	var standings: Array[Dictionary] = VictoryStandings.rows(world, SPAIN)
	assert_eq(standings.size(), FactionCatalog.great_power_ids().size())
	assert_eq(String(standings[0]["name"]), "England", "equal bars: the most provinces leads")
	assert_eq(int(standings[0]["holdings"]), 9)
	assert_eq(int(standings[0]["need"]), 22, "a rival clears the published 31")
	assert_eq(String(standings[1]["name"]), "Spain")
	assert_true(bool(standings[1]["human"]), "the reader's row is marked")


func test_the_crown_bar_carries_the_level_and_rivals_keep_the_published_one() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 30, ENGLAND: 30})
	var crown: Dictionary = VictoryStandings.crown_row(
		VictoryStandings.rows(world, SPAIN, HARD), SPAIN
	)
	var rival: Dictionary = VictoryStandings.next_rival(
		VictoryStandings.rows(world, SPAIN, HARD)
	)
	assert_eq(int(crown["bar"]), 36, "hard scales the crown's own bar")
	assert_eq(int(rival["bar"]), 31, "every rival keeps the published bar")
	assert_eq(int(crown["need"]), 6)
	assert_eq(int(rival["need"]), 1)


func test_only_old_world_provinces_count() -> void:
	var world: WorldMap = Fixture.world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 5})
	var before: int = int(VictoryStandings.crown_row(VictoryStandings.rows(world, SPAIN), SPAIN)["holdings"])
	_seat(world.region(WorldMap.NEW_WORLD), {SPAIN: 20})
	var after: int = int(VictoryStandings.crown_row(VictoryStandings.rows(world, SPAIN), SPAIN)["holdings"])
	assert_eq(after, before, "a New World empire is not the age")
	assert_eq(after, 5)


func test_a_shared_holdings_count_keeps_the_smaller_id_first() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 7, ENGLAND: 7, FRANCE: 7})
	var standings: Array[Dictionary] = VictoryStandings.rows(world, SPAIN)
	assert_eq(int(standings[0]["id"]), SPAIN)
	assert_eq(int(standings[1]["id"]), ENGLAND)
	assert_eq(int(standings[2]["id"]), FRANCE)


# --- the court's line --------------------------------------------------------


## The race ranks each crown against **its own** bar: on a harder level the crown
## carries a 36 bar, so a rival holding fewer provinces can stand nearer the age
## (wiki: victory § Military victory; DR-20261112-05 — `England leads with 9 of
## 31` beside `you hold 12 of 36`).
func test_the_race_ranks_by_distance_to_each_crown_bar() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 12, ENGLAND: 9})
	var standings: Array[Dictionary] = VictoryStandings.rows(world, SPAIN, HARD)
	assert_eq(String(standings[0]["name"]), "England", "the nearer crown leads")
	assert_eq(int(standings[0]["need"]), 22)
	assert_eq(int(standings[1]["need"]), 24, "twelve of thirty-six is the longer road")
	var line: String = VictoryStandings.line(world, 3, SPAIN, HARD)
	assert_true(line.contains("England leads with 9 of 31"), line)
	assert_false(line.contains("you lead"), "more provinces is not the same as nearer the age")


## The crown can hold the most provinces in the world and still be told it is
## behind: at hard, 30 of 36 is six away while a rival's 29 of 31 is two.
func test_the_crown_is_named_behind_though_it_holds_the_most() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 30, ENGLAND: 29})
	var line: String = VictoryStandings.line(world, 3, SPAIN, HARD)
	assert_true(line.contains("England leads with 29 of 31"), line)
	assert_false(line.contains("you lead"), "the crown's own bar sets its road, not the rival's")


func test_the_line_names_the_crown_the_leader_and_the_calendar() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 9, ENGLAND: 12})
	var line: String = VictoryStandings.line(world, 5, SPAIN)
	assert_true(line.contains("you hold 9 of 31 Old World provinces"), line)
	assert_true(line.contains("England leads with 12 of 31"), line)
	assert_true(line.contains("the calendar closes in %d turns" % (TurnTime.cap_turn() - 5)), line)


func test_the_line_says_when_the_crown_leads() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 14, ENGLAND: 9})
	var line: String = VictoryStandings.line(world, 3, SPAIN)
	assert_true(line.contains("you lead"), line)
	assert_true(line.contains("England follows with 9 of 31"), line)


func test_the_line_reads_the_advanced_bar_at_a_harder_level() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 9, ENGLAND: 12})
	var line: String = VictoryStandings.line(world, 3, SPAIN, HARD)
	assert_true(line.contains("you hold 9 of 36"), line)
	assert_true(line.contains("England leads with 12 of 31"), line)


func test_an_endless_campaign_names_no_calendar() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 12, ENGLAND: 9})
	var line: String = VictoryStandings.line(world, 3, SPAIN, Difficulty.DEFAULT, true)
	assert_true(line.contains("no calendar closes this age"), line)
	assert_false(line.contains("calendar closes in"), line)


func test_the_line_is_empty_without_a_crown_to_read() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {ENGLAND: 9})
	assert_eq(VictoryStandings.line(world, 3), "", "the full-AI observer has no crown")


# --- the turn's warning ------------------------------------------------------


func test_the_warning_is_silent_while_the_age_is_distant() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 12})
	assert_eq(VictoryStandings.warning(world, SPAIN), "")


func test_the_warning_names_a_rival_within_three_provinces() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 28})
	var warning: String = VictoryStandings.warning(world, SPAIN)
	assert_eq(warning, "England stands 3 provinces from the age (28 of 31 Old World).")


func test_the_warning_counts_one_province_in_the_singular() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 30})
	var warning: String = VictoryStandings.warning(world, SPAIN)
	assert_eq(warning, "England stands 1 province from the age (30 of 31 Old World).")


func test_the_warning_names_the_crown_too() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 34, ENGLAND: 10})
	var warning: String = VictoryStandings.warning(world, SPAIN, HARD)
	assert_eq(warning, "Your crown stands 2 provinces from the age (34 of 36 Old World).")


func test_the_warning_names_both_when_both_are_close() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 29, ENGLAND: 28})
	var warning: String = VictoryStandings.warning(world, SPAIN)
	assert_eq(
		warning,
		"Your crown stands 2 provinces from the age (29 of 31 Old World). "
		+ "England stands 3 provinces from the age (28 of 31 Old World)."
	)


func test_a_crown_on_its_bar_is_not_merely_warned() -> void:
	var world := _old_world()
	_seat(world.region(WorldMap.OLD_WORLD), {SPAIN: 10, ENGLAND: 31})
	# The victory check closes the campaign before a warning could print; the
	# reading stays silent so the two never disagree.
	assert_eq(VictoryStandings.warning(world, SPAIN), "")


# --- fixtures ----------------------------------------------------------------


## A single-region world over the shared small map, with every province
## unclaimed until a case seats it.
func _old_world() -> WorldMap:
	var world: WorldMap = _wrap(Fixture.region())
	_seat(world.region(WorldMap.OLD_WORLD), {})
	return world


## The shared small map wrapped as a one-region world, so the fixture's
## snapshot/restore pair can read it.
static func _wrap(model: MapModel) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(model)
	return world


## Hands the province list to the crowns in the order given, the rest unclaimed.
func _seat(model: MapModel, counts: Dictionary) -> void:
	var owners: Array[int] = []
	for faction_id: int in counts:
		for _index in int(counts[faction_id]):
			owners.append(faction_id)
	for index in model.provinces.size():
		model.provinces[index].owner = owners[index] if index < owners.size() else MapModel.NO_ID
