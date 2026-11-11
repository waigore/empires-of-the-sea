extends GdToolsTest
## Every regiment bears a title and a record (wiki: naming § Regiment names,
## § Regiment records; DR-20261111-18): a muster christens it from its crown's
## period pool, an army never wears the same title twice, a saved regiment keeps
## both its title and its tally, an old save is christened on load, and every
## engagement its side survives is written down once — auto-resolve and Quick
## Battle through the same attach.

const Fixture = preload("res://tests/army_fixture.gd")


func test_every_muster_names_its_regiments_from_the_crown_pool() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)

	for regiment_id: String in army.regiments:
		var title: String = RegimentNames.of(army, regiment_id)
		assert_false(title.is_empty(), "a mustered regiment is never anonymous")
		assert_true(
			RegimentNames.pool_for(0).has(title),
			"Spain christens from its own pool, got '%s'" % title
		)


func test_a_reload_speaks_the_same_titles() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)
	var before: Dictionary = {}
	for regiment_id: String in army.regiments:
		before[regiment_id] = RegimentNames.of(army, regiment_id)

	var restored: ArmyState = ArmyState.from_dict(army.to_dict())

	for regiment_id: String in restored.regiments:
		assert_eq(RegimentNames.of(restored, regiment_id), String(before[regiment_id]))


func test_no_army_wears_the_same_title_twice() -> void:
	var army := ArmyState.muster(1, 0, 2, false, [], 1)
	for index in range(14):
		army.add_regiment("unit_%d" % (index + 1), "pikemen")

	var titles: Array[String] = []
	var numbered: bool = false
	for regiment_id: String in army.regiments:
		var title: String = RegimentNames.of(army, regiment_id)
		assert_false(titles.has(title), "'%s' is worn twice" % title)
		if title.ends_with(" II"):
			numbered = true
		titles.append(title)
	# Past the ten-title pool the repeats are numbered, never duplicated.
	assert_true(numbered, "a repeat is numbered, not duplicated")


func test_a_crown_with_no_pool_still_names_its_regiments() -> void:
	var army := ArmyState.muster(1, 9, 2, false, ["peasant_levies"], 1)

	assert_true(RegimentNames.GENERIC.has(RegimentNames.of(army, "unit_1")))


func test_a_detached_regiment_keeps_its_title_and_record() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen", "pikemen", "pikemen"])
	army.regiment_engagements["unit_102"] = 3
	army.regiment_wins["unit_102"] = 2
	var title: String = RegimentNames.of(army, "unit_102")
	var armies: Array[ArmyState] = [army]

	var result: Dictionary = ArmyState.split(armies, army, ["unit_102"], 2)

	assert_true(bool(result["ok"]), String(result["reason"]))
	var detached: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentNames.of(detached, "unit_102"), title, "the veteran keeps its title")
	assert_eq(int(RegimentRecord.of(detached, "unit_102")["engagements"]), 3)
	assert_eq(int(RegimentRecord.of(detached, "unit_102")["wins"]), 2)


func test_a_combined_army_keeps_each_regiments_title_and_record() -> void:
	var first := Fixture.army(1, 0, 2, ["pikemen"], true)
	var second := Fixture.army(2, 0, 2, ["musketeers"])
	second.regiment_engagements["unit_201"] = 1
	second.regiment_wins["unit_201"] = 1
	var title: String = RegimentNames.of(second, "unit_201")
	var armies: Array[ArmyState] = [first, second]

	var result: Dictionary = ArmyState.combine(armies, [first, second])

	assert_true(bool(result["ok"]), String(result["reason"]))
	var target: ArmyState = result["army"] as ArmyState
	assert_eq(RegimentNames.of(target, "unit_201"), title)
	assert_eq(int(RegimentRecord.of(target, "unit_201")["wins"]), 1)


func test_a_battle_is_written_into_every_survivors_record() -> void:
	var model := Fixture.build()
	var defender := Fixture.army(1, 1, 2, ["peasant_levies"], true)
	var attacker := Fixture.army(2, 0, 2, ["guards", "guards", "guards", "guards", "guards"])
	attacker.moved = true
	var armies: Array[ArmyState] = [defender, attacker]

	var reports: Array[Dictionary] = ArmyCombat.resolve_turn(model, armies, {})

	assert_eq(int(reports[0]["outcome"]), ArmyCombat.Outcome.ATTACKER_VICTORY)
	assert_false(attacker.is_empty(), "the winner keeps its standing regiments")
	for regiment_id: String in attacker.regiments:
		var record: Dictionary = RegimentRecord.of(attacker, regiment_id)
		assert_eq(int(record["engagements"]), 1, "one engagement is written down")
		assert_eq(int(record["wins"]), 1, "the field was won")
		assert_true(
			RegimentRecord.line(attacker, regiment_id).contains("1 engagement"),
			"the dossier line reads the same tally"
		)


func test_a_standoff_counts_an_engagement_but_no_win() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])
	var side: Array[ArmyState] = [army]

	RegimentRecord.note_battle(side, false)
	RegimentRecord.note_battle(side, true)

	var record: Dictionary = RegimentRecord.of(army, "unit_101")
	assert_eq(int(record["engagements"]), 2)
	assert_eq(int(record["wins"]), 1)


func test_the_dossier_line_is_empty_until_a_regiment_is_blooded() -> void:
	var army := Fixture.army(1, 0, 2, ["pikemen"])

	assert_eq(RegimentRecord.line(army, "unit_101"), "")

	army.regiment_engagements["unit_101"] = 4
	army.regiment_wins["unit_101"] = 3

	assert_eq(RegimentRecord.line(army, "unit_101"), "4 engagements · 3 won")


func test_an_old_save_is_christened_on_load() -> void:
	var army := ArmyState.muster(1, 0, 2, false, ["pikemen", "musketeers"], 1)
	var expected: Dictionary = {}
	for regiment_id: String in army.regiments:
		expected[regiment_id] = RegimentNames.of(army, regiment_id)
	var data: Dictionary = army.to_dict()
	data.erase("regiment_names")
	data.erase("regiment_engagements")
	data.erase("regiment_wins")

	var restored: ArmyState = ArmyState.from_dict(data)

	for regiment_id: String in restored.regiments:
		assert_eq(
			RegimentNames.of(restored, regiment_id),
			String(expected[regiment_id]),
			"the same arithmetic christens the same title"
		)
		assert_eq(int(RegimentRecord.of(restored, regiment_id)["engagements"]), 0)


func test_the_aftermath_names_a_mauled_regiment() -> void:
	var army := Fixture.army(1, 0, 2, ["guards"])
	var side: Array[ArmyState] = [army]

	var entries: Array[Dictionary] = RegimentCondition.entries(side)

	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0]["name"]), RegimentNames.of(army, "unit_101"))
