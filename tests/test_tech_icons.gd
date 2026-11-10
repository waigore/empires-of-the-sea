extends GdToolsTest
## Every tech carries a series medallion, and every plate ships (REQ-P1-02;
## tools/art/tech-medallions.md).


func test_every_catalog_tech_names_a_series() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.series_of(tech_id).is_empty():
			missing.append(tech_id)
	assert_eq(missing.size(), 0, "techs without a plate: %s" % ", ".join(missing))


func test_every_series_ships_a_texture() -> void:
	var missing: Array[String] = []
	for tech_id: String in TechCatalog.ids():
		if TechIcons.texture(tech_id) == null:
			missing.append(TechIcons.series_of(tech_id))
	assert_eq(missing.size(), 0, "plates missing from assets/art/tech: %s" % ", ".join(missing))


func test_a_chain_shares_one_plate() -> void:
	assert_eq(TechIcons.series_of("crop_rotation"), TechIcons.series_of("land_enclosure"))
	assert_eq(TechIcons.series_of("sugar_planting"), TechIcons.series_of("sugar_industry"))


func test_a_long_chain_may_grow_a_grander_plate() -> void:
	assert_ne(TechIcons.series_of("saw_mill"), TechIcons.series_of("circular_saw"))


func test_an_unknown_tech_has_no_plate() -> void:
	assert_eq(TechIcons.series_of("no_such_tech"), "")
	assert_null(TechIcons.texture("no_such_tech"))


func test_no_plate_is_listed_twice() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for tech_id: String in TechIcons.covered_ids():
		if seen.has(tech_id):
			clashes.append(tech_id)
		seen[tech_id] = true
	assert_eq(clashes.size(), 0, "techs claimed by two plates: %s" % ", ".join(clashes))
