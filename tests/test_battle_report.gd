extends GdToolsTest
## Despatch wording for resolved battles (moved out of the screen controller).

const FACTIONS: Array[String] = ["España", "England", "France", "Portugal"]


func test_a_side_one_victory_reads_as_a_held_zone() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["a", "b"],
	}
	assert_eq(BattleReport.describe(battle, "Windward Passage", FACTIONS),
		"España holds the Windward Passage — England loses 2 ships")


func test_a_side_two_victory_reads_as_a_repulse() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": NavalCombat.Outcome.SIDE2_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": [],
	}
	assert_eq(BattleReport.describe(battle, "Gulf of Darién", FACTIONS),
		"France repels England in the Gulf of Darién — 1 ships lost")


func test_a_stalemate_reads_as_a_withdrawal() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 3,
		"outcome": NavalCombat.Outcome.STALEMATE,
		"attacker_lost": [],
		"defender_lost": [],
	}
	assert_eq(BattleReport.describe(battle, "Azores", FACTIONS),
		"España and Portugal trade broadsides in the Azores and withdraw")


func test_unknown_flags_do_not_crash_the_despatch() -> void:
	var battle: Dictionary = {
		"attacker": 9,
		"defender": -1,
		"outcome": NavalCombat.Outcome.STALEMATE,
	}
	var text: String = BattleReport.describe(battle, "Nowhere", FACTIONS)
	assert_true(text.contains("An unknown flag"))


func test_a_land_victory_reads_as_a_capture() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.ATTACKER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": ["b", "c"],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Flanders", FACTIONS),
		"España takes Flanders — England loses 2 regiments"
	)


func test_a_land_repulse_reads_as_a_hold() -> void:
	var battle: Dictionary = {
		"attacker": 1,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"attacker_lost": ["a"],
		"defender_lost": [],
	}
	assert_eq(
		BattleReport.describe_land(battle, "Burgundy", FACTIONS),
		"France holds Burgundy — England loses 1 regiments"
	)


func test_mutual_annihilation_reports_the_reformed_garrison() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		"garrison": 1,
		"recovered_type": "guards",
	}
	assert_eq(
		BattleReport.describe_land(battle, "Artois", FACTIONS),
		"España and England destroy each other at Artois — a Guards garrison reforms"
	)


func test_mutual_annihilation_without_a_garrison_reads_empty() -> void:
	var battle: Dictionary = {
		"attacker": 0,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.MUTUAL_ANNIHILATION,
		"garrison": 0,
	}
	assert_eq(
		BattleReport.describe_land(battle, "Artois", FACTIONS),
		"España and England destroy each other at Artois — the province stands empty"
	)


func test_an_unopposed_capture_and_a_stalemate_read_plainly() -> void:
	var capture: Dictionary = {
		"attacker": 0,
		"defender": 3,
		"outcome": ArmyCombat.Outcome.CAPTURE,
	}
	assert_eq(
		BattleReport.describe_land(capture, "Algarve", FACTIONS),
		"España occupies Algarve unopposed"
	)
	var standoff: Dictionary = {
		"attacker": 0,
		"defender": 2,
		"outcome": ArmyCombat.Outcome.STALEMATE,
	}
	assert_eq(
		BattleReport.describe_land(standoff, "Picardy", FACTIONS),
		"España and France stand off at Picardy"
	)
