extends GdToolsTest
## Every unit type carries its own medallion plate, cut on the shell's brass
## frame (REQ-P1-02, REQ-P4-04; tools/art/unit-medallions.md).


func test_every_worker_type_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in CivilianCatalog.ORDER:
		if CivilianArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "workers without a plate: %s" % ", ".join(missing))


func test_every_hull_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: Variant in ShipStats.STATS.keys():
		if ShipArt.medallion(String(type_id)) == null:
			missing.append(String(type_id))
	assert_eq(missing.size(), 0, "hulls without a plate: %s" % ", ".join(missing))


func test_every_regiment_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for type_id: String in RegimentCatalog.ids():
		if RegimentArt.medallion(type_id) == null:
			missing.append(type_id)
	assert_eq(missing.size(), 0, "regiments without a plate: %s" % ", ".join(missing))


## Unique icons, not one plate reused under several names: every type resolves
## a file of its own.
func test_no_two_types_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for type_id: String in _every_type():
		var texture: Texture2D = _plate(type_id)
		var path: String = texture.resource_path if texture != null else ""
		if seen.has(path):
			clashes.append("%s = %s" % [type_id, String(seen[path])])
		seen[path] = type_id
	assert_eq(clashes.size(), 0, "types sharing a plate: %s" % ", ".join(clashes))


func test_an_unknown_hull_falls_back_to_the_default_plate() -> void:
	assert_eq(
		ShipArt.medallion("no_such_hull").resource_path,
		ShipArt.medallion(ShipStats.DEFAULT_TYPE).resource_path
	)
	assert_eq(
		RegimentArt.medallion("no_such_regiment").resource_path,
		RegimentArt.medallion(RegimentCatalog.DEFAULT_TYPE).resource_path
	)


func test_an_unknown_worker_has_no_plate() -> void:
	assert_null(CivilianArt.medallion("no_such_worker"))


## The row widget draws the plate at its own size, and a missing plate leaves a
## pale disc so a roster row never collapses.
func test_the_row_widget_draws_the_plate_it_is_given() -> void:
	var plate: Texture2D = ShipArt.medallion("frigate")
	var medallion: UnitMedallion = UnitMedallion.of_ship("frigate", 40.0)
	assert_eq(medallion.texture, plate)
	assert_eq(medallion.custom_minimum_size, Vector2(40.0, 40.0))
	assert_eq(medallion.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	add_child(medallion)
	medallion.queue_free()
	var bare := UnitMedallion.new(null, 20.0)
	assert_null(bare.texture)
	add_child(bare)
	bare.queue_free()


func test_a_regiment_medallion_names_its_own_type() -> void:
	var medallion: UnitMedallion = UnitMedallion.of_regiment("grenadiers")
	assert_eq(medallion.texture, RegimentArt.medallion("grenadiers"))
	assert_eq(medallion.custom_minimum_size, Vector2(28.0, 28.0))


func _every_type() -> Array[String]:
	var all: Array[String] = []
	all.append_array(CivilianCatalog.ORDER)
	for type_id: Variant in ShipStats.STATS.keys():
		all.append(String(type_id))
	all.append_array(RegimentCatalog.ids())
	return all


func _plate(type_id: String) -> Texture2D:
	if CivilianCatalog.known(type_id):
		return CivilianArt.medallion(type_id)
	if ShipStats.known(type_id):
		return ShipArt.medallion(type_id)
	return RegimentArt.medallion(type_id)
