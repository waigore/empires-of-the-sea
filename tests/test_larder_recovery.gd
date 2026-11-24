extends GdToolsTest
## The famine order (issue #1433): a court whose own fields cannot carry the
## mouths it feeds stops buying grain forever and sheds force — an empty hull
## first, then the thinnest colours — so the pool is fed and works again
## (wiki: workers-and-population § Strike workers; military-armies § Dismissing
## regiments; ships-and-naval § Ship muster and the breaker's yard;
## treasury-planner § Lock-recovery).
##
## One thin turn is a pantry, two is a famine: the streak is the phase's own dry
## run noted by the court's plan turn, and the bill is the same total the
## Consumption phase eats. Everything here is pure — one hand-built chart per
## case, no screen mount (docs/testing.md § Speed rules).

const AiFixture = preload("res://tests/ai_fixture.gd")

## A mouth the muster's own catalogue feeds at 2 a turn (RegimentCatalog).
const LEVY: String = "peasant_levies"


func _play(regiments: int) -> PlaySession:
	var world: WorldMap = AiFixture.land_world([0, 1], {0: true})
	var model: MapModel = world.region(0)
	var types: Array[String] = []
	for _index in regiments:
		types.append(LEVY)
	var home: ArmyState = ArmyState.muster(1, 0, 0, true, types, 1)
	var roster: Array[ArmyState] = [home]
	var armies := ArmyLayer.new()
	armies.model = model
	armies.next_army = 100
	armies.armies.assign(roster)
	armies.regions.set_region(0, roster)
	var play := PlaySession.new()
	play.player_faction = 0
	play.world = world
	play.model = model
	play.army_layer = armies
	play.map_seed = 1500
	play.ai = AiState.new()
	return play


## One court on a hand-built chart: `harvest` is the ration its land lands, the
## store empty (the pantry the strike has already eaten).
func _court(play: PlaySession, pool: int, harvest: int) -> MapPlayEconomyCourt:
	var economy := PlayerEconomy.starting()
	economy.workers = WorkerPool.make(pool)
	economy.stockpile = {}
	var court := MapPlayEconomyCourt.new()
	court.play = play
	court.faction = 0
	court.economy = economy
	court.overseas = {"extraction": {"grain": harvest} if harvest > 0 else {}}
	return court


func _streak(play: PlaySession, turns: int) -> void:
	for _index in turns:
		play.ai.note_strike_streak(0, true)


## The streak is the phase's own reading, and a fed larder clears it: a court
## with grain in store hears nothing, a starving one counts every turn it runs.
func test_the_note_counts_the_turns_the_pool_would_go_unfed() -> void:
	var play: PlaySession = _play(4)
	var court: MapPlayEconomyCourt = _court(play, 2, 2)

	assert_true(MapPlayLarderRecovery.note(court), "an empty pantry starves the pool")
	assert_eq(MapPlayLarderRecovery.streak(court), 1, "the first thin turn is counted")
	assert_true(MapPlayLarderRecovery.note(court), "and the second says the same")
	assert_eq(MapPlayLarderRecovery.streak(court), 2, "a famine, not a pantry")

	court.economy.stockpile = {"grain": 100}
	assert_false(MapPlayLarderRecovery.note(court), "a fed larder says nothing")
	assert_eq(MapPlayLarderRecovery.streak(court), 0, "and clears the streak")


## One thin turn is a pantry: the court buys its dinner before it sells its
## army (treasury-planner § Lock-recovery). Only the second turn sheds.
func test_one_thin_turn_sheds_nothing() -> void:
	var play: PlaySession = _play(4)
	var court: MapPlayEconomyCourt = _court(play, 2, 2)
	_streak(play, MapPlayLarderRecovery.STRIKE_TURNS - 1)

	var receipt: Dictionary = MapPlayLarderRecovery.shed(court)

	assert_false(bool(receipt["ok"]), "a thin turn files no order")
	assert_eq((receipt["lines"] as Array).size(), 0, "and says nothing")
	assert_eq(
		(play.army_layer.armies[0] as ArmyState).count(), 4,
		"the colours stay while the pantry can still carry them"
	)


## A famine sheds the mouths the harvest cannot carry, keeping one colour per
## standard, and hands the pool their peasants: four levies at two rations eat
## eight against a harvest of two, so three go and one stays.
func test_a_famine_sheds_the_mouths_the_harvest_cannot_carry() -> void:
	var play: PlaySession = _play(4)
	var court: MapPlayEconomyCourt = _court(play, 2, 2)
	_streak(play, MapPlayLarderRecovery.STRIKE_TURNS)

	var receipt: Dictionary = MapPlayLarderRecovery.shed(court)

	assert_true(bool(receipt["ok"]), "the famine order files")
	assert_eq(int(receipt["regiments"]), 3, "three colours leave, one standard keeps")
	assert_eq(int(receipt["hulls"]), 0, "no hull is broken up with none afloat")
	assert_eq(int(receipt["peasants"]), 3, "each dismissed regiment returns one peasant")
	assert_eq(
		(receipt["lines"] as Array),
		["Dismisses 3 regiments — 3 peasants return to the fields"],
		"and the court is told what left"
	)
	var home: ArmyState = play.army_layer.armies[0] as ArmyState
	assert_eq(home.count(), MapPlayLarderRecovery.KEEP_PER_STANDARD, "a standard keeps one mouth")
	assert_eq(
		court.economy.workers.count(WorkerPool.Tier.PEASANT), 5,
		"the three peasants joined the pool"
	)
	play.army_layer.free()


## The order stops when the bill fits the land: a court whose harvest already
## carries its mouths sells nothing, even with the famine streak standing.
func test_a_carried_bill_sheds_nothing() -> void:
	var play: PlaySession = _play(1)
	var court: MapPlayEconomyCourt = _court(play, 1, 12)
	_streak(play, MapPlayLarderRecovery.STRIKE_TURNS)

	var receipt: Dictionary = MapPlayLarderRecovery.shed(court)

	assert_false(bool(receipt["ok"]), "a carried bill files no order")
	assert_eq(
		(play.army_layer.armies[0] as ArmyState).count(), 1,
		"the colour stays"
	)
	play.army_layer.free()


## An empty hull goes before a colour, and a squadron keeps one afloat: four
## hulls eating eight against a harvest of none shed three, and the deck under
## a charge is never broken up (wiki: ships-and-naval § Naval transport).
func test_an_empty_hull_goes_before_a_colour() -> void:
	var play: PlaySession = _play(1)
	var court: MapPlayEconomyCourt = _court(play, 1, 0)
	var types: Dictionary = {
		"hull_a": "carrack", "hull_b": "carrack",
		"hull_c": "carrack", "hull_d": "carrack",
	}
	var fleet: FleetState = FleetState.in_port(
		0, 0, 0, ["hull_a", "hull_b", "hull_c", "hull_d"], types
	)
	var carried: FleetState = FleetState.in_port(
		1, 0, 0, ["hull_e", "hull_f"], {"hull_e": "sloop", "hull_f": "sloop"}
	)
	carried.embarked_army = 1
	var ships := ShipLayer.new()
	ships.model = play.model
	var roster: Array[FleetState] = [fleet, carried]
	ships.regions.set_region(0, roster)
	ships.fleets = roster
	play.ship_layer = ships
	_streak(play, MapPlayLarderRecovery.STRIKE_TURNS)

	var receipt: Dictionary = MapPlayLarderRecovery.shed(court)

	assert_eq(int(receipt["hulls"]), 3, "three empty hulls go first")
	assert_eq(fleet.ship_count(), MapPlayLarderRecovery.KEEP_PER_STANDARD, "a squadron keeps one afloat")
	assert_eq(carried.ship_count(), 2, "the deck under a charge keeps her hulls")
	assert_true(
		(receipt["lines"] as Array).has("Breaks up 3 hulls — 3 peasants return to the pool"),
		"and the court is told what was broken up"
	)
	assert_eq(
		(play.army_layer.armies[0] as ArmyState).count(), 1,
		"the one mouth the harvest cannot carry stays while a hull can go"
	)
	play.army_layer.free()


## A court that runs no planner, holds no ledger or sits at peace in an empty
## larder answers rather than crashing the household pass.
func test_a_court_with_nothing_to_shed_answers_empty() -> void:
	var empty: Dictionary = MapPlayLarderRecovery.shed(null)
	assert_false(bool(empty["ok"]), "no court, no order")
	assert_eq((empty["lines"] as Array).size(), 0, "and no line")

	var play: PlaySession = _play(1)
	var court: MapPlayEconomyCourt = _court(play, 1, 0)
	_streak(play, MapPlayLarderRecovery.STRIKE_TURNS)
	court.economy = null
	assert_false(bool(MapPlayLarderRecovery.shed(court)["ok"]), "no ledger, no order")
	assert_eq(MapPlayLarderRecovery.streak(null), 0, "no court reads no streak")
	assert_false(MapPlayLarderRecovery.note(null), "and notes nothing")
	play.army_layer.free()
