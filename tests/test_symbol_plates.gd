extends GdToolsTest
## One boot for the drawn plates: tech, commodity and unit icons and the map's
## symbol stamp.

## Merged from test_tech_icons, test_commodity_icons, test_unit_icons,
## test_map_symbols.
## One Godot boot (coverage instrumentation) per theme instead of one per file.
## Each test runs only its own suite's setup; teardown follows the setup.

const KINDS: Array[String] = [
	"mountain", "hill", "tree", "scrub", "dune", "reed", "grass", "field",
	"port", "capital", "town",
]

# --- test_tech_icons ---

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

# --- test_commodity_icons ---

func test_every_catalog_commodity_ships_a_medallion() -> void:
	var missing: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if CommodityIcons.texture(id) == null:
			missing.append(id)
	assert_eq(missing.size(), 0, "goods with no plate: %s" % ", ".join(missing))

func test_two_goods_never_share_one_plate() -> void:
	var seen: Dictionary = {}
	var clashes: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		var art: Texture2D = CommodityIcons.texture(id)
		if art == null:
			continue
		if seen.has(art.resource_path):
			clashes.append("%s/%s" % [seen[art.resource_path], id])
		seen[art.resource_path] = id
	assert_eq(clashes.size(), 0, "goods sharing a plate: %s" % ", ".join(clashes))

func test_an_unknown_good_has_no_plate() -> void:
	assert_null(CommodityIcons.texture("no_such_good"))
	assert_null(CommodityIcons.texture(""))

func test_a_badge_draws_the_good_at_the_row_size() -> void:
	var badge: Control = CommodityIcons.badge("grain")
	var art: TextureRect = badge as TextureRect
	assert_not_null(art, "a known good draws a texture")
	assert_eq(art.texture, CommodityIcons.texture("grain"))
	assert_eq(art.custom_minimum_size, Vector2(CommodityIcons.ROW_SIZE, CommodityIcons.ROW_SIZE))
	badge.free()

func test_a_missing_plate_leaves_a_gap_of_the_same_width() -> void:
	var gap: Control = CommodityIcons.badge("no_such_good", 18)
	assert_null(gap as TextureRect, "a missing plate is not a texture")
	assert_eq(gap.custom_minimum_size, Vector2(18, 18), "the row keeps its columns")
	gap.free()

func test_a_name_cell_keeps_the_column_width() -> void:
	var cell: HBoxContainer = CommodityIcons.cell("timber", 132.0)
	assert_eq(cell.custom_minimum_size.x, 132.0, "the cell owns the column width")
	var labels: Array[Node] = cell.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 1, "one label per cell")
	assert_eq((labels[0] as Label).text, CommodityCatalog.label("timber"))
	var art: Array[Node] = cell.find_children("*", "TextureRect", true, false)
	assert_eq(art.size(), 1, "the medallion rides inside the cell")
	assert_eq((art[0] as TextureRect).texture, CommodityIcons.texture("timber"))
	cell.free()

## The plate is 128 px so it survives the phone's 3× draw scale.
func test_a_plate_is_a_128_px_source() -> void:
	var art: Texture2D = CommodityIcons.texture("coal")
	assert_not_null(art)
	assert_eq(art.get_width(), 128)
	assert_eq(art.get_height(), 128)

# --- test_unit_icons ---

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

## The row widget wears the plate at its own size, mipmapped, and a missing
## plate leaves a gap of the same width so the row's columns do not shift.
func test_the_row_widget_draws_the_plate_it_is_given() -> void:
	var plate: Texture2D = ShipArt.medallion("frigate")
	var medallion: UnitMedallion = UnitMedallion.of_ship("frigate", 40.0)
	assert_eq(medallion.texture, plate)
	assert_eq(medallion.custom_minimum_size, Vector2(40.0, 40.0))
	assert_eq(medallion.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(medallion.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(medallion.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	add_child(medallion)
	medallion.queue_free()
	var bare := UnitMedallion.new(null, 20.0)
	assert_null(bare.texture)
	assert_eq(bare.custom_minimum_size, Vector2(20.0, 20.0), "an absent plate keeps its width")
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

# --- test_map_symbols ---

func test_every_planned_kind_has_a_painted_stamp() -> void:
	for kind: String in KINDS:
		var tex: Texture2D = MapSymbols.texture(kind)
		assert_not_null(tex, "%s has no painted stamp" % kind)
		assert_gt(tex.get_width(), 63, "%s is drawn from a downscaled source" % kind)

func test_unknown_kind_has_no_stamp() -> void:
	assert_null(MapSymbols.texture("nonesuch"))

## The stamp falls back to the ink vectors rather than drawing nothing.
func test_stamp_refuses_a_kind_it_has_no_art_for() -> void:
	assert_false(MapSymbols.stamp(_probe(), {"kind": "nonesuch", "position": Vector2.ZERO, "size": 20.0}))
	assert_false(MapSymbols.stamp(_probe(), {"kind": "tree", "position": Vector2.ZERO, "size": 0.0}))

## A scattered province uses more than one sprite, so a range is not one stamp.
func test_terrain_mountains_take_several_variants() -> void:
	var seen: Dictionary = {}
	for i in 40:
		var at := Vector2(float(i) * 37.0, float(i) * 91.0)
		seen[MapSymbols.texture("mountain", at)] = true
	assert_gt(seen.size(), 1, "a mountain range repeats one sprite")

func test_stamp_draws_a_scenery_mark() -> void:
	var drawn: bool = await _draw_mark({
		"kind": "tree", "position": Vector2(30, 30), "size": 18.0, "flip": true,
	})
	assert_true(drawn, "the painted stamp drew instead of falling back")

func test_stamp_draws_a_town() -> void:
	assert_true(await _draw_mark({"kind": "town", "position": Vector2(64, 64), "size": 20.0}))

## The capital flies its owner's pennant, and still draws when nobody holds it.
func test_capital_stamp_covers_owner_and_neutral() -> void:
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(90, 90), "size": 24.0, "owner": 2,
	}))
	assert_true(await _draw_mark({
		"kind": "capital", "position": Vector2(120, 120), "size": 24.0,
		"owner": MapModel.NO_ID,
	}))

func test_ship_uses_a_painted_hull() -> void:
	var tex: Texture2D = MapSymbols.texture("ship")
	assert_not_null(tex, "the fleet has no painted hull")
	assert_eq(tex.get_width(), 256)

func _probe() -> _StampProbe:
	return _StampProbe.new()

## Drawing is only legal inside `_draw`, so the probe's own draw runs the stamp
## and the test reads its result after a rendered frame.
func _draw_mark(glyph: Dictionary) -> bool:
	var probe := _probe()
	probe.name = "StampProbe"
	probe.glyph = glyph
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	var drawn: bool = probe.result
	probe.queue_free()
	return drawn

class _StampProbe:
	extends Node2D

	var glyph: Dictionary = {}
	var result: bool = false

	func _draw() -> void:
		result = MapSymbols.stamp(self, glyph)
