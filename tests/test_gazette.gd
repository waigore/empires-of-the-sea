# gdlint: disable=max-public-methods
extends GdToolsTest
## The Gazette's rules: the watchlist and its archive, the three classes and
## Also includes gazette plate (one Godot boot).
## their order, the imperial prose, and the PlayerView masking (wiki:
## the-gazette; DR-20261110-14). Pure rules — no map screen, no HUD.

const Fixture = preload("res://tests/map_fixture.gd")

const VIEWER: int = 0
const ENGLAND: int = 1
const FRANCE: int = 2
const AZTEC: int = 9
const TLAXCALA: int = 10
const GENOA: int = 6

## Cached two-region world; only province and zone names are read from it.
var world: WorldMap = null


func before_all() -> void:
	world = Fixture.world()


func after_all() -> void:
	world = null


func after_each() -> void:
	_teardown_gazette_plate()


# --- watchlist ---------------------------------------------------------------


func test_the_watchlist_seeds_from_the_bonds_the_campaign_opens_with() -> void:
	var state: DiplomacyState = _state(2)
	var gazette := GazetteState.new()
	GazetteState.seed(gazette, state, VIEWER)
	assert_true(gazette.is_watched(ENGLAND), "an embassy puts a court on the list")
	assert_true(gazette.is_watched(FRANCE))
	assert_false(gazette.is_watched(AZTEC), "a people the crown has not met is not")


func test_a_removal_sticks_even_when_the_bond_remains() -> void:
	var state: DiplomacyState = _state(2)
	var gazette := GazetteState.new()
	GazetteState.seed(gazette, state, VIEWER)
	gazette.set_watched(ENGLAND, false)
	GazetteState.seed(gazette, state, VIEWER)
	assert_false(gazette.is_watched(ENGLAND), "seed never undoes a player's removal")


func test_a_bond_formed_later_reseeds_the_court() -> void:
	var state: DiplomacyState = _state(2)
	var gazette := GazetteState.new()
	GazetteState.seed(gazette, state, VIEWER)
	gazette.set_watched(FRANCE, false)
	state.set_overture(VIEWER, AZTEC, DiplomacyCatalog.STAGE_NAP)
	GazetteState.seed(gazette, state, VIEWER)
	assert_true(gazette.is_watched(AZTEC), "a new pact puts the court on the list")
	assert_false(gazette.is_watched(FRANCE), "the struck-off court stays off")


func test_the_watchlist_and_the_archive_round_trip_through_a_save() -> void:
	var gazette := GazetteState.new()
	gazette.set_watched(ENGLAND, true)
	gazette.set_watched(FRANCE, false)
	gazette.append(_sheet(2, "one"))
	gazette.append(_sheet(3, "two"))
	var restored: GazetteState = GazetteState.from_dict(gazette.to_dict())
	assert_true(restored.is_watched(ENGLAND))
	assert_false(restored.is_watched(FRANCE), "a removal survives the round trip")
	assert_eq(restored.sheets.size(), 2)
	assert_eq(restored.newest_turn(), 3)
	assert_eq(restored.history()[0]["turn"], 3, "history reads newest first")


# --- classification ----------------------------------------------------------


func test_a_war_between_other_great_powers_is_world_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", ENGLAND, FRANCE)
	var items: Array = _items(state, [])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)
	assert_true(String(items[0]["text"]).contains("gauntlet"), "thick imperial voice")


func test_the_crowns_own_war_is_our_court_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", VIEWER, FRANCE)
	var items: Array = _items(state, [])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains("Our crown"))


## A watched court's war is still a public epoch fact, and the classes are
## exclusive in order: World outranks Courts of interest (wiki: the-gazette
## § Classes).
func test_a_watched_courts_war_is_still_world_news() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", ENGLAND, FRANCE)
	var items: Array = _items(state, [ENGLAND])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)


## A watched court's quieter act — a league, a finished study — is what the
## interest page is for.
func test_a_watched_courts_league_is_news_of_interest() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("allianceFormed", ENGLAND, FRANCE)
	var items: Array = _items(state, [ENGLAND])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.INTEREST)


func test_a_strangers_private_war_stays_out_of_the_sheet() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", AZTEC, TLAXCALA)
	var items: Array = _items(state, [])
	assert_eq(items.size(), 0, "an unmet court cannot be named, so it is not printed")


func test_display_order_is_world_then_our_court_then_interest() -> void:
	var state: DiplomacyState = _state(3)
	state.record_event("warDeclared", ENGLAND, FRANCE)  # World
	state.record_event("peaceMade", VIEWER, FRANCE)  # Our court
	state.record_event("allianceFormed", ENGLAND, FRANCE)  # Interest, when watched
	var classes: Array[int] = []
	for item: Variant in _items(state, [ENGLAND]):
		classes.append(int((item as Dictionary)["class"]))
	assert_eq(classes, [Gazette.Class.WORLD, Gazette.Class.COURT, Gazette.Class.INTEREST])


func test_an_empty_turn_is_still_archived_so_the_history_has_no_gaps() -> void:
	var sheet: Dictionary = Gazette.collect(
		VIEWER, 4, world, _state(4), [], [], [], [], {}, 0, []
	)
	assert_true(Gazette.is_empty(sheet), "nothing to print")
	var gazette := GazetteState.new()
	gazette.append(sheet)
	assert_eq(gazette.sheets.size(), 1, "the archive still takes the turn")
	assert_true(gazette.has_sheet(4))


# --- battles, studies, treasury, raids ---------------------------------------


func test_a_capture_prints_the_province_and_the_regiments_lost() -> void:
	var province: int = _province()
	var battle: Dictionary = {
		"attacker": VIEWER,
		"defender": FRANCE,
		"region": 0,
		"province": province,
		"outcome": ArmyCombat.Outcome.CAPTURE,
		"captured": true,
		"defender_lost": [1, 2],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	var text: String = String(items[0]["text"])
	assert_true(text.contains(_province_name(province)))
	assert_true(text.contains("2 regiments"))


func test_a_battle_between_unwatched_courts_is_never_reported() -> void:
	var battle: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"defender_lost": [1],
	}
	assert_eq(_items(_state(3), [], [battle]).size(), 0)


func test_a_watched_courts_sea_battle_reports_both_courts() -> void:
	var battle: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 0,
		"zone": 0,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"defender_lost": [1, 2, 3],
	}
	var items: Array = _items(_state(3), [ENGLAND], [], [battle])
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.INTEREST)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("England"))
	assert_false(text.contains("3 hulls"), "another court's losses are never counted")


## Charted is the gate for a watched court's fight, and the crown's own chart is
## what counts (wiki: the-gazette § What the crown can know; DR-20261110-28).
func test_a_watched_courts_battle_in_uncharted_land_is_not_printed() -> void:
	var province: int = _new_world_province()
	var battle: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"defender_lost": [1],
	}
	assert_eq(
		_items(_state(3), [ENGLAND], [battle], [], {}, 0, [], [], _charts()).size(),
		0,
		"uncharted ground prints nothing"
	)
	var charted: Array = _items(
		_state(3), [ENGLAND], [battle], [], {}, 0, [], [], _charts(province)
	)
	assert_eq(charted.size(), 1, "the crown's own chart opens the place")
	assert_eq(int(charted[0]["class"]), Gazette.Class.INTEREST)
	assert_false(
		String(charted[0]["text"]).contains("1 regiments"),
		"a charted fight still prints no casualty count"
	)


func test_a_watched_courts_battle_in_uncharted_water_is_not_printed() -> void:
	var zone: int = _new_world_zone()
	var battle: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 1,
		"zone": zone,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"defender_lost": [1, 2],
	}
	assert_eq(_items(_state(3), [ENGLAND], [], [battle], {}, 0, [], [], _charts()).size(), 0)
	assert_eq(
		_items(_state(3), [ENGLAND], [], [battle], {}, 0, [], [], _charts(-1, zone)).size(),
		1,
		"charted water carries the line"
	)


## A watched court's study is a spy's finding, never the sheet's
## (wiki: civilian-units § Spy; DR-20261110-28).
func test_a_watched_courts_finished_study_is_never_printed() -> void:
	var research: Dictionary = {VIEWER: ["crop_rotation"], ENGLAND: ["crop_rotation"]}
	var items: Array = _items(_state(3), [ENGLAND], [], [], research)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains(TechCatalog.display_name("crop_rotation")))


## A watched court's capture and hold read as fact without a body count: the
## place, the winner and the beaten side only (DR-20261110-28).
func test_a_watched_courts_capture_and_hold_print_no_numbers() -> void:
	var province: int = _new_world_province()
	var charts: CourtCharts = _charts(province)
	var capture: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.CAPTURE,
		"captured": true,
		"defender_lost": [1, 2, 3],
	}
	var held: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": [1, 2],
	}
	var items: Array = _items(_state(3), [ENGLAND], [capture, held], [], {}, 0, [], [], charts)
	assert_eq(items.size(), 2)
	for item: Variant in items:
		var text: String = String((item as Dictionary)["text"])
		assert_false(text.contains("regiment"), "no casualties for another court: %s" % text)
		assert_true(text.contains("England") and text.contains("France"))


## The crown's own fight prints with numbers wherever it happens: its own report
## is not gated by its chart.
func test_the_crowns_own_battle_ignores_the_chart() -> void:
	var battle: Dictionary = {
		"attacker": VIEWER,
		"defender": FRANCE,
		"region": 1,
		"province": _new_world_province(),
		"outcome": ArmyCombat.Outcome.CAPTURE,
		"captured": true,
		"defender_lost": [1, 2],
	}
	var items: Array = _items(_state(3), [], [battle], [], {}, 0, [], [], _charts())
	assert_eq(items.size(), 1)
	assert_true(String(items[0]["text"]).contains("2 regiments"))


## The crown's own losses always print their numbers, even when it did not win
## (wiki: the-gazette § What the crown can know).
func test_a_field_battle_the_crown_loses_prints_its_dead() -> void:
	var battle: Dictionary = {
		"attacker": FRANCE,
		"defender": VIEWER,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"attacker_lost": [1],
		"defender_lost": [1, 2, 3],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("3 of our regiments are lost"), text)


## A fought win that takes the province is a capture on the crown's page: the
## sheet must say the province changed hands, not only that the field was held
## (wiki: the-gazette § Item catalog — "Provinces the crown took or lost").
func test_a_fought_capture_prints_the_province_lost() -> void:
	var battle: Dictionary = {
		"attacker": FRANCE,
		"defender": VIEWER,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"captured": true,
		"attacker_lost": [1],
		"defender_lost": [1],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("has carried"), text)
	assert_true(text.contains("1 of our regiments is lost"), text)


## An advantage holds the field and leaves the province with its owner, so the
## sheet keeps the held-field line (wiki: quick-battle § Outcome and integration).
func test_an_advantage_still_reads_as_a_held_field() -> void:
	var battle: Dictionary = {
		"attacker": FRANCE,
		"defender": VIEWER,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
		"attacker_lost": [1],
		"defender_lost": [1],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	assert_true(String(items[0]["text"]).contains("holds the field"), String(items[0]["text"]))


func test_a_standoff_prints_the_crowns_own_dead() -> void:
	var battle: Dictionary = {
		"attacker": VIEWER,
		"defender": FRANCE,
		"region": 0,
		"province": _province(),
		"outcome": ArmyCombat.Outcome.STALEMATE,
		"attacker_lost": [1, 2],
		"defender_lost": [1],
	}
	var items: Array = _items(_state(3), [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("2 of our regiments lost"), text)


## A beaten squadron that slips away still costs the crown that held the water
## hulls (wiki: the-gazette § What the crown can know; ships-and-naval § Naval
## Combat Resolution).
func test_a_withdrawal_that_costs_the_crown_hulls_prints_them() -> void:
	var battle: Dictionary = {
		"attacker": FRANCE,
		"defender": VIEWER,
		"region": 0,
		"zone": 0,
		"outcome": NavalCombat.Outcome.SIDE2_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["h1"],
		"retreat": {"ok": true, "success": true, "beaten": FRANCE},
	}
	var items: Array = _items(_state(3), [], [], [battle])
	assert_eq(items.size(), 1)
	var text: String = String(items[0]["text"])
	assert_true(text.contains("1 of our hulls lost"), text)


## Another court's standoff and withdrawal still print no numbers
## (wiki: the-gazette § What the crown can know; DR-20261110-28).
func test_a_watched_courts_standoff_and_withdrawal_print_no_numbers() -> void:
	var province: int = _new_world_province()
	var zone: int = _new_world_zone()
	var standoff: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 1,
		"province": province,
		"outcome": ArmyCombat.Outcome.STALEMATE,
		"attacker_lost": [1, 2],
		"defender_lost": [1],
	}
	var withdrawal: Dictionary = {
		"attacker": ENGLAND,
		"defender": FRANCE,
		"region": 1,
		"zone": zone,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": ["h1"],
		"defender_lost": [],
		"retreat": {"ok": true, "success": true, "beaten": FRANCE},
	}
	var items: Array = _items(
		_state(3), [ENGLAND], [standoff], [withdrawal], {}, 0, [], [],
		_charts(province, zone)
	)
	assert_eq(items.size(), 2)
	for item: Variant in items:
		var text: String = String((item as Dictionary)["text"])
		assert_false(text.contains("regiment"), "no casualties for another court: %s" % text)
		assert_false(text.contains("hull"), "no hulls for another court: %s" % text)


func test_deed_income_is_our_court_news() -> void:
	var items: Array = _items(_state(3), [], [], [], {}, 1250)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains("estates"))


func test_a_prize_taken_off_rival_trade_prints_as_a_prize() -> void:
	var raids: Array = [
		{
			"kind": "prize",
			"zone_name": "the Windward Passage",
			"losses": {"grain": 3},
		}
	]
	var items: Array = _items(_state(3), [], [], [], {}, 0, raids)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_true(String(items[0]["text"]).contains("3 grain"))


## A raid that sends a merchant down says so in the record (DR-20261111-17).
func test_a_raid_that_sinks_a_merchant_names_her_in_the_gazette() -> void:
	var raids: Array = [
		{
			"kind": "prize",
			"zone_name": "the Windward Passage",
			"losses": {"grain": 3},
			"hulls_lost": [{"type_id": "fluyte", "name": "Vrouw Maria"}],
		},
		{
			"kind": "incoming",
			"zone_name": "Mar Caribe",
			"losses": {"timber": 2},
			"hulls_lost": [{"type_id": "carrack", "name": "Santa Ana"}],
		},
	]
	var items: Array = _items(_state(3), [], [], [], {}, 0, raids)
	assert_eq(items.size(), 2)
	assert_true(String(items[0]["text"]).contains("sends the Fluyte Vrouw Maria down"))
	assert_true(String(items[1]["text"]).contains("sent the Carrack Santa Ana to the bottom"))


func test_a_great_powers_fall_is_world_news() -> void:
	var falls: Array = [{"faction": FRANCE, "conqueror": ENGLAND}]
	var items: Array = _items(_state(3), [], [], [], {}, 0, [], falls)
	assert_eq(items.size(), 1)
	assert_eq(int(items[0]["class"]), Gazette.Class.WORLD)
	assert_true(String(items[0]["text"]).contains("France"))


## A Minor Nation falling is map cleanup, not a struck name on the roll of
## powers (wiki: the-gazette § Item catalog — World).
func test_a_minor_nations_fall_is_not_world_news() -> void:
	var falls: Array = [{"faction": GENOA, "conqueror": ENGLAND}]
	assert_eq(_items(_state(3), [], [], [], {}, 0, [], falls).size(), 0)


# --- prose -------------------------------------------------------------------


## Every catalogue kind this sheet can print must produce a filled line: no
## template may leave a field or print nothing (REQ-P2-03, REQ-P1-07).
func test_every_catalogue_kind_prints_a_filled_line() -> void:
	var base: Dictionary = {
		"who": "England",
		"whom": "France",
		"aggressor": "Spain",
		"target": "France",
		"place": "Coro",
		"label": "Embassy",
		"count": 3,
		"prize": "3 grain",
		"bonus": "Tercio",
		"amount": 1250,
		"percent": 10,
		"cause": "war",
	}
	var kinds: Array[String] = [
		"warDeclared",
		"peaceMade",
		"allianceFormed",
		"allianceBroken",
		"joinEmpire",
		"colonyFormed",
		"colonyReleased",
		"overtureEstablished",
		"overtureRejected",
		"callToArmsAccepted",
		"callToArmsRefused",
		"interventionProtest",
		"interventionIntervened",
		"interventionDoNothing",
		"proposalAccepted",
		"proposalRefused",
		"subsidySet",
		"subsidyCancelled",
		"ftpSigned",
		"ftpRefused",
		"ftpRevoked",
		"boycottSet",
		"boycottRevoked",
		"grantAid",
		"firstContact",
		"greatPowerFell",
		"battleCapture",
		"battleHeld",
		"battleAnnihilated",
		"battleStandoff",
		"seaHeld",
		"seaWithdrew",
		"seaDraw",
		"techFinished",
		"richesRendered",
		"raidSuffered",
		"raidPrize",
	]
	for kind: String in kinds:
		for self_act: bool in [true, false]:
			var rec: Dictionary = base.duplicate()
			rec["kind"] = kind
			rec["self_act"] = self_act
			var text: String = GazetteCopy.line(rec)
			assert_false(text.is_empty(), "%s prints a line" % kind)
			assert_false(
				text.contains("%s") or text.contains("%d"),
				"%s leaves no unfilled field" % kind
			)


## Every narrated diplomacy kind builds a record, and the record prints.
func test_every_narrated_diplomacy_kind_builds_and_prints() -> void:
	var state: DiplomacyState = _state(3)
	for kind: String in GazetteDiplomacy.COURT_KINDS:
		var event: Dictionary = {
			"kind": kind,
			"a": VIEWER,
			"b": FRANCE,
			"turn": 3,
			"data": {
				"aggressor": ENGLAND,
				"target": FRANCE,
				"stage": DiplomacyCatalog.STAGE_EMBASSY,
				"kind": DiplomacyProposals.KIND_PEACE,
				"percent": 10,
				"amount": 1000,
				"cause": "war",
			},
		}
		var rec: Dictionary = GazetteDiplomacy.record(kind, event, state, VIEWER)
		assert_false(rec.is_empty(), "%s builds a record" % kind)
		assert_false(GazetteCopy.line(rec).is_empty(), "%s prints" % kind)


## Every Combat outcome the rules can return reaches the sheet with a line.
func test_every_combat_outcome_reaches_the_sheet() -> void:
	var land: Array[int] = [
		ArmyCombat.Outcome.ATTACKER_VICTORY,
		ArmyCombat.Outcome.DEFENDER_VICTORY,
		ArmyCombat.Outcome.STALEMATE,
		ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		ArmyCombat.Outcome.CAPTURE,
		ArmyCombat.Outcome.ATTACKER_ADVANTAGE,
	]
	for outcome: int in land:
		var battle: Dictionary = _battle(outcome)
		var items: Array = _items(_state(3), [], [battle])
		assert_eq(items.size(), 1, "land outcome %d prints" % outcome)
	var sea: Array[int] = [
		NavalCombat.Outcome.SIDE1_VICTORY, NavalCombat.Outcome.SIDE2_VICTORY,
		NavalCombat.Outcome.STALEMATE,
	]
	for outcome: int in sea:
		var battle: Dictionary = _sea_battle(outcome)
		var items: Array = _items(_state(3), [], [], [battle])
		assert_eq(items.size(), 1, "sea outcome %d prints" % outcome)
	var retreat: Dictionary = _sea_battle(NavalCombat.Outcome.STALEMATE)
	retreat["retreat"] = {"success": true, "beaten": VIEWER}
	assert_eq(_items(_state(3), [], [], [retreat]).size(), 1, "a withdrawal prints")


func test_the_prose_never_invents_an_outcome_for_an_unknown_kind() -> void:
	assert_eq(GazetteCopy.line({"kind": "noSuchThing"}), "")


## The copy desk's table is the sheet's one list of kinds, so a kind the
## diplomacy catalogue narrates cannot fall off the desk (REQ-P2-03, RUB-P3-01).
func test_every_narrated_kind_has_a_copy_desk() -> void:
	var narrated: Array[String] = []
	narrated.append_array(GazetteDiplomacy.COURT_KINDS)
	narrated.append_array(GazetteDiplomacy.WORLD_KINDS)
	for kind: String in narrated:
		assert_true(GazetteCopy.kinds().has(kind), "%s has a copy desk" % kind)


func test_an_unmet_party_reads_as_an_unknown_faction() -> void:
	var state: DiplomacyState = _state(3)
	var line: String = GazetteCopy.line(
		GazetteDiplomacy.record(
			"warDeclared",
			{"kind": "warDeclared", "a": AZTEC, "b": FRANCE, "turn": 3, "data": {}},
			state,
			VIEWER
		)
	)
	assert_true(line.contains("Unknown faction"), "a stranger is never named")


# --- helpers -----------------------------------------------------------------


## A diplomacy ledger at `turn` with the opening embassies in place.
func _state(turn: int) -> DiplomacyState:
	var state := DiplomacyState.new()
	state.initialize(1)
	state.turn = turn
	return state


func _sheet(turn: int, text: String) -> Dictionary:
	return {
		"turn": turn,
		"items": [{"class": Gazette.Class.COURT, "kind": "techFinished", "text": text}],
	}


## The sheet's items for one resolved turn.
func _items(
	state: DiplomacyState,
	watched: Array[int],
	land: Array = [],
	naval: Array = [],
	research: Dictionary = {},
	richness: int = 0,
	raids: Array = [],
	falls: Array = [],
	charts: CourtCharts = null
) -> Array:
	var sheet: Dictionary = Gazette.collect(
		VIEWER, 3, world, state, watched, land, naval, falls, research, richness, raids, charts
	)
	return sheet["items"]


## The crown's chart for a headless sheet: the Old World baseline, plus a New
## World province and/or sea zone the crown has charted when asked.
func _charts(province: int = -1, zone: int = -1) -> CourtCharts:
	var views: Dictionary = {}
	for index in world.region_count():
		var view := VisibilityModel.new()
		view.setup(world.region(index), VIEWER)
		if index == FactionCatalog.NEW_WORLD:
			if province >= 0:
				view.reveal_province(province)
			if zone >= 0:
				view.reveal_sea_zone(zone)
		views[index] = view
	var charts := CourtCharts.new()
	charts.setup(world, VIEWER, views)
	return charts


## An uncharted New World province: the fogged Old World cannot refuse a fight.
func _new_world_province() -> int:
	return int(world.region(FactionCatalog.NEW_WORLD).provinces[0].id)


func _new_world_zone() -> int:
	return int(world.region(FactionCatalog.NEW_WORLD).sea_zones[0].id)


func _province() -> int:
	var model: MapModel = world.region(0)
	return int(model.provinces[0].id)


func _province_name(province: int) -> String:
	return world.region(0).province_name(province)


## A land-battle record of `outcome` between our crown and France.
func _battle(outcome: int) -> Dictionary:
	return {
		"attacker": VIEWER,
		"defender": FRANCE,
		"region": 0,
		"province": _province(),
		"outcome": outcome,
		"captured": outcome == ArmyCombat.Outcome.CAPTURE,
		"attacker_lost": [1],
		"defender_lost": [1, 2],
		"garrison": 1,
		"recovered_type": "peasant_levies",
	}


## A sea-battle record of `outcome` in the Old World's first zone.
func _sea_battle(outcome: int) -> Dictionary:
	return {
		"attacker": VIEWER,
		"defender": FRANCE,
		"region": 0,
		"zone": 0,
		"outcome": outcome,
		"attacker_lost": [1],
		"defender_lost": [1, 2, 3],
	}

# --- gazette_plate ---
## The soft Gazette plate: the turn-start sheet, the archive and the watchlist
## editor on one surface, dismissible with one press (wiki: the-gazette § When
## it appears, § History screen; DR-20261110-14). Presentation only — the lines
## are what [Gazette] built (REQ-P2-03, REQ-P5-06).

const gazette_plate_VIEWER: int = 0
const gazette_plate_ENGLAND: int = 1

var plate: GazettePlate = null


func _setup_gazette_plate() -> void:
	plate = GazettePlate.new()
	add_child(plate)


func _teardown_gazette_plate() -> void:
	if is_instance_valid(plate):
		plate.free()
	plate = null


func test_the_sheet_prints_its_stamp_and_each_class_heading() -> void:
	_setup_gazette_plate()
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	assert_true(plate.is_shown())
	assert_true(_has_text(plate, "THE GAZETTE"))
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)))
	assert_true(_has_text(plate, "THE WORLD"))
	assert_true(_has_text(plate, "OUR COURT"))
	assert_true(_has_text(plate, "The gauntlet passes between them."))


func test_one_press_sets_the_sheet_aside() -> void:
	_setup_gazette_plate()
	var dismissed: Array[bool] = []
	plate.dismissed.connect(func() -> void: dismissed.append(true))
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	plate.dismiss()
	assert_false(plate.is_shown())
	assert_false(plate.visible)
	assert_eq(dismissed.size(), 1)


## The plate is soft: the map under and around it keeps its pointer.
func test_only_the_plate_takes_the_pointer() -> void:
	_setup_gazette_plate()
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	assert_eq(plate.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the map stays usable")
	assert_eq(plate._panel.mouse_filter, Control.MOUSE_FILTER_STOP, "the sheet is readable")


func test_a_turn_that_printed_nothing_says_so() -> void:
	_setup_gazette_plate()
	plate.open_sheet({"turn": 4, "items": []}, GazetteState.new(), null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, GazettePlate.EMPTY_LINE))


## The plate stands as tall as its news and only the news scrolls, so a quiet
## sheet never leaves a reef of blank paper under it.
func test_the_plate_takes_the_height_of_its_news() -> void:
	_setup_gazette_plate()
	plate.size = Vector2(1280, 800)
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	plate._fit()
	assert_eq(plate._panel.offset_bottom, plate._panel.offset_top, "height follows content")
	assert_true(plate._scroll.custom_minimum_size.y >= 120.0, "the sheet keeps a readable body")
	assert_true(plate._scroll.custom_minimum_size.y <= 600.0, "a long sheet scrolls")


## The sheet's foot states the race for the age; the archive, a past sheet, does
## not (wiki: victory § Victory Check; DR-20261112-05).
func test_the_live_sheet_states_the_race_for_the_age() -> void:
	_setup_gazette_plate()
	var age: String = "The age: you hold 12 of 31 Old World provinces; England leads with 9 of 31."
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER, age)
	assert_true(_has_text(plate, "THE STATE OF THE AGE"), "the standing column is printed")
	assert_true(_has_text(plate, "you hold 12 of 31"), age)
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_false(_has_text(plate, "THE STATE OF THE AGE"), "a past sheet carries no standing")


func test_a_sheet_without_a_reading_prints_no_standing_column() -> void:
	_setup_gazette_plate()
	plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	assert_false(_has_text(plate, "THE STATE OF THE AGE"))


## The seal opens the history screen; its sheet tab is the live sheet, so the
## race stays readable on a turn that printed no news, and it is the newest
## sheet rather than whatever was on screen last (wiki: the-gazette § History
## screen — the Gazette and every prior turn's sheet are readable there).
func test_the_history_screen_keeps_the_live_sheet_and_its_standing() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	state.append(gazette_plate_sheet(3))
	var age: String = "The age: you hold 12 of 31 Old World provinces; England leads with 9 of 31."
	plate.open_archive(state, null, gazette_plate_VIEWER, age)
	plate._go(GazettePlate.Mode.SHEET)
	assert_true(_has_text(plate, "THE STATE OF THE AGE"), "the live sheet keeps its standing")
	assert_true(_has_text(plate, age), age)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)), "the newest sheet is read")
	assert_false(_has_text(plate, GazettePlate.EMPTY_LINE), "a filed sheet is not empty news")


func test_the_archive_opens_on_the_newest_sheet_and_walks_back() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	state.append(gazette_plate_sheet(2))
	state.append(gazette_plate_sheet(3))
	plate.open_archive(state, null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(3)))
	plate._step(1)
	assert_true(_has_text(plate, DiplomacyHistory.stamp_for_turn(2)))
	assert_true(plate._older.disabled, "the oldest sheet has no older neighbour")
	plate._step(-1)
	assert_true(plate._newer.disabled, "the newest sheet leads")


func test_an_archive_without_sheets_says_the_presses_have_not_run() -> void:
	_setup_gazette_plate()
	plate.open_archive(GazetteState.new(), null, gazette_plate_VIEWER)
	assert_true(_has_text(plate, GazettePlate.NO_HISTORY))


func test_the_watchlist_lists_met_courts_and_toggles_the_list() -> void:
	_setup_gazette_plate()
	var state := GazetteState.new()
	var diplomacy := DiplomacyState.new()
	diplomacy.initialize(1)
	plate.open_watchlist(state, diplomacy, gazette_plate_VIEWER)
	var box: CheckBox = _check_for(plate, "England")
	assert_not_null(box, "a met court is offered")
	assert_false(box.button_pressed)
	box.button_pressed = true
	assert_true(state.is_watched(gazette_plate_ENGLAND), "ticking follows the court")
	box.button_pressed = false
	assert_false(state.is_watched(gazette_plate_ENGLAND))
	assert_true(state.removed.has(gazette_plate_ENGLAND), "and the removal is remembered")


func test_the_plate_narrows_to_a_phone_viewport() -> void:
	_setup_gazette_plate()
	plate.size = Vector2(480, 800)
	plate._fit()
	var width: float = plate._panel.offset_right - plate._panel.offset_left
	assert_true(width <= 480.0, "the sheet never outgrows the screen")
	assert_true(width >= GazettePlate.MIN_WIDTH)


## Toasts stay readable: while the sheet is up they are pushed to the lane under
## it, and the moment it goes they return to the top (REQ-P5-05). A phone's
## resting lane is not the atlas 84, so the plate gives back the lane's own top.
func test_the_sheet_moves_the_toast_lane_below_itself() -> void:
	_setup_gazette_plate()
	var host := ToastHost.new()
	host.size = Vector2(1280, 800)
	add_child(host)
	var lane := HudDespatches.new()
	host.add_child(lane)
	# A compact bar (56) + 6 is well above the atlas 84 the old plate assumed.
	lane.fit(true, 56.0, 382.0)
	var resting: float = lane.resting_top()
	assert_eq(resting, 62.0)

	var sheet_plate := GazettePlate.new()
	sheet_plate.despatches = lane
	host.add_child(sheet_plate)
	sheet_plate.open_sheet(gazette_plate_sheet(3), GazetteState.new(), null, gazette_plate_VIEWER)
	# The lane follows the laid-out sheet, so let one layout pass settle.
	await get_tree().process_frame
	sheet_plate._fit()
	assert_true(lane.lane_top() > resting, "the lane drops below the sheet")
	sheet_plate.dismiss()
	assert_eq(lane.lane_top(), resting, "the lane comes back to its own top")
	host.free()


## A stand-in for the HUD: the plate only needs the despatch lane.
class ToastHost:
	extends Control


# --- helpers -----------------------------------------------------------------


func gazette_plate_sheet(turn: int) -> Dictionary:
	return {
		"turn": turn,
		"items": [
			{
				"class": Gazette.Class.WORLD,
				"kind": "warDeclared",
				"text": "The gauntlet passes between them.",
			},
			{
				"class": Gazette.Class.COURT,
				"kind": "techFinished",
				"text": "Our scholars have finished the Crop Rotation.",
			},
		],
	}


func _check_for(node: Node, needle: String) -> CheckBox:
	if node is CheckBox and String((node as CheckBox).text).contains(needle):
		return node as CheckBox
	for child: Node in node.get_children():
		var found: CheckBox = _check_for(child, needle)
		if found != null:
			return found
	return null


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false
