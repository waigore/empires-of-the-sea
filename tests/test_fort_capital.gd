extends GdToolsTest
## An Old World capital opens behind a Wood wall, and a Great Power's fort tech
## lifts its own capital one level once — never a Minor's, and never again after
## a siege takes the wall down (wiki: siege-mechanics § Fort Levels; issue #919).
##
## Two rules, two owners: `FortCapital.seed` is [WorldBootstrap]'s start-of-campaign
## grant, `FortCapital.apply_research` is the turn close's read of the research
## report each ledger filed (the crown's and every rival's).
##
## Hand-built charts keep the cases explicit: a province id is its index in
## `provinces`, so a seat is one [ProvinceState] with the capital flag.

const OLD_WORLD: int = FactionCatalog.OLD_WORLD
const NEW_WORLD: int = FactionCatalog.NEW_WORLD

var great_power: int = FactionCatalog.PLAYER_FACTION
var other_power: int = FactionCatalog.great_power_ids()[1]
var minor: int = FactionCatalog.minor_ids()[0]


## One chart with one capital province per entry of `owners`, in order.
func _chart(region_id: int, owners: Array) -> MapModel:
	var model := MapModel.new()
	model.region_id = region_id
	model.setup(owners.size() * 2, 2)
	for index in owners.size():
		var tiles: Array[Vector2i] = []
		model.provinces.append(ProvinceState.create(
			index, "Province %d" % index, tiles, Vector2.ZERO, 1,
			int(owners[index]), true
		))
	return model


func _world(model: MapModel) -> WorldMap:
	var world := WorldMap.new()
	world.add_region(model)
	return world


# --- start grant -------------------------------------------------------------


## Both kinds of Old World seat — Great Power and Minor — open behind a Wood
## wall, and the bootstrap reports what it raised.
func test_every_old_world_capital_opens_behind_a_wood_wall() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power, other_power, minor])
	var report: Dictionary = WorldBootstrap.apply(model, LandWorks.new())
	assert_eq(int(report["capital_forts"]), 3, "every capital was walled")
	for province: ProvinceState in model.provinces:
		assert_eq(
			province.fort_level, FortCapital.START_LEVEL,
			"capital of %d is Wood" % province.owner
		)
		assert_eq(
			FortRules.level_name(province.fort_level), "Wood",
			"the start level is the Wood tier"
		)


## A New World chart keeps its tribe seats open: the grant is an Old World rule.
func test_a_new_world_seat_is_left_open() -> void:
	var tribe: int = FactionCatalog.tribe_ids()[0]
	var model: MapModel = _chart(NEW_WORLD, [tribe])
	var report: Dictionary = WorldBootstrap.apply(model, LandWorks.new())
	assert_eq(int(report["capital_forts"]), 0)
	assert_eq(model.provinces[0].fort_level, 0, "a tribe's seat carries no wall")


## The grant only raises: a hand-built chart that already walls its seat keeps
## the wall it drew.
func test_the_grant_never_lowers_a_wall() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power])
	model.provinces[0].fort_level = FortRules.MAX_LEVEL
	assert_eq(FortCapital.seed(model), 0)
	assert_eq(model.provinces[0].fort_level, FortRules.MAX_LEVEL)


# --- the free bump -----------------------------------------------------------


## Mine Engineering lifts the crown's own capital to Stone and Modern Forts to
## Modern, each at its own unlock; a repeat read of the same study moves nothing.
func test_a_great_power_fort_tech_lifts_its_capital_once() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power])
	var world: WorldMap = _world(model)
	FortCapital.seed(model)
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]}),
		FortCapital.LEVELS["mine_engineering"],
		"the crown's capital reaches Stone"
	)
	assert_eq(model.provinces[0].fort_level, 2)
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]}),
		0, "the same study never bumps twice"
	)
	assert_eq(model.provinces[0].fort_level, 2)
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["modern_forts"]}),
		FortCapital.LEVELS["modern_forts"],
		"Modern Forts carries the capital to the top tier"
	)
	assert_eq(model.provinces[0].fort_level, 3)


## A court that finishes a study without a wall in it keeps its wall as it was.
func test_a_study_with_no_fort_in_it_moves_nothing() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power])
	var world: WorldMap = _world(model)
	FortCapital.seed(model)
	assert_eq(FortCapital.apply_research(world, great_power, {"researched": ["navigation"]}), 0)
	assert_eq(FortCapital.apply_research(world, great_power, {}), 0)
	assert_eq(model.provinces[0].fort_level, 1)


## Minors never take the free bump: their walls are what an Engineer builds
## (wiki: siege-mechanics § Fort Levels — the grant is a Great Power rule).
func test_a_minor_keeps_only_the_wall_it_built() -> void:
	var model: MapModel = _chart(OLD_WORLD, [minor])
	var world: WorldMap = _world(model)
	FortCapital.seed(model)
	assert_eq(model.provinces[0].owner, minor)
	assert_eq(FortCapital.apply_research(world, minor, {"researched": ["modern_forts"]}), 0)
	assert_eq(model.provinces[0].fort_level, 1, "a Minor stays at its Wood wall")


## The bump is a moment, not a floor: a capital taken down by a siege is not
## raised again by the rule that once lifted it. Only a later fort study of its
## own lifts it (Modern Forts below).
func test_a_siege_downgrade_is_not_restored() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power])
	var world: WorldMap = _world(model)
	FortCapital.seed(model)
	FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]})
	assert_eq(model.provinces[0].fort_level, 2)
	model.provinces[0].fort_level = 0  # the besieging train took the last gun
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["navigation"]}),
		0, "a later turn's study restores nothing"
	)
	assert_eq(model.provinces[0].fort_level, 0, "the wall stays down until rebuilt")
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["modern_forts"]}),
		FortCapital.LEVELS["modern_forts"], "only its own fort study lifts it again"
	)
	assert_eq(model.provinces[0].fort_level, 3)


## A capital already above the unlock's level is left where it stands.
func test_a_wall_above_the_unlock_is_left_alone() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power])
	var world: WorldMap = _world(model)
	model.provinces[0].fort_level = FortRules.MAX_LEVEL
	assert_eq(
		FortCapital.apply_research(world, great_power, {"researched": ["mine_engineering"]}),
		0
	)
	assert_eq(model.provinces[0].fort_level, FortRules.MAX_LEVEL)


# --- the turn close ----------------------------------------------------------


## The turn close reads both books: the rivals' rows and the crown's own report
## name the studies that finished, and each Great Power's capital follows its
## own ledger. A rival's row is the whole economy report, so its research phase
## rides under `research` — the shape `EconomyTurn.resolve` files and the
## Gazette and spy despatch read.
func test_the_turn_close_lifts_each_courts_own_capital() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power, other_power, minor])
	FortCapital.seed(model)
	var play := PlaySession.new()
	play.world = _world(model)
	play.player_faction = great_power
	var book := MapPlayTurnFinish.TurnBook.new()
	book.crown_report = {"research": {"researched": ["modern_forts"]}}
	book.economy_report = {"factions": {
		other_power: {"resolved": {"research": {"researched": ["mine_engineering"]}}},
		minor: {"resolved": {"research": {"researched": ["modern_forts"]}}},
	}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(model.provinces[0].fort_level, 3, "the crown's capital reached Modern")
	assert_eq(model.provinces[1].fort_level, 2, "the rival's capital reached Stone")
	assert_eq(model.provinces[2].fort_level, 1, "the Minor keeps its Wood wall")


## A rival's row is the economy report, not the research report: the step reads
## the nested `research` slot the ledger files. A row whose top level carries no
## research phase moves nothing, and a row that is not a report at all is
## skipped rather than trusted.
func test_the_turn_close_reads_the_nested_research_report() -> void:
	var model: MapModel = _chart(OLD_WORLD, [great_power, other_power])
	FortCapital.seed(model)
	var play := PlaySession.new()
	play.world = _world(model)
	play.player_faction = great_power
	var book := MapPlayTurnFinish.TurnBook.new()
	book.crown_report = {}
	book.economy_report = {"factions": {
		other_power: {"resolved": {"consumption": {}, "researched": ["mine_engineering"]}},
	}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(
		model.provinces[1].fort_level, 1,
		"a study filed outside the research phase lifts no wall"
	)
	book.economy_report = {"factions": {other_power: {"resolved": null}}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(model.provinces[1].fort_level, 1, "a row with no report is skipped")
	book.economy_report = {"factions": {other_power: {"resolved": {"research": null}}}}
	MapPlayTurnFinish._fort_upgrades(play, book)
	assert_eq(model.provinces[1].fort_level, 1, "a row with no research phase is skipped")