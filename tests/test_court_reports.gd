extends GdToolsTest
## Court reports for a shadowed rival (wiki: civilian-units § Spy — court
## reports; DR-20261110-07): which acts are read, how each kind reads, what is
## masked, the cap, and that an unwatched court yields nothing
## (REQ-P2-01, REQ-P2-04).

const VIEWER: int = 0
const ENGLAND: int = 1
const PORTUGAL: int = 3
const FRANCE: int = 2

const Fixture = preload("res://tests/map_fixture.gd")

var state: DiplomacyState


func before_each() -> void:
	state = DiplomacyState.new()
	state.initialize(1)


func test_a_proposal_is_read_in_the_receivers_voice() -> void:
	assert_eq(CourtReports.actor_of({"kind": "warDeclared", "a": ENGLAND, "b": PORTUGAL}), ENGLAND)
	var offered: Dictionary = {"kind": "proposalAccepted", "a": ENGLAND, "b": PORTUGAL}
	assert_eq(CourtReports.actor_of(offered), PORTUGAL, "the receiver answers")


func test_only_the_turns_own_acts_reach_the_despatch() -> void:
	state.record_event("warDeclared", ENGLAND, PORTUGAL)
	state.record_event("peaceMade", ENGLAND, PORTUGAL)
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 1, [], [], {}, [ENGLAND]
	)
	var lines: Array[String] = CourtReports.digest(facts, state, null, VIEWER, ENGLAND)
	assert_eq(lines.size(), 1, "the mark hides the earlier war")
	assert_eq(lines[0], "England and Portugal concluded a white peace.")


func test_an_unwatched_court_writes_nothing() -> void:
	state.record_event("warDeclared", FRANCE, PORTUGAL)
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [], [], {}, [ENGLAND]
	)
	assert_eq(facts.size(), 0, "no spy, no despatch")
	assert_eq(CourtReports.digest(facts, state, null, VIEWER, FRANCE).size(), 0)


func test_a_capture_reads_from_both_sides() -> void:
	var battle: Dictionary = {
		"province": 5, "region": 0, "attacker": ENGLAND, "defender": PORTUGAL,
		"captured": true, "outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
	}
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [battle], [], {}, [ENGLAND, PORTUGAL]
	)
	var winner: Array[String] = CourtReports.digest(facts, state, null, VIEWER, ENGLAND)
	var loser: Array[String] = CourtReports.digest(facts, state, null, VIEWER, PORTUGAL)
	assert_eq(winner[0], "England took an unnamed province from Portugal.")
	assert_eq(loser[0], "Portugal lost an unnamed province to England.")


func test_a_beaten_assault_reads_from_both_sides() -> void:
	var battle: Dictionary = {
		"province": 5, "region": 0, "attacker": ENGLAND, "defender": PORTUGAL,
		"captured": false, "outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
	}
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [battle], [], {}, [ENGLAND, PORTUGAL]
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, ENGLAND)[0],
		"England's assault on an unnamed province was broken by Portugal."
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, PORTUGAL)[0],
		"Portugal threw back England's assault on an unnamed province."
	)


func test_a_squadron_action_reads_by_outcome() -> void:
	var battle: Dictionary = {
		"zone": 2, "region": 0, "attacker": ENGLAND, "defender": PORTUGAL,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
	}
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [], [battle], {}, [ENGLAND, PORTUGAL]
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, ENGLAND)[0],
		"England's squadron broke Portugal's in the open sea."
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, PORTUGAL)[0],
		"Portugal's squadron was broken by England's in the open sea."
	)


func test_finished_technologies_are_named() -> void:
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [], [], {ENGLAND: ["money_lending"]}, [ENGLAND]
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, ENGLAND)[0],
		"England finished %s." % TechCatalog.display_name("money_lending")
	)


func test_technologies_gained_diff_the_two_tables() -> void:
	var before: Dictionary = {ENGLAND: {"money_lending": true}}
	var after: Dictionary = {ENGLAND: {"money_lending": true, "printing_press": true}}
	var gained: Dictionary = CourtReports.techs_gained(before, after)
	assert_eq((gained[ENGLAND] as Array).size(), 1, "only the new row counts")
	assert_eq(String((gained[ENGLAND] as Array)[0]), "printing_press")
	assert_false(gained.has(FRANCE), "a quiet court gains nothing")


func test_an_unmet_court_stays_masked() -> void:
	state.record_event("warDeclared", ENGLAND, 99)
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [], [], {}, [ENGLAND]
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, ENGLAND)[0],
		"England declared war on Unknown faction."
	)


func test_the_despatch_is_capped() -> void:
	var techs: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		techs.append(tech_id)
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [], [], {ENGLAND: techs}, [ENGLAND]
	)
	assert_eq(
		CourtReports.digest(facts, state, null, VIEWER, ENGLAND).size(),
		CourtReports.MAX_LINES
	)


func test_facts_of_another_court_never_leak() -> void:
	var facts: Array[Dictionary] = CourtReports.collect(
		state, 0, [], [], {ENGLAND: ["money_lending"]}, [ENGLAND, PORTUGAL]
	)
	assert_eq(CourtReports.digest(facts, state, null, VIEWER, PORTUGAL).size(), 0)
	assert_eq(CourtReports.digest(facts, state, null, VIEWER, ENGLAND).size(), 1)


# --- the session glue --------------------------------------------------------


func test_the_turn_writes_a_despatch_for_a_shadowed_court() -> void:
	var play := PlaySession.new()
	play.world = Fixture.world()
	play.region_index = 0
	play.civilian_layer = CivilianLayer.new()
	play.ai = AiState.new()
	play.diplomacy = DiplomacyState.new()
	play.diplomacy.initialize(1)
	var rival: int = _rival_great_power(play.world.region(0))
	assert_true(rival >= 0, "the fixture has a rival Great Power")
	var spy := CivilianState.new()
	spy.owner = play.player_faction
	spy.type_id = SpyNetworks.SPY_TYPE
	spy.tile = play.world.region(0).capital_tile_of(_province_of(play.world.region(0), rival))
	play.civilian_layer.units.append(spy)
	assert_eq(MapPlayEspionage.shadowed_rivals(play)[0], rival)
	var before: Dictionary = MapPlayEspionage.tech_snapshot(play)
	play.ai.economy_for(rival).tech_unlocked["money_lending"] = true
	var battle: Dictionary = {
		"province": _province_of(play.world.region(0), rival),
		"region": 0,
		"attacker": play.player_faction,
		"defender": rival,
		"captured": false,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
	}
	MapPlayEspionage.record_court_reports(play, [battle], [], before)
	assert_eq(int(play.court_reports["turn"]), play.turn)
	assert_true((play.court_reports["shadowed"] as Array).has(rival))
	var lines: Array[String] = CourtReports.digest(
		play.court_reports["facts"], play.diplomacy, play.world, play.player_faction, rival
	)
	assert_eq(lines.size(), 2, "a broken assault and a finished technology")
	assert_eq(lines[1], "%s finished %s." % [
		FactionCatalog.name_of(rival), TechCatalog.display_name("money_lending")
	])
	assert_eq(
		play.court_report_mark, play.diplomacy.events.size(),
		"the next turn starts from this mark"
	)
	play.civilian_layer.free()


func test_the_observer_keeps_no_despatch() -> void:
	var play := PlaySession.new()
	play.observer_mode = true
	play.ai = AiState.new()
	MapPlayEspionage.record_court_reports(play, [], [], {})
	assert_true(play.court_reports.is_empty(), "no court to read it")


func _rival_great_power(model: MapModel) -> int:
	for raw: ProvinceState in model.provinces:
		var owner: int = raw.owner
		if owner == FactionCatalog.PLAYER_FACTION or owner == MapModel.NO_ID:
			continue
		if FactionCatalog.great_power_ids().has(owner):
			return owner
	return -1


func _province_of(model: MapModel, owner: int) -> int:
	for raw: ProvinceState in model.provinces:
		if raw.owner == owner:
			return int(raw.id)
	return MapModel.NO_ID


func test_the_court_panel_carries_the_despatch_only_for_a_spy() -> void:
	state.record_event("warDeclared", ENGLAND, 6)
	# Genoa (6) is the minor the act names; England (1) is the court on show.
	var panel := DiplomacyPanel.new()
	add_child(panel)
	var reports: Dictionary = {
		"turn": 4,
		"shadowed": [ENGLAND],
		"facts": CourtReports.collect(state, 0, [], [], {}, [ENGLAND]),
	}
	panel.refresh(state, null, VIEWER, 2500, {}, reports)
	panel.select_faction(ENGLAND)
	assert_true(_has_text(panel._detail, "COURT REPORTS"))
	assert_true(_has_text(panel._detail, "England declared war on Genoa."))
	reports["facts"] = []
	panel.refresh(state, null, VIEWER, 2500, {}, reports)
	panel.select_faction(ENGLAND)
	assert_true(_has_text(panel._detail, "did nothing worth a despatch"))
	reports["shadowed"] = []
	panel.refresh(state, null, VIEWER, 2500, {}, reports)
	panel.select_faction(ENGLAND)
	assert_false(_has_text(panel._detail, "COURT REPORTS"), "no spy, no despatch")
	panel.free()


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false
