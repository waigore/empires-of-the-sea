extends GdToolsTest
## Commodity catalog (wiki: commodity-catalog).

const MANUFACTURED_ROWS: Dictionary = {
	"lumber": 60,
	"fabric": 80,
	"castIron": 160,
	"refinedSugar": 70,
	"cigars": 80,
	"furHats": 110,
	"steel": 170,
	"paper": 60,
	"bronze": 145,
}


func test_catalog_covers_the_wiki_lists() -> void:
	assert_eq(CommodityCatalog.FOOD, ["grain", "meat"] as Array[String])
	assert_eq(CommodityCatalog.RAW.size(), 11)
	assert_eq(CommodityCatalog.MANUFACTURED.size(), 9)
	assert_eq(CommodityCatalog.LUXURY.size(), 0)
	assert_eq(CommodityCatalog.RICHES, ["gold", "silver", "gems", "diamonds"] as Array[String])
	assert_eq(CommodityCatalog.ADVANCED, ["spices"] as Array[String])
	assert_eq(CommodityCatalog.all_ids().size(), 27)


func test_categories_match_the_table() -> void:
	assert_eq(CommodityCatalog.category_of("grain"), CommodityCatalog.Category.FOOD)
	assert_eq(CommodityCatalog.category_of("timber"), CommodityCatalog.Category.RAW)
	assert_eq(CommodityCatalog.category_of("castIron"), CommodityCatalog.Category.MANUFACTURED)
	assert_eq(CommodityCatalog.category_of("gold"), CommodityCatalog.Category.RICHES)
	assert_eq(CommodityCatalog.category_of("spices"), CommodityCatalog.Category.ADVANCED)
	assert_eq(CommodityCatalog.category_of("silk"), CommodityCatalog.NO_CATEGORY)
	assert_false(CommodityCatalog.known("silk"))
	assert_eq(CommodityCatalog.category_label(CommodityCatalog.Category.RAW), "Raw materials")


func test_tradeable_excludes_riches_and_spices() -> void:
	assert_true(CommodityCatalog.is_tradeable("timber"))
	assert_true(CommodityCatalog.is_tradeable("lumber"))
	assert_true(CommodityCatalog.is_tradeable("grain"))
	assert_false(CommodityCatalog.is_tradeable("gold"))
	assert_false(CommodityCatalog.is_tradeable("diamonds"))
	assert_false(CommodityCatalog.is_tradeable("spices"))
	assert_false(CommodityCatalog.is_tradeable("silk"))
	var tradeable: int = 0
	for id: String in CommodityCatalog.all_ids():
		if CommodityCatalog.is_tradeable(id):
			tradeable += 1
	assert_eq(tradeable, 22)


func test_manufactured_prices_are_break_even() -> void:
	for id: String in MANUFACTURED_ROWS.keys():
		assert_eq(CommodityCatalog.base_price(id), int(MANUFACTURED_ROWS[id]), id)


func test_raw_and_riches_prices_match_the_rules() -> void:
	assert_eq(CommodityCatalog.base_price("grain"), 50)
	assert_eq(CommodityCatalog.base_price("timber"), 30)
	assert_eq(CommodityCatalog.base_price("iron"), 80)
	assert_eq(CommodityCatalog.base_price("coal"), 90)
	assert_eq(CommodityCatalog.base_price("spices"), 50)
	assert_eq(CommodityCatalog.base_price("gold"), 166)
	assert_eq(CommodityCatalog.base_price("diamonds"), 500)
	assert_eq(CommodityCatalog.base_price("silk"), 0)


func test_labels_are_readable_and_stable() -> void:
	assert_eq(CommodityCatalog.label("grain"), "Grain")
	assert_eq(CommodityCatalog.label("castIron"), "Cast Iron")
	assert_eq(CommodityCatalog.label("sugarCane"), "Sugar Cane")
	assert_eq(CommodityCatalog.label("furHats"), "Fur Hats")


func test_ids_in_returns_a_copy_of_the_category() -> void:
	var food: Array[String] = CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD)
	assert_eq(food, ["grain", "meat"] as Array[String])
	food.append("silk")
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.FOOD).size(), 2)
	assert_eq(CommodityCatalog.ids_in(CommodityCatalog.Category.LUXURY).size(), 0)
