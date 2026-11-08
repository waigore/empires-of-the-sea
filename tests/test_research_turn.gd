extends GdToolsTest
## The Research phase: funding, points, completion and the economy hand-off
## (wiki: tech-tree § Research Model; tech-and-extraction-cap).

const Fixture = preload("res://tests/civilian_fixture.gd")

var _economy: PlayerEconomy = null
var _state: ResearchState = null


func before_each() -> void:
	_economy = PlayerEconomy.starting()
	_state = _economy.research


func _resolve(turns: int) -> Dictionary:
	var report: Dictionary = {}
	for _turn in turns:
		report = ResearchTurn.resolve(_state, _economy)
	return report


func test_a_tier_one_tech_takes_six_medium_turns() -> void:
	assert_true(bool(_state.assign("land_enclosure", "medium")["ok"]))
	_resolve(5)
	assert_false(_state.is_unlocked("land_enclosure"))
	assert_eq(_state.progress_of("land_enclosure"), 1500)
	_resolve(1)
	assert_true(_state.is_unlocked("land_enclosure"))
	assert_eq(_state.tech_at(0), ResearchState.EMPTY_TECH)


func test_a_tier_four_tech_takes_twelve_medium_turns() -> void:
	_state.unlock("large_coal_mines")
	_state.unlock("dynamite")
	assert_true(bool(_state.assign("safety_lamp", "medium")["ok"]))
	_resolve(11)
	assert_false(_state.is_unlocked("safety_lamp"))
	assert_eq(_state.progress_of("safety_lamp"), 3300)
	_resolve(1)
	assert_true(_state.is_unlocked("safety_lamp"))


func test_low_funding_earns_one_hundred_points() -> void:
	var report: Dictionary = {}
	assert_true(bool(_state.assign("land_enclosure", "low")["ok"]))
	report = ResearchTurn.resolve(_state, _economy)
	assert_eq(_state.progress_of("land_enclosure"), 100)
	assert_eq(int(report["spent"]), 50)
	assert_false(_state.is_unlocked("land_enclosure"))


func test_industrial_funding_boosts_military_techs() -> void:
	_state.unlock("industrial_funding_of_research")
	_state.unlock("land_enclosure")
	assert_true(bool(_state.assign("organised_regiments", "medium")["ok"]))
	ResearchTurn.resolve(_state, _economy)
	assert_eq(_state.progress_of("organised_regiments"), 360)
	assert_eq(ResearchTurn.points_for(_state, "organised_regiments", "medium"), 360)
	assert_eq(ResearchTurn.points_for(_state, "land_enclosure", "medium"), 300)


func test_none_funding_spends_and_earns_nothing() -> void:
	assert_true(bool(_state.assign("land_enclosure", "none")["ok"]))
	var treasury: int = _economy.treasury
	var report: Dictionary = ResearchTurn.resolve(_state, _economy)
	assert_eq(int(report["spent"]), 0)
	assert_eq(_economy.treasury, treasury)
	assert_eq(_state.progress_of("land_enclosure"), 0)


func test_an_unpayable_slot_earns_nothing() -> void:
	_economy.treasury = 100
	assert_true(bool(_state.assign("land_enclosure", "medium")["ok"]))
	var report: Dictionary = ResearchTurn.resolve(_state, _economy)
	assert_false(bool((report["slots"] as Array[Dictionary])[0]["paid"]))
	assert_eq(_state.progress_of("land_enclosure"), 0)
	assert_eq(_economy.treasury, 100)
	assert_eq((report["unpaid"] as Array[String]).size(), 1)


func test_money_lending_lets_research_borrow() -> void:
	_state.unlock("money_lending")
	_economy.treasury = 100
	assert_true(bool(_state.assign("land_enclosure", "medium")["ok"]))
	ResearchTurn.resolve(_state, _economy)
	assert_eq(_economy.treasury, -50)
	assert_eq(_state.progress_of("land_enclosure"), 300)


func test_banking_extends_the_research_floor() -> void:
	_state.unlock("money_lending")
	_state.unlock("banking")
	_economy.treasury = 100
	assert_true(bool(_state.assign("land_enclosure", "maximum")["ok"]))
	ResearchTurn.resolve(_state, _economy)
	assert_eq(_economy.treasury, -900)
	assert_true(_state.is_unlocked("land_enclosure"))


func test_the_economy_turn_runs_research_after_production() -> void:
	assert_true(bool(_state.assign("land_enclosure", "medium")["ok"]))
	var report: Dictionary = EconomyTurn.resolve(
		_economy, WorldMarket.with_default_prices(), {}, 0
	)
	var research: Dictionary = report["research"]
	assert_eq(int(research["spent"]), 150)
	assert_eq(_state.progress_of("land_enclosure"), 300)
	assert_eq((research["slots"] as Array[Dictionary]).size(), 3)


func test_projection_leaves_research_untouched() -> void:
	assert_true(bool(_state.assign("land_enclosure", "medium")["ok"]))
	var treasury: int = _economy.treasury
	var report: Dictionary = EconomyTurn.project(
		_economy, WorldMarket.with_default_prices(), {}, 0
	)
	assert_eq(_economy.treasury, treasury)
	assert_eq(_state.progress_of("land_enclosure"), 0)
	assert_lt(int(report["treasury_delta"]), 0)


func test_a_researched_gathering_tech_lifts_the_extraction_cap() -> void:
	var model: MapModel = Fixture.build()
	var works := LandWorks.new()
	works.set_transport(model, Vector2i(0, 1), LandWorks.TRANSPORT_ROAD)
	works.set_transport(model, Fixture.TIMBER_TILE, LandWorks.TRANSPORT_RAIL)
	works.set_improvement(model, Fixture.TIMBER_TILE, 2)
	var capped: Dictionary = Extraction.yields(
		model, 0, -1, TechCatalog.extraction_caps({}), works, Fixture.BARE_TILE
	)
	assert_eq(capped, {"timber": 1})
	_state.unlock("saw_mill")
	var lifted: Dictionary = Extraction.yields(
		model, 0, -1, TechCatalog.extraction_caps(_state.unlocked), works, Fixture.BARE_TILE
	)
	assert_eq(lifted, {"timber": 2})
