extends GdToolsTest
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
