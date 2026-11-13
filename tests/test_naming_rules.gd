extends GdToolsTest
## One boot for naming, order-of-battle readings and battle settlement (wiki:
## naming; fog-and-exploration § Order Visibility; combat § Outcomes). Merged
## from test_name_roster, test_general_names, test_oob_readings and
## test_battle_settlement so coverage pays one instrumentation pass.

# --- test_name_roster ---

## One deterministic christening core for every named thing (wiki: naming,
## DR-20261111-07/18, DR-20261112-03): the hull, regiment and general rosters all
## draw their pick, their repeat numbering and their FNV-1a digest from
## NameRoster, so a saved campaign speaks the same names on every load and the
## three rosters can never drift apart. Pure arithmetic: pools in, titles out.

const POOL: Array[String] = ["Revenge", "Sovereign", "Vanguard"]


func test_a_pick_comes_from_the_pool_and_never_repeats() -> void:
	var taken: Array[String] = []
	for step in POOL.size():
		var name: String = NameRoster.pick(POOL, "%d" % step, taken, "Unnamed")
		assert_true(POOL.has(name), "step %d picked '%s' from its pool" % [step, name])
		assert_false(taken.has(name), "'%s' is worn twice" % name)
		taken.append(name)


func test_the_same_key_always_christens_the_same_name() -> void:
	var first: String = NameRoster.pick(POOL, "0:0:ship_1", [], "Unnamed")
	var second: String = NameRoster.pick(POOL, "0:0:ship_1", [], "Unnamed")

	assert_eq(first, second, "a reload draws the same title")
	assert_false(NameRoster.pick(POOL, "0:0:ship_2", [], "Unnamed").is_empty())


func test_a_spent_pool_numbers_its_repeats() -> void:
	var taken: Array[String] = POOL.duplicate()
	var numbered: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")

	assert_true(numbered.ends_with(" II"), "the fourth hull is numbered, got '%s'" % numbered)
	assert_false(taken.has(numbered), "the numbered pick is still free")


func test_a_pool_past_its_last_ordinal_repeats_its_last_title() -> void:
	var taken: Array[String] = POOL.duplicate()
	for _cycle in NameRoster.ORDINALS.size():
		var name: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")
		if not taken.has(name):
			taken.append(name)
	var last: String = NameRoster.pick(POOL, "0:0:ship_1", taken, "Unnamed")

	assert_true(taken.has(last), "an exhausted numbering falls back to a taken title")
	assert_true(last.ends_with(" VIII"), "the last ordinal is the ceiling, got '%s'" % last)


func test_an_empty_pool_falls_back_to_the_callers_word() -> void:
	var empty: Array[String] = []

	assert_eq(NameRoster.pick(empty, "0:0:ship_1", [], "Unnamed"), "Unnamed")
	assert_eq(NameRoster.pick(empty, "0:general_1", [], "Commander"), "Commander")


func test_a_crown_with_no_pool_reads_the_generic_one() -> void:
	var pools: Dictionary = {0: ["Revenge"]}
	var generic: Array[String] = ["Providence"]

	assert_eq(NameRoster.pool_of(pools, generic, 0), ["Revenge"])
	assert_eq(NameRoster.pool_of(pools, generic, 9), generic, "an unknown crown is generic")


func test_taken_names_reads_the_store_and_skips_the_new_instance() -> void:
	var store: Dictionary = {"ship_1": "Revenge", "ship_2": "", "ship_3": "Vanguard"}

	assert_eq(
		NameRoster.taken_names(["ship_1", "ship_2", "ship_3"], store, "ship_1"),
		["Vanguard"],
		"the hull being christened and the unnamed one are left out"
	)
	assert_eq(NameRoster.taken_names([], {}, ""), [], "an empty roster names nothing")


func test_a_saved_title_map_reads_json_keys_as_strings() -> void:
	assert_eq(
		NameRoster.map_from({"1": "Revenge"}),
		{"1": "Revenge"},
		"a string-keyed map survives"
	)
	assert_eq(
		NameRoster.map_from({1: "Vanguard"}),
		{"1": "Vanguard"},
		"a numeric key is read back as the string a save writes"
	)
	assert_eq(NameRoster.map_from([1, 2]), {}, "a malformed map reads empty")
	assert_eq(NameRoster.map_from(null), {}, "a missing map reads empty")


## A JSON round-trip turns every count into a float; the reader casts it back, so
## a restored regiment's condition and record compare equal to what was saved.
func test_a_saved_number_map_reads_json_values_as_ints() -> void:
	var json: String = JSON.stringify({"unit_1": 3, "unit_2": 0})
	var raw: Variant = JSON.parse_string(json)

	assert_eq(
		NameRoster.numbers_from(raw),
		{"unit_1": 3, "unit_2": 0},
		"counts survive a JSON round-trip as ints"
	)
	assert_eq(NameRoster.numbers_from({1: "2"}), {"1": 2}, "a numeric key and a text value")
	assert_eq(NameRoster.numbers_from("nonsense"), {}, "malformed reads empty")
	assert_eq(NameRoster.numbers_from(null), {}, "a missing map reads empty")


func test_the_digest_is_the_fn_1a_save_contract() -> void:
	assert_eq(NameRoster.stable_hash("0:0:ship_1"), 3815455475)
	assert_eq(NameRoster.stable_hash("0:general_1"), 2632187469)
	assert_eq(NameRoster.stable_hash("0:1:unit_101"), 1682817625)
	assert_false(
		NameRoster.stable_hash("0:0:ship_1") == NameRoster.stable_hash("0:0:ship_2"),
		"a different instance draws a different start"
	)


func test_every_roster_numbers_repeats_the_same_way() -> void:
	var hulls: Array[String] = ShipNames.pool_for(0).duplicate()
	var regiments: Array[String] = RegimentNames.pool_for(0).duplicate()
	var generals: Array[String] = GeneralNames.pool_for(0).duplicate()

	assert_true(ShipNames.mint(0, 0, "ship_1", hulls).ends_with(" II"))
	assert_true(RegimentNames.mint(0, 0, "unit_1", regiments).ends_with(" II"))
	assert_true(GeneralNames.mint(0, "general_1", generals).ends_with(" II"))
# --- test_general_names ---

## Every commander bears a name (wiki: naming § General names;
## DR-20261112-03): a crown christens its generals from its own period pool, no
## two of them share a name, a saved roster keeps its names, an old save is
## christened on load by the same arithmetic, and the dossier names each general
## with the medals he carries.

const SPAIN: int = 0
const UNKNOWN: int = 9
const CivilianFixture = preload("res://tests/civilian_fixture.gd")


func test_a_new_roster_names_its_generals_from_the_crown_pool() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {})

	for general_id: String in roster.ids(SPAIN):
		var christened: String = roster.name_of(SPAIN, general_id)
		assert_false(christened.is_empty(), "a general is never anonymous")
		assert_true(
			GeneralNames.pool_for(SPAIN).has(christened),
			"Spain christens from its own pool, got '%s'" % christened
		)


func test_a_crown_with_no_pool_still_names_its_generals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(UNKNOWN, {})

	assert_true(GeneralNames.GENERIC.has(roster.name_of(UNKNOWN, "general_1")))


func test_no_crown_wears_the_same_name_twice() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {"nationalism": true})
	assert_eq(roster.count(SPAIN), 4, "the cap raises the pool to four")

	var borne: Array[String] = []
	for general_id: String in roster.ids(SPAIN):
		var christened: String = roster.name_of(SPAIN, general_id)
		assert_false(borne.has(christened), "'%s' is worn twice" % christened)
		borne.append(christened)


func test_the_same_crown_and_id_always_christen_the_same_name() -> void:
	var first := GeneralRoster.new()
	first.sync(SPAIN, {"nationalism": true})
	var second := GeneralRoster.new()
	second.sync(SPAIN, {"nationalism": true})

	assert_eq(first.names(SPAIN), second.names(SPAIN), "seeded, not drawn")


func test_a_full_pool_numbers_its_repeats() -> void:
	var taken: Array[String] = GeneralNames.pool_for(SPAIN).duplicate()
	var numbered: String = GeneralNames.mint(SPAIN, "general_1", taken)

	assert_true(numbered.ends_with(" II"), "an eleventh commander is numbered, got '%s'" % numbered)
	assert_false(taken.has(numbered), "the numbered pick is still free")


func test_a_saved_roster_keeps_its_names() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {"organised_regiments": true})
	roster.award(SPAIN, "general_2")

	var restored: GeneralRoster = GeneralRoster.from_dict(roster.to_dict())

	assert_eq(restored.names(SPAIN), roster.names(SPAIN), "names travel with the save")
	assert_eq(restored.medals(SPAIN, "general_2"), 1, "medals still travel")


func test_an_old_save_is_christened_on_load() -> void:
	# A save written before names existed: ids and medals only.
	var restored: GeneralRoster = GeneralRoster.from_dict({
		"pools": {str(SPAIN): [{"id": "general_1", "medals": 2}]}
	})
	var fresh := GeneralRoster.new()
	fresh.sync(SPAIN, {})

	assert_false(restored.name_of(SPAIN, "general_1").is_empty(), "nothing is anonymous")
	assert_eq(
		restored.name_of(SPAIN, "general_1"),
		fresh.name_of(SPAIN, "general_1"),
		"the same arithmetic christens a legacy save"
	)
	assert_eq(restored.medals(SPAIN, "general_1"), 2, "the record survives the naming")


func test_the_despatch_names_the_commander() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {})

	assert_eq(
		roster.label(SPAIN, "general_1"),
		roster.name_of(SPAIN, "general_1"),
		"a medal is credited to a man, not a rank"
	)
	assert_eq(roster.label(SPAIN, "general_9"), "", "an unknown commander names nothing")


func test_the_dossier_block_names_every_general_and_his_medals() -> void:
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {"organised_regiments": true})
	roster.award(SPAIN, "general_1")

	var block: String = roster.line(SPAIN)

	for general_id: String in roster.ids(SPAIN):
		assert_true(
			block.contains(roster.name_of(SPAIN, general_id)),
			"the block names every commander"
		)
	assert_true(block.contains("%s (1 medal)" % roster.name_of(SPAIN, "general_1")))
	assert_true(block.contains("%s (0 medals)" % roster.name_of(SPAIN, "general_2")))
	assert_true(block.contains("+1 line"), "the block says what a medal buys")
	assert_true(block.contains("+5% morale"))
	assert_true(block.contains("+10 initiative"))


func test_a_minor_nation_dossier_carries_no_commanders() -> void:
	var layer := ArmyLayer.new()
	var army := ArmyState.muster(1, 6, 2, false, ["pikemen"], 1)

	assert_eq(layer.command_text(army), "", "a Minor Nation holds no generals")
	layer.free()


func test_the_dossier_shows_the_commanders_under_their_medallion() -> void:
	var model: MapModel = CivilianFixture.build()
	var army := ArmyState.muster(1, SPAIN, 0, false, ["pikemen"], 1)
	var roster := GeneralRoster.new()
	roster.sync(SPAIN, {})
	var panel := ArmyPanel.new()
	add_child(panel)

	panel.refresh(model, army, true, false, roster.line(SPAIN), [], "", "balanced")

	assert_true(panel._command_row.visible, "the block shows for the crown's army")
	assert_true(
		String(panel._command.text).contains(roster.name_of(SPAIN, "general_1")),
		"the block names the commander"
	)
	assert_true(
		panel._command.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART,
		"the block wraps at a phone sheet instead of clipping"
	)
	assert_true(
		String(panel._command.text).contains("\n"),
		"the medal's worth sits on its own line"
	)
	assert_not_null(panel._command_icon.texture, "the commander has his own medallion")
	panel.free()
# --- test_oob_readings ---

## Order-of-battle readings (wiki: fog-and-exploration § Explorer vs Spy,
## § Order Visibility Requirements; military-armies § Docket; DR-20261112-09).
##
## A court reads another court's garrison and hulls only across ground and water
## its own chart holds, so a rival plans against what it has seen — never the
## published truth of a colony it has not reached.

const AiFixture = preload("res://tests/ai_fixture.gd")

const RIVAL: int = 1
const OTHER: int = 2
## Province 0 is OTHER's colony; province 1 is RIVAL's; province 2 is unclaimed
## wilds. Sea zone 0 runs under both coasts, so RIVAL charts it at setup; zone 1
## is open water, unknown.
const FOREIGN_PROVINCE: int = 0
const OWN_PROVINCE: int = 1
const WILDS_PROVINCE: int = 2
const HOME_ZONE: int = 0
const OPEN_ZONE: int = 1


## A New World region (every tile unknown at setup) with two colonies, a strip of
## wilds and two sea zones. Six tiles wide, three tall: land on row 0, water below.
func _world() -> WorldMap:
	var model := MapModel.new()
	model.setup(6, 3)
	model.region_id = FactionCatalog.NEW_WORLD
	model.faction_ids = [RIVAL, OTHER]
	for x in 6:
		model.terrain[model.index_of(x, 0)] = MapModel.Terrain.PLAINS
	for zone in 2:
		var tiles: Array[Vector2i] = []
		for x in 6:
			var tile := Vector2i(x, zone + 1)
			tiles.append(tile)
			model.sea_zone[model.index_of(tile.x, tile.y)] = zone
		model.sea_zones.append(
			SeaZoneState.create(zone, "Z%d" % zone, tiles, Vector2.ZERO, tiles.size())
		)
	_add_province(model, FOREIGN_PROVINCE, [Vector2i(0, 0), Vector2i(1, 0)], OTHER)
	_add_province(model, OWN_PROVINCE, [Vector2i(2, 0), Vector2i(3, 0)], RIVAL)
	_add_province(
		model, WILDS_PROVINCE, [Vector2i(4, 0), Vector2i(5, 0)], MapModel.NO_ID
	)
	var world := WorldMap.new()
	world.add_region(model)
	return world


func _add_province(model: MapModel, id: int, tiles: Array[Vector2i], owner: int) -> void:
	var province := ProvinceState.create(
		id, "P%d" % id, tiles, Vector2(tiles[0].x, 0.0), tiles.size(), owner, false
	)
	for tile: Vector2i in tiles:
		model.province[model.index_of(tile.x, tile.y)] = id
	model.provinces.append(province)


## Charts cut from the world; the human court (0) keeps an empty grid here.
func _charts(world: WorldMap) -> CourtCharts:
	var charts := CourtCharts.new()
	charts.setup(world, FactionCatalog.PLAYER_FACTION, {})
	return charts


func _army(id: int, owner: int, province: int, regiments: int = 3) -> ArmyState:
	var types: Array[String] = []
	for index in regiments:
		types.append("peasant_levies")
	return ArmyState.muster(id, owner, province, false, types, 1)


## A squadron of the rival subject, `hulls` strong, in `zone` or in port.
func _sea(id: int, zone: int, hulls: int) -> FleetState:
	var names: Array[String] = []
	for index in hulls:
		names.append("hull_%d_%d" % [id, index])
	return FleetState.at_sea(id, OTHER, zone, names, {})


func _port(id: int, province: int, hulls: int) -> FleetState:
	var names: Array[String] = []
	for index in hulls:
		names.append("hull_%d_%d" % [id, index])
	return FleetState.in_port(id, OTHER, province, names, {})


func _armies(roster: Array) -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(0, roster)
	return table


func _fleets(roster: Array) -> MapRegionTable:
	var table := MapRegionTable.new()
	table.set_region(0, roster)
	return table


func _readings(
	charts: CourtCharts, armies: MapRegionTable, fleets: MapRegionTable
) -> Dictionary:
	return OobReadings.by_court(charts, armies, fleets, [RIVAL, OTHER])


## Nothing seen: both dockets start at zero for every court.
func test_a_charted_court_starts_out_seeing_nothing() -> void:
	var readings: Dictionary = _readings(_charts(_world()), _armies([]), _fleets([]))
	assert_eq(int(readings[RIVAL]["regiments"].get(OTHER, 0)), 0)
	assert_eq(int(readings[RIVAL]["ships"].get(OTHER, 0)), 0)
	assert_true(readings.has(OTHER), "every court carries its own docket")


## A court commands its own standard wherever it stands — even on ground its own
## chart has not reached — and no other court counts it there.
func test_a_court_always_counts_its_own_standard() -> void:
	var army: ArmyState = _army(1, RIVAL, WILDS_PROVINCE)
	var readings: Dictionary = _readings(_charts(_world()), _armies([army]), _fleets([]))
	assert_eq(int(readings[RIVAL]["regiments"][RIVAL]), 3, "its own men are its own")
	assert_eq(int(readings[RIVAL]["regiments"].get(OTHER, 0)), 0, "no foreign men seen")
	assert_eq(
		int(readings[OTHER]["regiments"].get(RIVAL, 0)), 0,
		"the wilds are unknown to the other court"
	)


## Ownership is sight: an army on a court's own ground is that court's to count
## (wiki: fog-and-exploration § New World arrival).
func test_an_army_on_owned_ground_is_seen() -> void:
	var army: ArmyState = _army(1, RIVAL, FOREIGN_PROVINCE)
	var readings: Dictionary = _readings(_charts(_world()), _armies([army]), _fleets([]))
	assert_eq(int(readings[OTHER]["regiments"][RIVAL]), 3, "its own colony shows the enemy")


## A garrison in a colony the reader has not charted is invisible; exploring the
## province reveals it (wiki: fog-and-exploration § Visibility Levels).
func test_an_uncharted_colony_hides_its_garrison() -> void:
	var charts: CourtCharts = _charts(_world())
	var army: ArmyState = _army(1, OTHER, FOREIGN_PROVINCE)
	var armies: MapRegionTable = _armies([army])
	var fleets: MapRegionTable = _fleets([])
	assert_eq(int(_readings(charts, armies, fleets)[RIVAL]["regiments"].get(OTHER, 0)), 0)
	charts.model_for(RIVAL, 0).reveal_province(FOREIGN_PROVINCE)
	assert_eq(
		int(_readings(charts, armies, fleets)[RIVAL]["regiments"][OTHER]), 3,
		"the explored province shows its garrison"
	)


## A squadron at sea is read in charted water only; open ocean stays blind until
## a ship enters it (wiki: fog-and-exploration § Distant sea zone fog).
func test_an_uncharted_sea_zone_hides_a_squadron() -> void:
	var charts: CourtCharts = _charts(_world())
	var armies: MapRegionTable = _armies([])
	var open: MapRegionTable = _fleets([_sea(1, OPEN_ZONE, 2)])
	assert_eq(int(_readings(charts, armies, open)[RIVAL]["ships"].get(OTHER, 0)), 0)
	charts.model_for(RIVAL, 0).reveal_sea_zone(OPEN_ZONE)
	assert_eq(
		int(_readings(charts, armies, open)[RIVAL]["ships"][OTHER]), 2,
		"the charted zone shows its hulls"
	)
	assert_eq(
		int(_readings(charts, armies, _fleets([_sea(2, HOME_ZONE, 1)]))[RIVAL]["ships"][OTHER]),
		1,
		"the home coast is charted from setup"
	)


## A squadron in port hides with its port; a court's own harbour is always its
## own business.
func test_a_port_hides_its_squadron_until_the_port_is_charted() -> void:
	var charts: CourtCharts = _charts(_world())
	var armies: MapRegionTable = _armies([])
	var fleets: MapRegionTable = _fleets([_port(1, FOREIGN_PROVINCE, 1)])
	assert_eq(int(_readings(charts, armies, fleets)[RIVAL]["ships"].get(OTHER, 0)), 0)
	assert_eq(
		int(_readings(charts, armies, fleets)[OTHER]["ships"][OTHER]), 1,
		"its own port is its own business"
	)
	charts.model_for(RIVAL, 0).reveal_province(FOREIGN_PROVINCE)
	assert_eq(int(_readings(charts, armies, fleets)[RIVAL]["ships"][OTHER]), 1)


## Regiments aboard a squadron are read wherever the squadron is seen.
func test_an_embarked_regiment_rides_with_its_squadron() -> void:
	var charts: CourtCharts = _charts(_world())
	var army: ArmyState = _army(1, OTHER, MapModel.NO_ID)
	army.embarked_fleet = 5
	var armies: MapRegionTable = _armies([army])
	assert_eq(
		int(_readings(charts, armies, _fleets([_sea(5, OPEN_ZONE, 1)]))[RIVAL]["regiments"]
			.get(OTHER, 0)),
		0,
		"the squadron is in open water"
	)
	assert_eq(
		int(_readings(charts, armies, _fleets([_sea(5, HOME_ZONE, 1)]))[RIVAL]["regiments"][OTHER]),
		3,
		"the charted water shows the transport and its men"
	)


## A court with no chart at all (a fixture, or a world never charted) reads the
## published docket, exactly as CourtCharts documents for its own lookups.
func test_a_court_without_a_chart_reads_the_published_docket() -> void:
	var army: ArmyState = _army(1, OTHER, FOREIGN_PROVINCE)
	var readings: Dictionary = _readings(
		null, _armies([army]), _fleets([_sea(1, OPEN_ZONE, 1)])
	)
	assert_eq(int(readings[RIVAL]["regiments"][OTHER]), 3)
	assert_eq(int(readings[RIVAL]["ships"][OTHER]), 1)


## The turn pass hands each rival its own charted docket, so war desire is
## scored against what that court has seen (DR-20261112-09).
func test_the_turn_reads_each_court_its_own_reading() -> void:
	var world: WorldMap = AiFixture.world([2, 2, 1])
	var published: Dictionary = _turn(world, {
		"regiments": {RIVAL: 10, OTHER: 40}, "ships": {},
	})
	var charted: Dictionary = _turn(world, {
		"regiments": {RIVAL: 10, OTHER: 40},
		"ships": {},
		"readings": {
			RIVAL: {"regiments": {RIVAL: 10}, "ships": {}},
			OTHER: {"regiments": {OTHER: 40}, "ships": {}},
		},
	})
	assert_eq(
		_factor(published, RIVAL, OTHER, "relative_power"), -25,
		"the published docket reads the other court as far stronger"
	)
	assert_eq(
		_factor(charted, RIVAL, OTHER, "relative_power"), 5,
		"the reading has seen no garrison across the water, so the court looks even"
	)
	assert_eq(
		_factor(charted, OTHER, RIVAL, "relative_power"), 30,
		"the court holding the 40 regiments still reads itself strong"
	)


## The session adapter builds those readings from the charts and the layers; a
## session without them hands the caller nothing and keeps the published docket.
func test_the_map_phase_reads_the_charts_and_the_layers() -> void:
	assert_true(
		MapPlayCourtFog.oob_readings(PlaySession.new()).is_empty(),
		"no charts, no readings"
	)
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = FactionCatalog.PLAYER_FACTION
	play.court_charts = _charts(play.world)
	assert_true(
		MapPlayCourtFog.oob_readings(play).is_empty(), "charts but no layers, no readings"
	)
	var armies := ArmyLayer.new()
	add_child(armies)
	var roster: Array[ArmyState] = [_army(1, OTHER, FOREIGN_PROVINCE)]
	armies.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	add_child(ships)
	play.army_layer = armies
	play.ship_layer = ships
	var readings: Dictionary = MapPlayCourtFog.oob_readings(play)
	assert_eq(
		int(readings[RIVAL]["regiments"].get(OTHER, 0)), 0,
		"the colony is uncharted"
	)
	assert_eq(int(readings[OTHER]["regiments"][OTHER]), 3, "its own men are its own")


## The diplomacy phase hands the turn its readings: a rival that has not charted
## its neighbour's colony plans against a smaller court than it really is.
func test_the_diplomacy_phase_scores_the_reading() -> void:
	var play := PlaySession.new()
	play.world = _world()
	play.player_faction = FactionCatalog.PLAYER_FACTION
	play.court_charts = _charts(play.world)
	play.map_seed = 1500
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.reset(RIVAL)
	play.diplomacy.ensure_relation(RIVAL, OTHER, 1)
	var armies := ArmyLayer.new()
	add_child(armies)
	var roster: Array[ArmyState] = [_army(1, OTHER, FOREIGN_PROVINCE)]
	armies.regions.set_region(0, roster)
	var ships := ShipLayer.new()
	add_child(ships)
	play.army_layer = armies
	play.ship_layer = ships
	MapPlayDiplomacyAi.run(play)
	assert_eq(play.ai_trace.size(), 5, "every rival court took its turn")
	assert_eq(
		_factor({"trace": play.ai_trace}, RIVAL, OTHER, "relative_power"), 5,
		"a garrison across uncharted water is not counted against the attack"
	)


# --- helpers -----------------------------------------------------------------


func _turn(world: WorldMap, context: Dictionary) -> Dictionary:
	var state := DiplomacyState.new()
	state.reset(RIVAL)
	state.ensure_relation(RIVAL, OTHER, 1)
	return AiTurn.run(
		state, world, AiState.new(), 1, FactionCatalog.PLAYER_FACTION, 1500, context
	)


## One candidate's war-desire factor for a (court, target) pair.
func _factor(run: Dictionary, faction: int, target: int, key: String) -> int:
	for record: Dictionary in run["trace"]:
		if int(record["faction"]) != faction:
			continue
		for entry: Dictionary in record["candidates"]:
			if int(entry["target"]) == target:
				return int((entry["factors"] as Dictionary).get(key, 0))
	return -999
# --- test_battle_settlement ---

## The one settlement pipeline auto-resolve and Quick Battle share: the report
## fields, the province, the medal and the aftermath (wiki: combat § Outcomes;
## quick-battle § Outcome and integration; REQ-P2-03, REQ-P3-01, REQ-P3-04).

const Fixture = preload("res://tests/army_fixture.gd")


func _mods(medals: int = 0, fort: int = 0) -> Dictionary:
	return {"medals": medals, "fort": fort}


func _report(
	model: MapModel, outcome: int, attacker_medals: int = 0, defender_medals: int = 0
) -> Dictionary:
	return BattleSettlement.report_skeleton(
		model, 2, 0, 1, outcome,
		[] as Array[String], [] as Array[String],
		_mods(attacker_medals), _mods(defender_medals)
	)


func test_the_skeleton_carries_the_fields_every_battle_prints() -> void:
	var model := Fixture.build()
	var province: ProvinceState = model.get_province(2)
	province.fort_level = 2
	province.hospital_level = 1
	var atk_lost: Array[String] = ["a1"]
	var def_lost: Array[String] = []
	var report: Dictionary = BattleSettlement.report_skeleton(
		model, 2, 0, 1, ArmyCombat.Outcome.STALEMATE, atk_lost, def_lost,
		_mods(2), _mods(1, 2)
	)
	assert_eq(int(report["province"]), 2)
	assert_eq(int(report["attacker"]), 0)
	assert_eq(int(report["defender"]), 1)
	assert_eq(int(report["outcome"]), ArmyCombat.Outcome.STALEMATE)
	assert_eq(report["attacker_lost"], atk_lost)
	assert_eq(report["defender_lost"], def_lost)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["garrison"]), 0)
	assert_eq(String(report["recovered_type"]), "")
	assert_eq(int(report["attacker_medals"]), 2)
	assert_eq(int(report["defender_medals"]), 1)
	assert_eq(String(report["battle_mode"]), "siege")
	assert_eq(int(report["fort_level"]), 2)
	assert_eq(int(report["hospital_level"]), 1)
	assert_eq(String(report["medal_gain"]), "")
	assert_eq(int(report["medal_owner"]), -1)


func test_a_victory_flips_the_province_and_decorates_the_attacker() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 0, "the victor holds the province")
	assert_true(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 1)
	assert_eq(int(report["defender_chevrons"]), 0)
	assert_eq(int(report["attacker_mauled"]), 0)


func test_a_defeat_keeps_the_province_and_decorates_the_defender() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["guards"])
	var attacking := Fixture.army(2, 0, 2, ["peasant_levies"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.DEFENDER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 0)
	assert_eq(int(report["defender_chevrons"]), 1)


## An advantage holds the field but never hands over the province
## (wiki: quick-battle § Outcome and integration).
func test_an_advantage_advances_the_attacker_without_the_province() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_ADVANTAGE)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 1)
	assert_eq(int(report["defender_chevrons"]), 0)


func test_a_mutual_annihilation_raises_a_garrison_when_a_second_attacker_waits() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.MUTUAL_ANNIHILATION)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, true, defending.count()
	)

	assert_eq(int(report["garrison"]), 1)
	assert_eq(
		String(report["recovered_type"]),
		RegimentCatalog.garrison_type_for(ArmyGarrison.GREAT_POWER_ERA)
	)
	assert_eq(armies.size(), 3, "the reformed garrison joins the field")


func test_a_mutual_annihilation_with_no_second_attacker_leaves_no_garrison() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.MUTUAL_ANNIHILATION)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, defending.count()
	)

	assert_eq(int(report["garrison"]), 0)
	assert_eq(String(report["recovered_type"]), "")
	assert_eq(armies.size(), 2)


func test_a_stalemate_settles_no_holder_and_no_chevrons() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var report: Dictionary = _report(model, ArmyCombat.Outcome.STALEMATE)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		{}, false, 1
	)

	assert_eq(model.province_owner(2), 1)
	assert_false(bool(report["captured"]))
	assert_eq(int(report["attacker_chevrons"]), 0)
	assert_eq(int(report["defender_chevrons"]), 0)
	assert_eq(int(report["garrison"]), 0)


## A medal is the commander's, not the side's: the settlement asks
## [ArmyCommand] exactly as auto-resolve did before the split.
func test_a_winning_commander_takes_the_medal() -> void:
	var model := Fixture.build()
	var defending := Fixture.army(1, 1, 2, ["peasant_levies"])
	var attacking := Fixture.army(2, 0, 2, ["guards"])
	var armies: Array[ArmyState] = [defending, attacking]
	var roster := GeneralRoster.new()
	roster.pool(0)
	var context: Dictionary = {
		"roster": roster,
		"army_general": {attacking.id: "general_1"},
	}
	var report: Dictionary = _report(model, ArmyCombat.Outcome.ATTACKER_VICTORY)

	BattleSettlement.settle(
		model, armies, report, [attacking], [defending], attacking, defending,
		context, false, 1
	)

	assert_eq(String(report["medal_gain"]), "general_1")
	assert_eq(int(report["medal_owner"]), 0)
	assert_eq(roster.medals(0, "general_1"), 1)
