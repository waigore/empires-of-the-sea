# gdlint: disable=max-public-methods
extends GdToolsTest
## Integration: the map's four readings on the live map — the survey lens (L), the
## political wash (P), the crown road lens and the defence reading (K): toggle,
## key, mutual exclusion, repaint on the signal, slip taps and the hover line.
## The defence projection that feeds the military reading runs here too, on a
## four-province chart of its own.
##
## Merged from test_resource_lens, test_diplomacy_lens and test_defence_lens: one
## Godot boot pays one coverage instrumentation pass instead of three (~11 s a
## suite under coverage).

const Fixture = preload("res://tests/map_fixture.gd")

## One mounted screen for the whole suite: under coverage a mount costs ~0.5 s
## and a re-seat from the pristine save ~0.15 s, so the cases share the chart
## and reset the session instead of remounting (`Fixture.suite_reset`).
var mounted: MapScreen = null
var pristine: Dictionary = {}
var pristine_map: Array = []
var _screen: MapScreen = null


func before_all() -> void:
	pristine_map = Fixture.snapshot(Fixture.world())
	mounted = Fixture.attach_screen(self)
	pristine = Fixture.suite_capture(mounted)


func before_each() -> void:
	Fixture.restore(Fixture.world(), pristine_map)
	Fixture.suite_reset(mounted, pristine)
	_screen = mounted


func after_all() -> void:
	if is_instance_valid(mounted):
		mounted.free()
	mounted = null
	_screen = null
	pristine = {}


## --- the survey lens (L) -----------------------------------------------------


func test_lens_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: ResourceLens = _screen.play.lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.set_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SURVEY)
	assert_gt(int(lens.survey["counts"]["estates"]), 0)
	assert_gt((lens.survey.get("routes", []) as Array).size(), 0, "the lens carries the roads")
	assert_eq(
		(lens._runs as Array).size(), RoadInk.ink_paths(lens.survey["routes"]).size(),
		"the lens bakes the road ink once, from the same segments"
	)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
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


func test_region_switch_rebuilds_the_survey_lens() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.lens.model, _screen.model)
	assert_eq(int(_screen.play.lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(_screen.play.lens.survey.has("counts"))


func test_hover_reports_the_estate_line_while_the_lens_is_on() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var entry: Dictionary = _visible_estate_entry(_screen.play.lens.survey)
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
	# Each reading takes a turn as well as a straight, so the sleeper and dash
	# walks are exercised over a bend and not only a single chord.
	probe.segments = [
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": true},
		{"a": Vector2i(3, 1), "b": Vector2i(3, 2), "linked": true, "rail": true},
		{
			"a": Vector2i(1, 2),
			"b": Vector2i(2, 2),
			"linked": false,
			"rail": false,
			"fogged": true,
		},
		{
			"a": Vector2i(2, 2),
			"b": Vector2i(2, 3),
			"linked": false,
			"rail": false,
			"fogged": true,
		},
	]
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	assert_eq(probe.segments.size(), 5)
	probe.queue_free()


## A road that turns is one inked curve, not two tile-centre chords: the corner
## is cut, so the stroke never passes through the grid vertex (REQ-P1-03).
func test_a_turning_road_inks_as_one_curve_with_a_cut_corner() -> void:
	var runs: Array[Dictionary] = RoadInk.ink_paths([
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(2, 2), "linked": true, "rail": false},
	])
	assert_eq(runs.size(), 1, "a linked turn is one run, not one stroke a tile")
	var points: PackedVector2Array = runs[0]["points"]
	assert_gt(points.size(), 4, "the corner is subdivided, not a hard vertex")
	var corner: Vector2 = MapGeo.tile_center(2, 1, RoadInk.TILE_SIZE)
	var nearest: float = INF
	for point: Vector2 in points:
		nearest = minf(nearest, point.distance_to(corner))
	assert_gt(nearest, 1.5, "the stroke cuts the corner instead of touching the vertex")


## A long straight run bows off the tile-centre line, so the network does not
## read as a ruled grid (REQ-P1-03).
func test_a_straight_road_bows_off_the_tile_centres() -> void:
	var runs: Array[Dictionary] = RoadInk.ink_paths([
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": false},
		{"a": Vector2i(3, 1), "b": Vector2i(4, 1), "linked": true, "rail": false},
	])
	assert_eq(runs.size(), 1)
	var points: PackedVector2Array = runs[0]["points"]
	var a: Vector2 = MapGeo.tile_center(1, 1, RoadInk.TILE_SIZE)
	var b: Vector2 = MapGeo.tile_center(4, 1, RoadInk.TILE_SIZE)
	var bow: float = 0.0
	for point: Vector2 in points:
		bow = maxf(bow, absf((b - a).cross(point - a) / a.distance_to(b)))
	assert_gt(bow, 0.3, "the stroke bows off the straight chord")
	assert_lt(bow, 3.0, "and stays on its own tiles")


## Two runs of different readings still meet at the tile centre they share, so a
## road never breaks where a railroad begins.
func test_runs_of_different_readings_still_meet_at_a_junction() -> void:
	var runs: Array[Dictionary] = RoadInk.ink_paths([
		{"a": Vector2i(1, 1), "b": Vector2i(2, 1), "linked": true, "rail": false},
		{"a": Vector2i(2, 1), "b": Vector2i(3, 1), "linked": true, "rail": true},
	])
	assert_eq(runs.size(), 2, "a road and a railroad keep their own strokes")
	var road: PackedVector2Array = runs[0]["points"]
	var rail: PackedVector2Array = runs[1]["points"]
	assert_almost_eq(road[road.size() - 1].distance_to(rail[0]), 0.0, 0.01)


## Ground still to read is a count on the plate, so a province says how many
## tiles an Explorer could prospect instead of only that some exist (#698).
func test_an_unsurveyed_province_carries_its_prospect_count() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var found: Dictionary = _first_with_ground(lens)
	if found.is_empty():
		return
	assert_true(String(found["summary"]).contains("unsurveyed"))
	var plain: float = (
		ResourceLens.PLATE_PAD * 2.0 + ResourceLens.RIBBON
		+ float((found["types"] as Array).size()) * ResourceLens.TYPE_COL
	)
	assert_almost_eq(lens._plate_size(found).x, plain + ResourceLens.CUE_W, 0.01)
	found["unsurveyed"] = 0
	assert_almost_eq(lens._plate_size(found).x, plain, 0.01, "no ground, no cue column")
	found["unsurveyed"] = 1
	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame


## The plate draws a column per type in every estate state, the badge inks amber
## when a kind is only partly linked, and the key names the Explorer cue.
func test_a_plate_draws_every_type_state_and_the_explorer_cue() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	var lens: ResourceLens = _screen.play.lens
	var first: Dictionary = _crafted_plate(
		1, ["producing", "vacant", "foreign", "disconnected"], 3
	)
	var second: Dictionary = _crafted_plate(2, ["building", "maxed", "producing", "vacant"])
	# One kind, one estate cut off: the reading a single-estate column never makes.
	var third: Dictionary = _crafted_plate(3, ["producing", "disconnected"], 0, "tree")
	var saved: Dictionary = lens.survey
	lens._reveal = 1.0
	lens.survey = {"provinces": [first, second, third], "counts": {}, "routes": []}
	lens._layout_plates()
	lens.queue_redraw()
	await get_tree().process_frame
	assert_eq((lens._plate_rect(first).size as Vector2).y, ResourceLens.PLATE_H)
	assert_eq(String(first["types"][0]["status"]), "producing")
	assert_eq(String(second["types"][0]["status"]), "building")
	assert_eq(String(third["types"][0]["badge"]), "2/1/2", "one of the two is cut off")
	lens.survey = saved
	lens.refresh()
	var key: LensLegend = _screen.hud.lens_legend
	assert_true(key.is_survey())
	var named: bool = false
	for row: Dictionary in LensLegend.SURVEY_ROWS:
		if String(row["status"]) == "survey":
			named = String(row["text"]).contains("Explorer")
	assert_true(named, "the key still says an Explorer reads the ground")
	key.queue_redraw()
	await get_tree().process_frame


## The first plate with ground still to read (empty when the chart is read).
func _first_with_ground(lens: ResourceLens) -> Dictionary:
	for raw: Variant in lens.survey.get("provinces", []):
		if int((raw as Dictionary).get("unsurveyed", 0)) > 0:
			return raw
	return {}


## A plate holding one estate of every kind in the states a case asks for.
## `kind` pins every row to one emblem so a case can build a multi-estate column.
func _crafted_plate(
	province_id: int, statuses: Array, unsurveyed: int = 0, kind: String = ""
) -> Dictionary:
	var rows: Array[Dictionary] = []
	for i in statuses.size():
		var icon: String = kind if not kind.is_empty() else (
			ResourceTypes.ORDER[i % ResourceTypes.ORDER.size()]
		)
		rows.append(_crafted_row(icon, String(statuses[i]), i))
	var entry: Dictionary = {
		"id": province_id, "name": "Fixture", "center": Vector2(6, 6),
		"anchor": Vector2(6, 6), "owner": _screen.player_faction, "capital": false,
		"charted": VisibilityModel.Level.FULLY_VISIBLE, "rows": rows,
		"counts": {}, "output": {}, "output_text": "", "tile_owners": [],
		"unsurveyed": unsurveyed,
	}
	entry["types"] = ResourceTypes.rows(entry)
	entry["summary"] = ResourceSurvey.summary_text(entry)
	return entry


## One crafted estate row in the state a case asks for.
func _crafted_row(kind: String, status: String, index: int) -> Dictionary:
	var maxed: bool = status == "maxed"
	return {
		"icon": kind, "ours": status != "foreign", "status": status,
		"level": ImprovementCatalog.MAX_LEVEL if maxed else (
			1 if status in ["producing", "disconnected"] else 0
		),
		"connected": status != "disconnected", "tile": Vector2i(index, index),
		"commodity": "timber",
	}


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
	var segments: Array = []

	func _draw() -> void:
		RoadInk.draw_routes(self, segments, 1.0)


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


func _visible_estate_entry(survey: Dictionary) -> Dictionary:
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


## --- the political wash (P) --------------------------------------------------


func test_toggle_raises_the_key_and_builds_a_survey() -> void:
	var lens: DiplomacyLens = _screen.play.diplomacy_lens
	assert_not_null(lens)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DIPLOMACY)
	assert_gt(int(lens.survey["tiles"]["self"]), 0)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_diplomacy_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


## The two lenses are readings of the same map: raising one lowers the other,
## so the key can never show two legends at once.
func test_the_two_lenses_are_exclusive() -> void:
	MapPlayInput.set_lens(_screen.play, true)
	assert_true(_screen.play.lens.active)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SURVEY)

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	assert_false(_screen.play.lens.active)
	assert_true(_screen.play.diplomacy_lens.active)
	assert_true(_screen.hud.lens_seal.button_pressed, "the one seal stays raised")
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DIPLOMACY)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DIPLOMACY)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	MapPlayInput.set_lens(_screen.play, true)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SURVEY)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SURVEY)


func test_a_declaration_of_war_repaints_the_wash() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var owner: int = _foreign_owner()
	assert_true(owner >= 0)
	var relation: DiplomacyRelation = _screen.play.diplomacy.ensure_relation(
		_screen.player_faction, owner, _screen.play.turn
	)
	relation.set_score(50.0)
	MapPlaySetup.build_diplomacy_lens(_screen.play)
	assert_eq(
		DiplomacySurvey.band_for(
			_screen.play.diplomacy, _screen.player_faction, owner
		),
		DiplomacySurvey.BAND_NEUTRAL
	)

	relation.at_war = true
	relation.normalize()
	MapPlaySetup.build_diplomacy_lens(_screen.play)
	var entry: Dictionary = _entry(_screen.play.diplomacy_lens.survey, _province_of(owner))
	assert_eq(String(entry["band"]), DiplomacySurvey.BAND_WAR)
	assert_gt(int(_screen.play.diplomacy_lens.survey["tiles"]["war"]), 0)


func test_region_switch_rebuilds_the_political_wash() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	_screen._cycle_region()
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_eq(int(_screen.play.diplomacy_lens.model.region_id), FactionCatalog.NEW_WORLD)
	assert_true(_screen.play.diplomacy_lens.survey.has("runs"))
	# The New World starts unknown, so the wash paints nothing yet.
	assert_eq(int(_screen.play.diplomacy_lens.survey["counts"]["neutral"]), 0)

	# Charting one province makes it readable as neutral (no court yet).
	var province: ProvinceState = _screen.model.provinces[0]
	_screen.visibility.reveal_province(province.id)
	MapPlaySetup.build_diplomacy_lens(_screen.play)
	assert_false(
		_entry(_screen.play.diplomacy_lens.survey, province.id).is_empty()
	)


func test_hover_reports_the_standing_while_the_lens_is_on() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var entry: Dictionary = _visible_band_entry(_screen.play.diplomacy_lens.survey)
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var world: Vector2 = province.center * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	var screen_point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, screen_point)
	assert_true(_screen.hud._tooltip_label.text.contains("Standing: "))
	assert_true(_screen.hud._tooltip_label.text.contains(String(entry["standing"])))


## Raising the lens must refresh a tooltip that is already open: a stationary
## cursor is the common case, and the pre-lens line has no standing.
func test_the_hover_line_appears_when_the_lens_is_raised() -> void:
	var entry: Dictionary = _visible_band_entry(
		DiplomacySurvey.snapshot(
			_screen.model, _screen.play.diplomacy, _screen.player_faction,
			_screen.visibility
		)
	)
	assert_false(entry.is_empty())
	var province: ProvinceState = _screen.model.province_data(int(entry["id"]))
	var point: Vector2 = _screen_point(province.center)
	MapPlayInput.update_hover(_screen.play, point)
	assert_false(_screen.hud._tooltip_label.text.contains("Standing:"))

	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(_screen.hud._tooltip_label.text.contains("Standing: "))


func test_the_key_action_binds_the_p_and_l_keys() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.DIPLOMACY_LENS))
	assert_true(InputMap.has_action(InputActions.LENS))
	assert_ne(InputActions.DIPLOMACY_LENS, InputActions.LENS)


## P toggles the political wash from the keyboard, like L does the survey.
func test_the_p_key_toggles_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	event.pressed = true
	_screen._unhandled_input(event)
	assert_false(_screen.play.diplomacy_lens.active)
	assert_false(_screen.hud.lens_legend.visible)


## A political map refresh (Join Empire) rebuilds the wash with the new owners.
func test_a_political_refresh_rebuilds_the_lens() -> void:
	MapPlayInput.set_diplomacy_lens(_screen.play, true)
	var before: int = int(_screen.play.diplomacy_lens.survey["tiles"]["self"])
	assert_gt(before, 0)
	_screen.refresh_political_map()
	assert_eq(_screen.play.diplomacy_lens.model, _screen.model)
	assert_eq(int(_screen.play.diplomacy_lens.survey["tiles"]["self"]), before)


# --- helpers -----------------------------------------------------------------


func _foreign_owner() -> int:
	for province: ProvinceState in _screen.model.provinces:
		if (
			province.owner != _screen.player_faction
			and province.owner != MapModel.NO_ID
		):
			return province.owner
	return MapModel.NO_ID


func _province_of(owner: int) -> int:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner == owner:
			return province.id
	return -1


func _visible_band_entry(survey: Dictionary) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["charted"]) != VisibilityModel.Level.UNKNOWN:
			return entry
	return {}


func _screen_point(world_in_tiles: Vector2) -> Vector2:
	var world: Vector2 = world_in_tiles * MapScreen.TILE_SIZE
	_screen.camera.focus_on(world, 0.8, true)
	_screen.camera._process(0.016)
	return CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)


## --- the defence reading (K) -------------------------------------------------


func test_the_key_action_binds_the_k_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.DEFENCE_LENS))
	assert_ne(InputActions.DEFENCE_LENS, InputActions.LENS)
	assert_ne(InputActions.DEFENCE_LENS, InputActions.DIPLOMACY_LENS)
	assert_ne(InputActions.DEFENCE_LENS, InputActions.CROWN_LENS)
	# The key still lands on the bar's one seal, which raises its reading.
	var event := InputEventAction.new()
	event.action = InputActions.DEFENCE_LENS
	event.pressed = true
	_screen.hud.lens_seal._shortcut_input(event)
	assert_true(_screen.play.defence_lens.active, "K names the defence reading")
	MapPlayInput.set_defence_lens(_screen.play, false)


func test_toggle_key_exclusivity_and_draw() -> void:
	var lens: DefenceLens = _screen.play.defence_lens
	assert_not_null(lens)
	assert_false(lens.active)

	MapPlayInput.set_defence_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DEFENCE)
	assert_gt((lens.survey["provinces"] as Array).size(), 0)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	# Every other reading lowers when this one is raised, and vice versa.
	MapPlayInput.set_lens(_screen.play, true)
	assert_true(_screen.play.lens.active)
	assert_false(lens.active)
	MapPlayInput.set_crown_lens(_screen.play, true)
	assert_true(_screen.play.crown_lens.active)
	assert_false(_screen.play.lens.active)
	MapPlayInput.set_defence_lens(_screen.play, true)
	assert_true(lens.active)
	assert_false(_screen.play.crown_lens.active)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_DEFENCE)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_defence_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_false(_screen.hud.lens_seal.button_pressed)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_the_reading_names_the_crown_garrison_and_its_wall() -> void:
	MapPlayInput.set_defence_lens(_screen.play, true)
	var lens: DefenceLens = _screen.play.defence_lens
	var province: ProvinceState = _crown_garrisoned()
	assert_true(province != null, "the crown keeps a garrison on the fixture map")
	var entry: Dictionary = _entry(lens.survey, province.id)
	assert_gt(int(entry["strength"]), 0)
	assert_gt(int(entry["regiments"]), 0)
	var summary: String = lens.summary_for(province.id)
	assert_true(summary.contains("strength"), summary)


## A march moves a garrison: the lens reads the roster again on the signal, not
## on a frame poll.
func test_a_roster_change_repaints_the_reading() -> void:
	MapPlayInput.set_defence_lens(_screen.play, true)
	var lens: DefenceLens = _screen.play.defence_lens
	var army: ArmyState = _first_army_with_regiments()
	assert_true(army != null)
	var before: int = int(_entry(lens.survey, army.province)["regiments"])
	army.remove_regiment(army.regiments[0])
	_screen.army_layer.army_moved.emit(army, {})
	var after: int = int(_entry(lens.survey, army.province)["regiments"])
	assert_eq(after, before - 1)


## A tap on a slip selects the province it belongs to, even when the slip was
## packed away from the province centre.
func test_a_tap_on_a_slip_selects_its_province() -> void:
	MapPlayInput.set_defence_lens(_screen.play, true)
	var lens: DefenceLens = _screen.play.defence_lens
	var province: ProvinceState = _unowned_slip()
	assert_true(province != null, "the fixture map offers a foreign slip")
	var rect: Rect2 = lens._rects[province.id]
	MapPlayInput.on_tapped(_screen.play, rect.get_center())
	assert_eq(_screen.play.selected_province, province.id)


func test_the_legend_carries_every_band() -> void:
	assert_eq(LensLegend.DEFENCE_ROWS.size(), DefenceSurvey.BANDS.size())
	_screen.hud.lens_legend.set_kind(LensLegend.KIND_DEFENCE)
	_screen.hud.lens_legend.queue_redraw()
	await get_tree().process_frame
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_DEFENCE)


## The hover line carries the reading, and only while the lens is up.
func test_hover_reports_the_defence_while_the_lens_is_on() -> void:
	var province: ProvinceState = _crown_garrisoned()
	assert_true(province != null)
	var world: Vector2 = province.center * MapScreen.TILE_SIZE
	var point: Vector2 = CameraMath.world_to_screen(
		_screen.camera.position, _screen.camera.zoom.x, world,
		_screen.camera.viewport_size()
	)
	MapPlayInput.update_hover(_screen.play, point)
	assert_false(_screen.hud._tooltip_label.text.contains("Defence:"))
	MapPlayInput.set_defence_lens(_screen.play, true)
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(_screen.hud._tooltip_label.text.contains("Defence: "))


# --- fixture helpers ---------------------------------------------------------


func _crown_garrisoned() -> ProvinceState:
	for province: ProvinceState in _screen.model.provinces:
		if province.owner != _screen.player_faction:
			continue
		if not _screen.army_layer.armies_in(province.id, _screen.player_faction).is_empty():
			return province
	return null


func _first_army_with_regiments() -> ArmyState:
	for raw: Variant in _screen.army_layer.regions.value(_screen.model.region_id, []):
		var army: ArmyState = raw
		if army.owner == _screen.player_faction and not army.regiments.is_empty():
			return army
	return null


## A charted province the crown does not own and keeps no unit in, so the tap
## can only resolve through the slip.
func _unowned_slip() -> ProvinceState:
	var lens: DefenceLens = _screen.play.defence_lens
	for province: ProvinceState in _screen.model.provinces:
		if province.owner == _screen.player_faction or not lens._rects.has(province.id):
			continue
		if _screen.army_layer.army_at(lens._rects[province.id].get_center()) != null:
			continue
		if _screen.civilian_layer.unit_at(lens._rects[province.id].get_center()) != null:
			continue
		return province
	return null

# --- defence_survey ---
## Defence projection for the military lens: a province is banded by its wall
## first and its garrison second, the garrison is the published order of battle
## (FPN + FPM, no medals and no wounds) of the province's owner, and ground the
## crown has not charted never reaches the reading.

const WIDTH: int = 12
const HEIGHT: int = 4
const PLAYER: int = FactionCatalog.PLAYER_FACTION
const RIVAL: int = 3

var _model: MapModel = null
var _armies: Array[ArmyState] = []


func _setup_defence_survey() -> void:
	_model = _build()
	_armies = []


## Four provinces, three columns each: the crown's open ground, a garrisoned
## province in the open, a rival's stone wall and the crown's modern citadel.
func _build() -> MapModel:
	var model := MapModel.new()
	model.setup(WIDTH, HEIGHT)
	var groups: Dictionary = {0: [], 1: [], 2: [], 3: []}
	for y in HEIGHT:
		for x in WIDTH:
			var sea: bool = y == HEIGHT - 1
			model.terrain[model.index_of(x, y)] = (
				MapModel.Terrain.OCEAN if sea else MapModel.Terrain.PLAINS
			)
			if sea:
				model.sea_zone[model.index_of(x, y)] = 0
				continue
			var province_id: int = mini(x / 3, 3)
			model.province[model.index_of(x, y)] = province_id
			(groups[province_id] as Array).append(Vector2i(x, y))
	var names: Array[String] = ["Sevilla", "Córdoba", "Évora", "Lisboa"]
	var owners: Array[int] = [PLAYER, PLAYER, RIVAL, PLAYER]
	var forts: Array[int] = [0, 0, 2, 3]
	var provinces: Array[ProvinceState] = []
	for province_id in 4:
		var tiles: Array[Vector2i] = []
		for raw: Variant in groups[province_id]:
			tiles.append(raw as Vector2i)
		var province := ProvinceState.create(
			province_id, names[province_id], tiles, Vector2(tiles[0]),
			tiles.size(), owners[province_id], province_id == 0
		)
		province.fort_level = forts[province_id]
		provinces.append(province)
	provinces[1].hospital_level = 1
	model.provinces = provinces
	return model


func _army(owner: int, province: int, types: Array[String]) -> ArmyState:
	var army: ArmyState = ArmyState.muster(
		_armies.size() + 1, owner, province, false, types, 1
	)
	_armies.append(army)
	return army


func _snapshot(visibility: VisibilityModel = null) -> Dictionary:
	return DefenceSurvey.snapshot(_model, _armies, visibility, PLAYER)


func defence_survey_entry(survey: Dictionary, province_id: int) -> Dictionary:
	for raw: Variant in survey.get("provinces", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == province_id:
			return entry
	return {}


func test_the_wall_outranks_the_garrison() -> void:
	_setup_defence_survey()
	assert_eq(DefenceSurvey.band_for(0, 0), DefenceSurvey.BAND_OPEN)
	assert_eq(DefenceSurvey.band_for(0, 3), DefenceSurvey.BAND_HELD)
	assert_eq(DefenceSurvey.band_for(1, 0), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(2, 4), DefenceSurvey.BAND_WALLED)
	assert_eq(DefenceSurvey.band_for(3, 0), DefenceSurvey.BAND_CITADEL)


func test_a_garrison_is_read_on_the_published_order_of_battle() -> void:
	_setup_defence_survey()
	var army: ArmyState = _army(PLAYER, 1, ["musketeers", "pikemen"])
	# Chevrons and wounds are the crown's own reading, not the published one.
	army.regiment_medals["unit_1"] = 4
	army.regiment_health["unit_1"] = 10
	var survey: Dictionary = _snapshot()
	var held: Dictionary = defence_survey_entry(survey, 1)
	assert_eq(int(held["strength"]), 14, "9 + 5, with no medal multiplier")
	assert_eq(int(held["regiments"]), 2)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_HELD)
	assert_eq(int(held["hospital"]), 1)


func test_an_empty_province_reads_open_and_a_wall_reads_walled() -> void:
	_setup_defence_survey()
	_army(PLAYER, 3, ["guards"])
	var survey: Dictionary = _snapshot()
	assert_eq(String(defence_survey_entry(survey, 0)["band"]), DefenceSurvey.BAND_OPEN)
	assert_eq(int(defence_survey_entry(survey, 0)["strength"]), 0)
	var citadel: Dictionary = defence_survey_entry(survey, 3)
	assert_eq(String(citadel["band"]), DefenceSurvey.BAND_CITADEL)
	assert_eq(int(citadel["fort"]), 3)
	assert_eq(int(citadel["guns"]), 3)
	var rival: Dictionary = defence_survey_entry(survey, 2)
	assert_eq(String(rival["band"]), DefenceSurvey.BAND_WALLED)
	assert_eq(int(rival["guns"]), 2)


## The garrison is the owner's: a foreign host ashore is a contested ground,
## never part of the province's defence.
func test_a_foreign_host_is_flagged_and_never_counted_as_the_garrison() -> void:
	_setup_defence_survey()
	_army(PLAYER, 2, ["musketeers"])
	var rival: Dictionary = defence_survey_entry(_snapshot(), 2)
	assert_true(bool(rival["foreign"]))
	assert_eq(int(rival["strength"]), 0)
	assert_eq(int(rival["regiments"]), 0)


func test_counts_and_the_crown_totals() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers"])
	_army(PLAYER, 3, ["pikemen"])
	var survey: Dictionary = _snapshot()
	var counts: Dictionary = survey["counts"]
	assert_eq(int(counts[DefenceSurvey.BAND_OPEN]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_HELD]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_WALLED]), 1)
	assert_eq(int(counts[DefenceSurvey.BAND_CITADEL]), 1)
	var totals: Dictionary = survey["totals"]
	assert_eq(int(totals["provinces"]), 4)
	assert_eq(int(totals["undefended"]), 1, "Sevilla is the crown's only open province")
	assert_eq(int(totals["strength"]), 14, "9 + 5 over the crown's own garrisons")


func test_uncharted_ground_never_reaches_the_reading() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers"])
	var visibility := VisibilityModel.new()
	visibility.setup(_model, PLAYER)
	for tile: Vector2i in _model.provinces[0].tiles:
		visibility.lower_to(
			_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN
		)
	var survey: Dictionary = _snapshot(visibility)
	assert_true(defence_survey_entry(survey, 0).is_empty())
	assert_false(defence_survey_entry(survey, 1).is_empty())
	assert_eq(int(survey["totals"]["provinces"]), 3)


func test_the_hover_line_names_the_strength_the_wall_and_the_hospital() -> void:
	_setup_defence_survey()
	_army(PLAYER, 1, ["musketeers", "pikemen"])
	var held: Dictionary = defence_survey_entry(_snapshot(), 1)
	var text: String = DefenceSurvey.summary_text(held)
	assert_true(text.contains("14 strength"), text)
	assert_true(text.contains("2 regiments"), text)
	assert_true(text.contains("No wall"), text)
	assert_true(text.contains(HospitalRules.level_name(1)), text)
	var open_line: String = DefenceSurvey.summary_text(defence_survey_entry(_snapshot(), 0))
	assert_true(open_line.contains("No garrison"), open_line)
	assert_true(open_line.contains("No wall"), open_line)


func test_one_regiment_and_one_gun_read_in_the_singular() -> void:
	_setup_defence_survey()
	_army(PLAYER, 3, ["guards"])
	var text: String = DefenceSurvey.summary_text(defence_survey_entry(_snapshot(), 3))
	assert_true(text.contains("22 strength · 1 regiment"), text)
	assert_true(text.contains("Fort 3 (3 guns)"), text)


func test_an_embarked_army_defends_nothing() -> void:
	_setup_defence_survey()
	var army: ArmyState = _army(PLAYER, 1, ["musketeers"])
	army.embarked_fleet = 7
	var held: Dictionary = defence_survey_entry(_snapshot(), 1)
	assert_eq(int(held["strength"]), 0)
	assert_eq(String(held["band"]), DefenceSurvey.BAND_OPEN)


## --- the sea reading (H) -----------------------------------------------------


func test_the_key_action_binds_the_h_key() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.SEA_LENS))
	assert_ne(InputActions.SEA_LENS, InputActions.LENS)
	assert_ne(InputActions.SEA_LENS, InputActions.DEFENCE_LENS)
	# The key lands on the bar's one seal, which raises its reading.
	var event := InputEventAction.new()
	event.action = InputActions.SEA_LENS
	event.pressed = true
	_screen.hud.lens_seal._shortcut_input(event)
	assert_true(_screen.play.sea_lens.active, "H names the sea reading")
	MapPlayInput.set_sea_lens(_screen.play, false)


func test_the_sea_reading_raises_its_key_and_survey() -> void:
	var lens: SeaLens = _screen.play.sea_lens
	assert_not_null(lens, "the chart mounts the sea lens")
	_sail_a_crown_squadron()
	MapPlaySetup.build_lens(_screen.play)
	assert_false(lens.active)

	MapPlayInput.set_sea_lens(_screen.play, true)
	assert_true(lens.active)
	assert_true(_screen.hud.lens_legend.visible)
	assert_eq(_screen.hud.lens_legend.kind, LensLegend.KIND_SEA)
	assert_true(_screen.hud.lens_seal.button_pressed)
	assert_eq(_screen.hud.lens_seal.active_kind, LensLegend.KIND_SEA)
	assert_gt((lens.survey["zones"] as Array).size(), 0, "a squadron at sea reads")
	assert_almost_eq(_screen.civilian_layer.modulate.a, 0.22, 0.001)

	# The readings never stack: a peer takes this one down and is taken down by it.
	MapPlayInput.set_defence_lens(_screen.play, true)
	assert_true(_screen.play.defence_lens.active)
	assert_false(lens.active)
	MapPlayInput.set_sea_lens(_screen.play, true)
	assert_true(lens.active)
	assert_false(_screen.play.defence_lens.active)

	lens._reveal = 1.0
	lens.queue_redraw()
	await get_tree().process_frame

	MapPlayInput.set_sea_lens(_screen.play, false)
	assert_false(lens.active)
	assert_false(_screen.hud.lens_legend.visible)
	assert_almost_eq(_screen.civilian_layer.modulate.a, 1.0, 0.001)


func test_a_sail_repaints_the_sea_reading() -> void:
	var fleet: FleetState = _sail_a_crown_squadron()
	MapPlaySetup.build_lens(_screen.play)
	var lens: SeaLens = _screen.play.sea_lens
	var before: int = fleet.sea_zone
	var next: int = _other_zone(before)
	var hulls: int = fleet.ship_count()
	var here: int = _own_hulls(lens.survey, before)
	var there: int = _own_hulls(lens.survey, next)
	assert_true(_has_zone(lens.survey, before), "the reading follows her water")
	fleet.sea_zone = next
	_screen.ship_layer.fleet_moved.emit(fleet, {})
	assert_true(_has_zone(lens.survey, next), "the new water is read")
	assert_eq(_own_hulls(lens.survey, next), there + hulls, "her hulls are counted there")
	assert_eq(_own_hulls(lens.survey, before), here - hulls, "and not where she was")


func test_hover_reports_the_sea_line_while_the_lens_is_on() -> void:
	var fleet: FleetState = _sail_a_crown_squadron()
	MapPlaySetup.build_lens(_screen.play)
	MapPlayInput.set_sea_lens(_screen.play, true)
	var zone: SeaZoneState = _screen.model.sea_zone_data(fleet.sea_zone)
	var point: Vector2 = _screen_point(Vector2(zone.tiles[0]))
	MapPlayInput.update_hover(_screen.play, point)
	assert_true(
		_screen.hud._tooltip_label.text.contains("Ours "),
		"the hover names the squadron: " + _screen.hud._tooltip_label.text
	)
	MapPlayInput.set_sea_lens(_screen.play, false)


## Puts a crown squadron at sea in the water beside its capital, so the reading
## has a sail to read.
func _sail_a_crown_squadron() -> FleetState:
	var capital: int = _screen.play.capital_province
	var zones: Array[int] = NavalMovement.province_sea_zones(_screen.model, capital)
	var zone: int = zones[0] if not zones.is_empty() else 0
	for raw: Variant in _screen.ship_layer.fleets:
		var fleet: FleetState = raw
		if fleet.owner != _screen.player_faction or fleet.ship_count() <= 0:
			continue
		fleet.location = FleetState.Location.AT_SEA
		fleet.sea_zone = zone
		fleet.province = MapModel.NO_ID
		fleet.mission = FleetState.Mission.PATROL
		return fleet
	return null


## Our hulls the reading counts in one zone.
func _own_hulls(survey: Dictionary, zone_id: int) -> int:
	for raw: Variant in survey.get("zones", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == zone_id:
			return int(entry["own_hulls"])
	return 0


func _has_zone(survey: Dictionary, zone_id: int) -> bool:
	for raw: Variant in survey.get("zones", []):
		if int((raw as Dictionary)["id"]) == zone_id:
			return true
	return false


func _other_zone(zone_id: int) -> int:
	for zone: SeaZoneState in _screen.model.sea_zones:
		if zone.id != zone_id:
			return zone.id
	return zone_id

# --- sea_survey ---
## Sea projection for the water reading: a zone is banded by who stands in it and
## whether they are at war, the fight is the resolver's own contested test, a
## rival the chart withholds or has not watched contributes nothing, and a
## harbour (a squadron in port) never reaches the reading.

const SEA_WIDTH: int = 12
const SEA_HEIGHT: int = 4
const SEA_PLAYER: int = FactionCatalog.PLAYER_FACTION
const SEA_RIVAL: int = 3
const SEA_OTHER: int = 4
const SEA_WEST: int = 0
const SEA_EAST: int = 1

var _sea_model: MapModel = null
var _sea_fleets: Array[FleetState] = []


func _setup_sea_survey() -> void:
	_sea_model = _build_sea()
	_sea_fleets = []


## Two sea zones under a strip of the crown's land: the west water and the east.
func _build_sea() -> MapModel:
	var model := MapModel.new()
	model.setup(SEA_WIDTH, SEA_HEIGHT)
	var west: Array[Vector2i] = []
	var east: Array[Vector2i] = []
	var land: Array[Vector2i] = []
	for y in SEA_HEIGHT:
		for x in SEA_WIDTH:
			var index: int = model.index_of(x, y)
			var tile := Vector2i(x, y)
			if y < SEA_HEIGHT - 2:
				model.terrain[index] = MapModel.Terrain.PLAINS
				model.province[index] = 0
				land.append(tile)
				continue
			model.terrain[index] = MapModel.Terrain.OCEAN
			var zone: int = SEA_WEST if x < SEA_WIDTH / 2 else SEA_EAST
			model.sea_zone[index] = zone
			if zone == SEA_WEST:
				west.append(tile)
			else:
				east.append(tile)
	var provinces: Array[ProvinceState] = []
	provinces.append(
		ProvinceState.create(
			0, "Sevilla", land, _sea_center(land), land.size(), SEA_PLAYER, true
		)
	)
	model.provinces = provinces
	model.sea_zones = [
		SeaZoneState.create(SEA_WEST, "Mar de Levante", west, _sea_center(west), west.size()),
		SeaZoneState.create(SEA_EAST, "Mar Océano", east, _sea_center(east), east.size()),
	]
	return model


func _sea_center(tiles: Array[Vector2i]) -> Vector2:
	var total := Vector2.ZERO
	for tile: Vector2i in tiles:
		total += Vector2(tile)
	return total / maxf(float(tiles.size()), 1.0)


func _fleet(owner: int, zone: int, types: Array[String]) -> FleetState:
	var hulls: Array[String] = []
	var catalog: Dictionary = {}
	for i in types.size():
		var hull_id: String = "ship_%d_%d" % [_sea_fleets.size() + 1, i]
		hulls.append(hull_id)
		catalog[hull_id] = types[i]
	var fleet: FleetState = FleetState.at_sea(
		_sea_fleets.size() + 1, owner, zone, hulls, catalog
	)
	_sea_fleets.append(fleet)
	return fleet


func _sea_snapshot(
	hostile: Callable = Callable(),
	view: Callable = Callable(),
	visibility: VisibilityModel = null
) -> Dictionary:
	return SeaSurvey.snapshot(_sea_model, _sea_fleets, visibility, SEA_PLAYER, hostile, view)


## Two courts at war with each other and with nobody else.
func _war_between(a: int, b: int) -> Callable:
	return func(left: int, right: int) -> bool:
		return (left == a and right == b) or (left == b and right == a)


func _nobody_is_hostile() -> Callable:
	return func(_a: int, _b: int) -> bool:
		return false


func sea_entry(survey: Dictionary, zone_id: int) -> Dictionary:
	for raw: Variant in survey.get("zones", []):
		var entry: Dictionary = raw
		if int(entry["id"]) == zone_id:
			return entry
	return {}


## The chart's answer for one squadron, the way `MapPlayFleets.view_filter` hands
## it in: a rival either drawn and read, drawn and unread, or not drawn at all.
func _view(drawn: bool, read: bool) -> Callable:
	return func(_fleet_in: FleetState) -> Dictionary:
		return {"drawn": drawn, "read": read}


func test_the_crowns_own_water_reads_quiet() -> void:
	_setup_sea_survey()
	var squadron: FleetState = _fleet(SEA_PLAYER, SEA_WEST, ["frigate", "carrack"])
	squadron.mission = FleetState.Mission.PATROL
	var entry: Dictionary = sea_entry(_sea_snapshot(), SEA_WEST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_QUIET)
	assert_eq(int(entry["own_hulls"]), 2)
	assert_gt(float(entry["own_strength"]), 0.0)
	assert_eq(String(entry["station_text"]), "Patrol")
	assert_false(bool(entry["fight"]))
	var text: String = SeaSurvey.summary_text(entry)
	assert_true(text.contains("Ours 1 squadron"), text)
	assert_true(text.contains("2 hulls"), text)
	assert_true(text.contains("Patrol"), text)


func test_a_rival_under_the_peace_reads_watched() -> void:
	_setup_sea_survey()
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	var entry: Dictionary = sea_entry(_sea_snapshot(_nobody_is_hostile()), SEA_EAST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_WATCHED)
	assert_false(bool(entry["fight"]))
	assert_eq(int(entry["foe_squadrons"]), 1)
	assert_eq(String((entry["foe_courts"] as Array)[0]), FactionCatalog.name_of(SEA_RIVAL))


## A hostile sail alone in a zone resolves no battle — a fight needs two sides —
## but the water is hers and the crown holds nothing there.
func test_a_hostile_sail_we_do_not_share_reads_standoff() -> void:
	_setup_sea_survey()
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	var entry: Dictionary = sea_entry(_sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL)), SEA_EAST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_STANDOFF)
	assert_false(bool(entry["fight"]), "no second side, so no battle")
	assert_eq(int(entry["own_hulls"]), 0)
	assert_true(SeaSurvey.summary_text(entry).contains("No sail of ours"))


func test_a_shared_zone_at_war_reads_contested_and_names_the_battle() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate", "galleon"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL), _view(true, true)),
		SEA_WEST
	)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_CONTESTED)
	assert_true(bool(entry["fight"]), "the resolver fights this zone")
	assert_true(bool(entry["own_engaged"]))
	assert_gt(float(entry["foe_strength"]), 0.0, "a read rival is weighed")
	assert_true(
		SeaSurvey.summary_text(entry).contains("a battle resolves here at turn end"),
		SeaSurvey.summary_text(entry)
	)


## An unread rival fights with nothing the crown can count: her figure is left
## out whole rather than printed short (wiki: ships-and-naval § Sighted strength).
func test_an_unread_rival_reads_blind_and_prints_no_weight() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL), _view(true, false)),
		SEA_WEST
	)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_BLIND)
	assert_true(bool(entry["fight"]), "she fights whether or not she is read")
	assert_eq(int(entry["foe_unread"]), 1)
	assert_almost_eq(float(entry["foe_strength"]), 0.0, 0.001)
	assert_true(SeaSurvey.summary_text(entry).contains("weight unread"))

## A rival the fog withholds is not the crown's to read: she adds no plaque, no
## hull and no fight to the water she stands in.
func test_a_withheld_rival_never_reaches_the_reading() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	var survey: Dictionary = _sea_snapshot(
		_war_between(SEA_PLAYER, SEA_RIVAL), _view(false, false)
	)
	var entry: Dictionary = sea_entry(survey, SEA_WEST)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_QUIET)
	assert_eq(int(entry["foe_squadrons"]), 0)
	assert_false(bool(entry["fight"]), "the crown sees no fight here to name")
	assert_eq(int(survey["totals"]["zones"]), 1, "only the water she can see")


## Two rivals at war in water the crown does not hold still fight at turn end;
## the reading says so without claiming the battle as ours.
func test_two_rivals_at_war_in_water_we_do_not_hold() -> void:
	_setup_sea_survey()
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	_fleet(SEA_OTHER, SEA_EAST, ["frigate"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_RIVAL, SEA_OTHER), _view(true, true)),
		SEA_EAST
	)
	assert_eq(String(entry["band"]), SeaSurvey.BAND_STANDOFF)
	assert_true(bool(entry["fight"]))
	assert_false(bool(entry["own_engaged"]), "no sail of ours is in it")
	assert_true(
		SeaSurvey.summary_text(entry).contains("two rivals fight here at turn end"),
		SeaSurvey.summary_text(entry)
	)


## Two rivals at war with each other, with a crown squadron standing in the same
## water at peace with both: the close fights the rivals and never the crown, so
## the reading must not claim that battle as ours (wiki: ships-and-naval § Naval
## Combat Resolution; DR-20261115-17 § Change — "the chart can never promise a
## battle the close would not strike").
func test_a_spectator_squadron_does_not_claim_a_rival_battle() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	_fleet(SEA_OTHER, SEA_WEST, ["frigate"])
	var entry: Dictionary = sea_entry(
		_sea_snapshot(_war_between(SEA_RIVAL, SEA_OTHER), _view(true, true)),
		SEA_WEST
	)
	assert_true(bool(entry["fight"]), "the rivals fight this zone")
	assert_false(bool(entry["own_engaged"]), "no hostile sail of ours shares the water")
	assert_eq(String(entry["band"]), SeaSurvey.BAND_WATCHED)
	assert_true(
		SeaSurvey.summary_text(entry).contains("two rivals fight here at turn end"),
		SeaSurvey.summary_text(entry)
	)


func test_a_squadron_in_port_reads_no_water() -> void:
	_setup_sea_survey()
	var moored: FleetState = FleetState.in_port(9, SEA_PLAYER, 0, ["ship_9"], {"ship_9": "frigate"})
	_sea_fleets.append(moored)
	var survey: Dictionary = _sea_snapshot()
	assert_eq((survey["zones"] as Array).size(), 0, "a harbour fights nothing")
	assert_eq(int(survey["totals"]["hulls"]), 0)


func test_sea_counts_and_the_crown_totals() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate", "frigate"])
	_fleet(SEA_RIVAL, SEA_WEST, ["frigate"])
	_fleet(SEA_PLAYER, SEA_EAST, ["frigate"])
	var survey: Dictionary = _sea_snapshot(_war_between(SEA_PLAYER, SEA_RIVAL), _view(true, true))
	assert_eq(int(survey["counts"][SeaSurvey.BAND_CONTESTED]), 1)
	assert_eq(int(survey["counts"][SeaSurvey.BAND_QUIET]), 1)
	assert_eq(int(survey["totals"]["zones"]), 2)
	assert_eq(int(survey["totals"]["hulls"]), 3, "our hulls only, never hers")
	assert_eq(int(survey["totals"]["contested"]), 1)
	assert_eq(int(survey["totals"]["blind"]), 0)


## The reading is remembered, not invented: charted water draws, and a plate
## anchors on the brightest water of its own zone. The crown's own sail is
## charted by definition — a fleet never floats in water it cannot read.
func test_the_zone_carries_the_chart_the_crown_holds() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	_fleet(SEA_RIVAL, SEA_EAST, ["frigate"])
	var visibility := VisibilityModel.new()
	visibility.setup(_sea_model, SEA_PLAYER)
	var survey: Dictionary = _sea_snapshot(
		_nobody_is_hostile(), _view(true, true), visibility
	)
	var entry: Dictionary = sea_entry(survey, SEA_WEST)
	assert_eq(int(entry["charted"]), VisibilityModel.Level.FULLY_VISIBLE, "our own water")
	var anchor: Vector2i = entry["anchor"]
	assert_eq(_sea_model.sea_zone_at(anchor.x, anchor.y), SEA_WEST, "the plate sits on its own water")
	for tile: Vector2i in _sea_model.sea_zone_data(SEA_EAST).tiles:
		visibility.lower_to(_sea_model.index_of(tile.x, tile.y), VisibilityModel.Level.UNKNOWN)
	assert_eq(
		int(sea_entry(_sea_snapshot(
			_nobody_is_hostile(), _view(true, true), visibility
		), SEA_EAST)["charted"]),
		VisibilityModel.Level.UNKNOWN,
		"water nobody charted is drawn at nothing"
	)


func test_one_hull_reads_in_the_singular() -> void:
	_setup_sea_survey()
	_fleet(SEA_PLAYER, SEA_WEST, ["frigate"])
	var text: String = SeaSurvey.summary_text(sea_entry(_sea_snapshot(), SEA_WEST))
	assert_true(text.contains("1 squadron"), text)
	assert_true(text.contains("1 hull"), text)
	assert_false(text.contains("1 hulls"), text)


func test_every_band_has_a_label_and_an_ink() -> void:
	var inks: Dictionary = {}
	for band: String in SeaSurvey.BANDS:
		assert_true(SeaSurvey.BAND_LABELS.has(band), "no label for " + band)
		inks[Palette.sea_color(band)] = band
	assert_eq(inks.size(), SeaSurvey.BANDS.size(), "each band owns its own ink")
	assert_eq(SeaSurvey.band_for(false, false, false, 0, false), SeaSurvey.BAND_QUIET)
	assert_eq(SeaSurvey.band_for(true, true, true, 0, true), SeaSurvey.BAND_CONTESTED)
	assert_eq(SeaSurvey.band_for(true, true, true, 1, true), SeaSurvey.BAND_BLIND)
	assert_eq(SeaSurvey.band_for(false, true, true, 0, false), SeaSurvey.BAND_STANDOFF)
	assert_eq(SeaSurvey.band_for(true, true, false, 0, false), SeaSurvey.BAND_WATCHED)
