extends GdToolsTest
## Canonical ship catalog (wiki: ships-and-naval § Ship combat and cargo stats).

const ROSTER: Array[String] = [
	"carrack",
	"fluyte",
	"sloop",
	"trader",
	"galleon",
	"indiaman",
	"frigate",
	"raider",
	"ship_of_the_line",
	"clipper",
	"merchant_steamship",
	"ironclad",
]


func test_catalog_covers_the_whole_roster() -> void:
	assert_eq(ShipStats.STATS.size(), ROSTER.size())
	for ship_id: String in ROSTER:
		assert_true(ShipStats.known(ship_id), ship_id)


func test_frozen_merchant_rows_match_the_wiki() -> void:
	var carrack: Dictionary = ShipStats.entry("carrack")
	assert_eq(int(carrack["frp"]), 2)
	assert_eq(int(carrack["rng"]), 1)
	assert_eq(int(carrack["arm"]), 1)
	assert_eq(int(carrack["hull"]), 2)
	assert_eq(int(carrack["mv"]), 2)
	assert_eq(int(carrack["cargo"]), 3)
	var fluyte: Dictionary = ShipStats.entry("fluyte")
	assert_eq(int(fluyte["hull"]), 1)
	assert_eq(int(fluyte["flee"]), 3)
	assert_eq(int(fluyte["cargo"]), 4)


func test_line_and_steam_rows_match_the_wiki() -> void:
	var line: Dictionary = ShipStats.entry("ship_of_the_line")
	assert_eq(int(line["frp"]), 6)
	assert_eq(int(line["hull"]), 8)
	assert_eq(int(line["intercept"]), 2)
	var ironclad: Dictionary = ShipStats.entry("ironclad")
	assert_eq(int(ironclad["arm"]), 8)
	assert_eq(int(ironclad["cargo"]), 0)
	var steamer: Dictionary = ShipStats.entry("merchant_steamship")
	assert_eq(int(steamer["cargo"]), 9)
	assert_eq(int(steamer["arm"]), 3)


func test_role_split_and_cargo_holds() -> void:
	assert_true(ShipStats.is_warship("sloop"))
	assert_true(ShipStats.is_warship("ship_of_the_line"))
	assert_false(ShipStats.is_warship("galleon"))
	for ship_id: String in ROSTER:
		var cargo: int = int(ShipStats.entry(ship_id)["cargo"])
		if ShipStats.is_warship(ship_id):
			assert_eq(cargo, 0, ship_id)
		else:
			assert_gt(cargo, 0, ship_id)


func test_strength_weights_firepower_range_armour_and_speed() -> void:
	# carrack: 2*1.0 + 1*0.4 + 1*0.15 + 2*0.1
	assert_almost_eq(ShipStats.strength("carrack"), 2.75, 0.0001)
	# ironclad: 5 + 1.2 + 1.2 + 0.3
	assert_almost_eq(ShipStats.strength("ironclad"), 7.7, 0.0001)
	# sloop: 2 + 0.8 + 0.15 + 0.3
	assert_almost_eq(ShipStats.strength("sloop"), 3.25, 0.0001)


func test_durability_is_hull_times_armour_bonus() -> void:
	# HULL * (1 + ARM/10)
	assert_almost_eq(ShipStats.durability("carrack"), 2.2, 0.0001)
	assert_almost_eq(ShipStats.durability("ironclad"), 10.8, 0.0001)
	assert_almost_eq(ShipStats.durability("fluyte"), 1.1, 0.0001)


func test_unknown_types_fall_back_to_the_carrack() -> void:
	assert_false(ShipStats.known("dromon"))
	assert_eq(ShipStats.normalize("dromon"), "carrack")
	assert_eq(ShipStats.entry("dromon"), ShipStats.entry("carrack"))
	assert_almost_eq(ShipStats.strength("dromon"), 2.75, 0.0001)


func test_display_names_are_period_readable() -> void:
	assert_eq(ShipStats.display_name("ship_of_the_line"), "Ship of the Line")
	assert_eq(ShipStats.display_name("merchant_steamship"), "Merchant Steamship")
	assert_eq(ShipStats.display_name("dromon"), "Carrack")
