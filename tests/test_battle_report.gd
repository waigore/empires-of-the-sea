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
