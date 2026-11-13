extends GdToolsTest
## Integration: the survey lens on the live map — toggle, key, work refresh,
## region swap and the hover line. Drawing is exercised by a rendered frame.

const Fixture = preload("res://tests/map_fixture.gd")

var _screen: MapScreen = null


func before_each() -> void:
	_screen = Fixture.attach_screen(self)


func after_each() -> void:
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null


func test_lens_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: ResourceLens = _screen.play.lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.toggle_lens(_screen.play)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_true(_screen.hud._lens_button.button_pressed)
	assert_gt(int(lens.survey["counts"]["estates"]), 0)
	assert_gt((lens.survey.get("routes", []) as Array).size(), 0, "the lens carries the roads")
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.toggle_lens(_screen.play)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud._lens_button.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_a_completed_estate_refreshes_the_survey() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Array = _owned_vacant(lens.survey)
	assert_false(found.is_empty())
	var entry: Dictionary = found[0]
	var row: Dictionary = found[1]
	var tile: Vector2i = row["tile"]
	var before: int = int(entry["counts"]["worked"])

	_screen.land_works.set_improvement(_screen.model, tile, 2)
	_screen.land_works.set_prospected(_screen.player_faction, _screen.model, tile)
	assert_true(
		_screen.civilian_layer.works_changed.is_connected(lens.refresh)
	)
	_screen.civilian_layer.refresh_works()

	var after: Dictionary = _entry(lens.survey, int(entry["id"]))
	assert_eq(int(after["counts"]["worked"]), before + 1)
	assert_eq(int(_row(after, tile)["level"]), 2)


func test_a_working_estate_animates_the_lens() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Array = _owned_vacant(lens.survey)
	assert_false(found.is_empty())
	var entry: Dictionary = found[0]
	var tile: Vector2i = (found[1] as Dictionary)["tile"]
	var unit: CivilianState = _screen.civilian_layer.add_unit(
		_screen.player_faction, "builder", tile
	)
	unit.start_work("build_improvement", tile, 2)
	_screen.civilian_layer.refresh_works()
	assert_true(lens._animating)
	var row: Dictionary = _row(_entry(lens.survey, int(entry["id"])), tile)
	assert_eq(String(row["status"]), "building")
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame


func test_region_switch_rebuilds_the_lens() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.lens.model, _screen.model)
	assert_eq(int(_screen.play.lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(_screen.play.lens.survey.has("counts"))


func test_hover_reports_the_estate_line_while_the_lens_is_on() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var entry: Dictionary = _visible_entry(_screen.play.lens.survey)
	assert_false(entry.is_empty())
	var world: Vector2 = Vector2(entry["center"]) * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_true(_screen.hud._tooltip_label.text.contains("\n"))
	assert_true(_screen.hud._tooltip_label.text.contains(String(entry["summary"])))
	assert_eq(_screen.play.lens.hover_province, int(entry["id"]))
	MapPlayInput.clear_hover(_screen.play)
	assert_eq(_screen.play.lens.hover_province, -1)


func test_plates_are_packed_without_overlap_and_anchor_on_land() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var rects: Dictionary = lens._rects
	assert_false(rects.is_empty())
	var ids: Array = rects.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			assert_false((rects[ids[i]] as Rect2).intersects(rects[ids[j]]))
	assert_eq(lens.hit_test((rects[ids[0]] as Rect2).get_center()), int(ids[0]))
	assert_eq(lens.hit_test(Vector2(-9999, -9999)), -1)
	for raw: Variant in lens.survey["provinces"]:
		var anchor: Vector2 = (raw as Dictionary)["anchor"]
		assert_true(_screen.model.is_land(int(anchor.x), int(anchor.y)))


func test_tapping_a_plate_selects_its_province() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	for raw: Variant in lens.survey["provinces"]:
		var id: int = int((raw as Dictionary)["id"])
		var point: Vector2 = (lens._rects[id] as Rect2).get_center()
		if _screen.civilian_layer.unit_at(point) != null:
			continue
		if _screen.army_layer.army_at(point) != null:
			continue
		MapPlayInput.on_tapped(_screen.play, point)
		assert_eq(_screen.selected_province, id)
		return
	assert_true(false, "no clear survey plaque to tap")


func test_summary_for_an_unsurveyed_province_is_empty() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	assert_eq(_screen.play.lens.summary_for(9999), "")


func test_road_ink_draws_linked_cut_rail_and_fogged_strokes() -> void:
	var probe := _RoadInkProbe.new()
	probe.font = UiTheme.serif()
	probe.segments = [
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": true},
		{
			"a": Vector2i(1, 2),
			"b": Vector2i(2, 2),
			"linked": false,
			"rail": false,
			"fogged": true,
		},
	]
	probe.links = [
		{"counts": {"developed": 0, "linked": 0}, "origin": Vector2.ZERO},
		{"counts": {"developed": 2, "linked": 2}, "origin": Vector2(0, 12)},
		{"counts": {"developed": 2, "linked": 1}, "origin": Vector2(0, 24)},
		{"counts": {"developed": 2, "linked": 0}, "origin": Vector2(0, 36)},
	]
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	assert_eq(probe.segments.size(), 3)
	probe.queue_free()


func test_an_unsurveyed_province_draws_its_survey_ring() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Dictionary = {}
	for raw: Variant in lens.survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry.get("unsurveyed", 0)) > 0:
			found = entry
			break
	if found.is_empty():
		return
	assert_true(String(found["summary"]).contains("unsurveyed"))
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame


## Every resource kind owns its commodity ink, so the lens never paints a coin,
## a sheaf, a stone and a tree the same hue (REQ-P1-08).
func test_each_resource_kind_owns_a_distinct_commodity_ink() -> void:
	var seen: Array[Color] = []
	for kind: String in ["tree", "ore", "coin", "wheat"]:
		var ink: Color = Palette.resource_ink(kind)
		assert_false(seen.has(ink), "%s must not borrow another kind's ink" % kind)
		seen.append(ink)
	assert_ne(Palette.resource_ink("coin"), Palette.GOLD, "coined gold is its own gold")
	assert_eq(
		Palette.resource_ink("cartload"), Palette.GOLD,
		"an unknown kind keeps the old gold mark (REQ-P3-02)"
	)


## Status inks ring the emblem and never repaint its fill; only a foreign
## holding dims the commodity, and the hue still reads through the grey.
func test_status_ink_rings_the_emblem_without_erasing_the_commodity() -> void:
	for status: String in ["producing", "maxed", "vacant", "building", "disconnected"]:
		assert_eq(
			Palette.emblem_ink("wheat", status), Palette.resource_ink("wheat"),
			"%s must not repaint the sheaf" % status
		)
	var iron: Color = Palette.emblem_ink("ore", "foreign")
	assert_ne(iron, Palette.resource_ink("ore"), "a foreign holding still dims the mark")
	assert_ne(iron, Palette.SURVEY_FOREIGN, "and never wipes the kind to plain grey")
	var straw: Color = Palette.emblem_ink("wheat", "foreign_worked")
	assert_gt(straw.r, iron.r, "straw stays warmer than iron under the same tint")
	assert_gt(iron.b, straw.b, "iron stays cooler than straw under the same tint")


func test_all_four_emblems_draw_in_their_commodity_ink() -> void:
	var probe := _EmblemProbe.new()
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	assert_eq(probe.kinds.size(), 4)
	probe.queue_free()


## Drawing is only legal inside `_draw`; the probe hosts every emblem for
## coverage of the four inks (the lens only shows the kinds a chart seeds).
class _EmblemProbe extends Node2D:
	var kinds: Array[String] = ["tree", "ore", "coin", "wheat"]

	func _draw() -> void:
		for i in kinds.size():
			MapGlyphs.resource(
				self, kinds[i], Vector2(float(i) * 20.0, 0), 14.0,
				Palette.resource_ink(kinds[i])
			)


## Drawing is only legal inside `_draw`; the probe hosts the ink for coverage.
class _RoadInkProbe extends Node2D:
	var font: Font = null
	var segments: Array = []
	var links: Array = []

	func _draw() -> void:
		RoadInk.draw_routes(self, segments, 1.0)
		for raw: Variant in links:
			var link: Dictionary = raw
			RoadInk.draw_link(
				self, font, link["counts"], link["origin"], 40.0, 1.0
			)


# --- helpers -----------------------------------------------------------------


func _entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func _row(entry: Dictionary, tile: Vector2i) -> Dictionary:
	for raw: Variant in entry.get("rows", []):
		var row: Dictionary = raw
		if row["tile"] == tile:
			return row
	return {}


func _owned_vacant(survey: Dictionary) -> Array:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		for raw_row: Variant in entry["rows"]:
			var row: Dictionary = raw_row
			if bool(row["ours"]) and int(row["level"]) == 0:
				return [entry, row]
	return []


func _visible_entry(survey: Dictionary) -> Dictionary:
	for raw: Variant in survey["provinces"]:
		var entry: Dictionary = raw
		var center: Vector2 = entry["center"]
		var tile := Vector2i(int(center.x), int(center.y))
		if (
			_screen.visibility != null
			and _screen.visibility.level_at(tile.x, tile.y) != VisibilityModel.Level.UNKNOWN
		):
			return entry
	return {}
