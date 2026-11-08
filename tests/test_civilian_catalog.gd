extends GdToolsTest
## Civilian roster and training costs (wiki: civilian-units § Civilian Types).

const ROLE_NAMES: Dictionary = {
	"explorer": "Explorer",
	"engineer": "Engineer",
	"builder": "Builder",
	"spy": "Spy",
	"merchant": "Merchant",
	"rail_builder": "Rail Builder",
}


func test_catalog_covers_all_six_wiki_types() -> void:
	assert_eq(CivilianCatalog.TYPES.size(), 6)
	assert_eq(CivilianCatalog.ORDER.size(), 6)
	for type_id: String in CivilianCatalog.ORDER:
		assert_true(CivilianCatalog.known(type_id), type_id)
		assert_eq(CivilianCatalog.display_name(type_id), String(ROLE_NAMES[type_id]))


func test_training_costs_match_the_wiki() -> void:
	for type_id: String in ["explorer", "engineer", "builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 1000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 2, type_id)
	for type_id: String in ["spy", "merchant", "rail_builder"]:
		assert_eq(CivilianCatalog.treasury_cost(type_id), 2000, type_id)
		assert_eq(CivilianCatalog.paper_cost(type_id), 4, type_id)


func test_only_the_starting_three_are_playable_this_milestone() -> void:
	assert_eq(CivilianCatalog.playable_types(), ["explorer", "engineer", "builder"])
	for type_id: String in ["spy", "merchant", "rail_builder"]:
		assert_false(CivilianCatalog.is_implemented(type_id), type_id)
		assert_true(CivilianCatalog.deferred_reason(type_id) != "", type_id)
	for type_id: String in CivilianCatalog.playable_types():
		assert_true(CivilianCatalog.is_starting(type_id), type_id)
		assert_eq(CivilianCatalog.deferred_reason(type_id), "")


func test_work_lists_match_the_wiki_table() -> void:
	assert_eq(CivilianCatalog.works("explorer"), ["explore", "prospect"])
	assert_eq(CivilianCatalog.works("builder"), ["build_improvement"])
	assert_eq(CivilianCatalog.works("engineer"), ["build_road", "build_port"])
	assert_eq(CivilianCatalog.works("spy"), ["counter_spy"])
	assert_eq(CivilianCatalog.works("merchant"), ["purchase_land"])
	assert_eq(CivilianCatalog.works("rail_builder"), ["build_rail"])


func test_affordability_needs_cash_and_paper() -> void:
	assert_true(CivilianCatalog.can_afford("explorer", 1000, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 999, 2))
	assert_false(CivilianCatalog.can_afford("explorer", 1000, 1))
	assert_false(CivilianCatalog.can_afford("merchant", 1999, 4))


func test_training_cost_text_reads_as_a_purse_line() -> void:
	assert_eq(CivilianCatalog.training_cost_text("explorer"), "1,000 cash + 2 paper")
	assert_eq(CivilianCatalog.training_cost_text("merchant"), "2,000 cash + 4 paper")


func test_unknown_types_fall_back_to_a_known_row() -> void:
	assert_false(CivilianCatalog.known("privateer"))
	assert_true(CivilianCatalog.known(CivilianCatalog.normalize("privateer")))
	assert_eq(CivilianCatalog.normalize("privateer"), CivilianCatalog.DEFAULT_TYPE)
