extends GdToolsTest
## The Gazette's rules: the watchlist and its archive, the three classes and
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
	assert_true(text.contains("3 hulls"))


func test_finished_technologies_are_news_of_the_court_that_finished_them() -> void:
	var research: Dictionary = {VIEWER: ["crop_rotation"], ENGLAND: ["crop_rotation"]}
	var items: Array = _items(_state(3), [ENGLAND], [], [], research)
	assert_eq(items.size(), 2)
	assert_eq(int(items[0]["class"]), Gazette.Class.COURT)
	assert_eq(int(items[1]["class"]), Gazette.Class.INTEREST)
	assert_true(String(items[1]["text"]).contains(TechCatalog.display_name("crop_rotation")))


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
	falls: Array = []
) -> Array:
	var sheet: Dictionary = Gazette.collect(
		VIEWER, 3, world, state, watched, land, naval, falls, research, richness, raids
	)
	return sheet["items"]


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
