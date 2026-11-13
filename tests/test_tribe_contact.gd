extends GdToolsTest
## GP–Tribe first contact for rival crowns (wiki: diplomacy § GP–Tribe first
## contact; map pass: MapPlayTribeContact).

const Fixture = preload("res://tests/map_fixture.gd")

const HUMAN: int = 0
const TURN: int = 4
const NEW_WORLD: int = 1

var _rival: int = 0
var _tribe: int = 0
var _other_tribe: int = 0
var _state: DiplomacyState = null
var _screen: MapScreen = null


func before_each() -> void:
	_rival = FactionCatalog.great_power_ids()[1]
	_tribe = FactionCatalog.tribe_ids()[0]
	_other_tribe = FactionCatalog.tribe_ids()[1]
	_state = DiplomacyState.new()
	_state.initialize(TURN)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


## One New World region, one province per entry. Its baseline is unknown, so a
## court discovers a tribe province only by charting it.
func _world(owners: Array[int]) -> WorldMap:
	var model := MapModel.new()
	model.setup(maxi(owners.size(), 1), 1)
	model.region_id = FactionCatalog.NEW_WORLD
	model.region_key = FactionCatalog.REGION_KEYS[FactionCatalog.NEW_WORLD]
	for index in owners.size():
		var tiles: Array[Vector2i] = [Vector2i(index, 0)]
		var province := ProvinceState.create(
			index,
			"P%d" % index,
			tiles,
			Vector2(float(index), 0.0),
			1,
			owners[index],
			false
		)
		model.provinces.append(province)
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _charts(owners: Array[int], human_views: Dictionary = {}) -> CourtCharts:
	return _charts_over(_world(owners), human_views)


func _charts_over(world: WorldMap, human_views: Dictionary = {}) -> CourtCharts:
	var charts := CourtCharts.new()
	charts.setup(world, HUMAN, human_views)
	return charts


func _reveal(charts: CourtCharts, faction: int, province: int) -> void:
	charts.reveal_province(faction, 0, province)


# --- discovery ---------------------------------------------------------------


## A court that has charted nothing of the New World holds no Tribal court, even
## though the Tribe's provinces exist in the world.
func test_an_uncharted_tribe_is_never_contacted() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	assert_eq(TribeContact.charted_tribes(charts, _rival), [] as Array[int])
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])
	assert_false(_state.has_relation(_rival, _tribe))


## One charted province opens the relation once, `AT_PEACE` / 50 / Neutral, with
## `sinceTurn` the turn that resolved and no war flag.
func test_a_charted_province_opens_first_contact() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	var found: Array[Dictionary] = TribeContact.apply(charts, _state, HUMAN, TURN)
	assert_eq(found.size(), 1)
	assert_eq(int(found[0]["faction"]), _rival)
	assert_eq(int(found[0]["tribe"]), _tribe)
	var record: DiplomacyRelation = _state.relation(_rival, _tribe)
	assert_not_null(record)
	assert_false(record.at_war, "first contact is peace, not war")
	assert_eq(record.score, 50.0)
	assert_eq(record.level(), "Neutral")
	assert_eq(record.since_turn, TURN)
	assert_false(record.formal_alliance)


## A crown whose leader publishes the Tribe lean opens on score 60, while a crown
## with no diplomacy row still opens at the Neutral equilibrium (wiki:
## leader-bonuses § Bonus Table — Isabella).
func test_a_leader_with_the_tribe_lean_opens_first_contact_at_sixty() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	var found: Array[Dictionary] = TribeContact.apply(
		charts, _state, HUMAN, TURN, {_rival: "isabella"}
	)
	assert_eq(found.size(), 1)
	var record: DiplomacyRelation = _state.relation(_rival, _tribe)
	assert_eq(record.score, 60.0, "Spain opens friendlier than the equilibrium")
	assert_false(record.at_war)


func test_a_crown_without_the_tribe_lean_opens_at_the_equilibrium() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	TribeContact.apply(charts, _state, HUMAN, TURN, {_rival: "victoria"})
	var record: DiplomacyRelation = _state.relation(_rival, _tribe)
	assert_eq(record.score, 50.0, "research funding buys no Tribal welcome")


## The discovery is a chronicle beat of the turn that resolved, so the court's
## sheet narrates it beside the turn's other acts.
func test_the_beat_is_stamped_with_the_resolved_turn() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	TribeContact.apply(charts, _state, HUMAN, TURN)
	var beats: Array[Dictionary] = []
	for event: Dictionary in _state.events:
		if String(event.get("kind", "")) == "firstContact":
			beats.append(event)
	assert_eq(beats.size(), 1)
	assert_eq(int(beats[0]["a"]), _rival)
	assert_eq(int(beats[0]["b"]), _tribe)
	assert_eq(int(beats[0]["turn"]), TURN, "the resolved turn, not the state's clock")


## Irreversible and once only: a second pass neither re-records the beat nor
## touches a score the courts have since moved.
func test_first_contact_is_once_and_irreversible() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	TribeContact.apply(charts, _state, HUMAN, TURN)
	_state.relation(_rival, _tribe).set_score(28.0)
	var charts_after: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts_after, _rival, 2)
	assert_eq(
		TribeContact.apply(charts_after, _state, HUMAN, TURN + 1), [] as Array[Dictionary]
	)
	assert_eq(_state.relation(_rival, _tribe).score, 28.0, "the record keeps its score")
	assert_eq(_state.relation(_rival, _tribe).since_turn, TURN)
	assert_eq(_events("firstContact"), 1)


## A court with no chart at all — a fixture, or a session that never loaded a
## region — discovers nothing and writes nothing.
func test_a_court_without_a_chart_is_a_stranger() -> void:
	assert_eq(TribeContact.apply(null, _state, HUMAN, TURN), [] as Array[Dictionary])
	assert_eq(TribeContact.charted_tribes(null, _rival), [] as Array[int])
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe])
	_reveal(charts, _rival, 2)
	charts.courts[_rival][0] = null
	assert_eq(TribeContact.charted_tribes(charts, _rival), [] as Array[int])
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])


## Two provinces of one Tribe are one court, and a province no faction owns is
## nobody's: neither opens a second relation nor a phantom one.
func test_a_repeated_or_unowned_province_is_not_a_second_court() -> void:
	var before: int = _state.relations_of(_rival).size()
	var charts: CourtCharts = _charts(
		[HUMAN, _rival, _tribe, _tribe, MapModel.NO_ID]
	)
	_reveal(charts, _rival, 2)
	_reveal(charts, _rival, 3)
	_reveal(charts, _rival, 4)
	assert_eq(TribeContact.charted_tribes(charts, _rival), [_tribe] as Array[int])
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN).size(), 1)
	assert_eq(_state.relations_of(_rival).size(), before + 1, "one court, one relation")


## The turn pass guards a session that is not a playthrough at all.
func test_the_turn_pass_waits_for_diplomacy_and_a_chart() -> void:
	assert_eq(MapPlayTribeContact.resolve(null), [] as Array[Dictionary])
	var bare := PlaySession.new()
	assert_eq(MapPlayTribeContact.resolve(bare), [] as Array[Dictionary])
	bare.diplomacy = DiplomacyState.new()
	bare.diplomacy.initialize(TURN)
	assert_eq(MapPlayTribeContact.resolve(bare), [] as Array[Dictionary])


## Several charted tribes in one pass come back in id order, one relation each.
func test_each_charted_tribe_is_contacted_once() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, _tribe, _other_tribe])
	_reveal(charts, _rival, 2)
	_reveal(charts, _rival, 3)
	var found: Array[Dictionary] = TribeContact.apply(charts, _state, HUMAN, TURN)
	assert_eq(TribeContact.charted_tribes(charts, _rival), [_tribe, _other_tribe] as Array[int])
	assert_eq(found.size(), 2)
	assert_eq(int(found[0]["tribe"]), _tribe)
	assert_eq(int(found[1]["tribe"]), _other_tribe)


## A Minor Nation's province is not a Tribal court: only tribes are discovered.
func test_a_charted_minor_is_not_a_tribe() -> void:
	var charts: CourtCharts = _charts([HUMAN, _rival, FactionCatalog.minor_ids()[0]])
	_reveal(charts, _rival, 2)
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])


# --- the human court ---------------------------------------------------------


## The crown's own discovery keeps its app-layer pass and herald, so this pass
## never writes the human relation — even when the crown's grid knows the tribe.
func test_the_human_court_is_skipped() -> void:
	var world: WorldMap = _world([HUMAN, _rival, _tribe])
	var human := VisibilityModel.new()
	human.setup(world.region(0), HUMAN)
	human.reveal_province(2)
	var charts: CourtCharts = _charts_over(world, {0: human})
	assert_true(TribeContact.charted_tribes(charts, HUMAN).has(_tribe))
	assert_eq(TribeContact.apply(charts, _state, HUMAN, TURN), [] as Array[Dictionary])
	assert_false(_state.has_relation(HUMAN, _tribe))


## The full-AI observer has no human court, so every crown — the slot one
## included, whose grid is the session's own table — opens its own first contact.
func test_an_observer_contacts_every_crown() -> void:
	var world: WorldMap = _world([HUMAN, _rival, _tribe])
	var slot := VisibilityModel.new()
	slot.setup(world.region(0), HUMAN)
	slot.reveal_province(2)
	var charts: CourtCharts = _charts_over(world, {0: slot})
	for faction: int in FactionCatalog.great_power_ids():
		charts.reveal_province(faction, 0, 2)
	var found: Array[Dictionary] = TribeContact.apply(charts, _state, MapModel.NO_ID, TURN)
	assert_eq(found.size(), FactionCatalog.great_power_ids().size())
	assert_true(_state.has_relation(HUMAN, _tribe), "the observer's slot court contacts too")
	assert_eq(_events("firstContact"), FactionCatalog.great_power_ids().size())


# --- the turn pass -----------------------------------------------------------


## Closing a turn lets a rival that charted a tribe province open contact, and a
## rival that has not stays a stranger (wiki: end-of-turn pass).
func test_a_turn_close_opens_contact_from_the_rivals_own_chart() -> void:
	_screen = Fixture.attach_screen(self)
	assert_not_null(_screen.play.court_charts, "the screen charts its world")
	# The crown's region 1 is the New World; the load charts every rival too.
	_screen._cycle_region()
	var province: ProvinceState = _tribe_province(_screen.play.world)
	assert_not_null(province, "the New World holds a Tribe province")
	var rival: int = FactionCatalog.great_power_ids()[1]
	assert_false(_screen.play.diplomacy.has_relation(rival, province.owner))
	var charts: CourtCharts = _screen.play.court_charts
	charts.reveal_province(rival, NEW_WORLD, province.id)
	_close_turn(_screen.play)
	assert_true(
		_screen.play.diplomacy.has_relation(rival, province.owner),
		"the rival charted the province before the turn closed"
	)
	assert_eq(_screen.play.diplomacy.relation(rival, province.owner).score, 50.0)


func _tribe_province(world: WorldMap) -> ProvinceState:
	for index in world.region_count():
		var model: MapModel = world.region(index)
		if model == null:
			continue
		for province: ProvinceState in model.provinces:
			if FactionCatalog.type_of(province.owner) == FactionCatalog.Type.TRIBE:
				return province
	return null


## Ends the turn past every consent decision the rivals raise on the way.
func _close_turn(play: PlaySession) -> void:
	var before: int = play.turn
	MapPlayTurn.end_turn(play)
	var guard: int = 0
	while play.turn == before and guard < 12:
		guard += 1
		if CallToArms.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_call(play, false)
		elif Intervention.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_intervention(play, Intervention.KIND_NOTHING)
		elif DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
			MapPlayTurn.answer_offer(play, false)
		else:
			break
	assert_gt(play.turn, before, "the turn closed")


func _events(kind: String) -> int:
	var total: int = 0
	for event: Dictionary in _state.events:
		if String(event.get("kind", "")) == kind:
			total += 1
	return total
