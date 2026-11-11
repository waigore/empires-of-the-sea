extends GdToolsTest
## Province dossier: every estate the province holds (not just its headline
## resource), whether each is developed and whether it reaches the crown, the
## roads row's real meaning, the town order's gate and the discreet dock
## affordance every dossier shares (REQ-P1-02, REQ-P2-03).

const Fixture = preload("res://tests/civilian_fixture.gd")

## Beside the seat: a road reaches it and it yields.
const LINKED_TILE: Vector2i = Vector2i(1, 0)
## Beside the seat but never raised.
const VACANT_TILE: Vector2i = Vector2i(0, 1)
## Two tiles off the seat, diagonal: developed, but no path to the crown.
const OFF_ROAD_TILE: Vector2i = Vector2i(1, 1)

var _model: MapModel = null
var _works: LandWorks = null
var _units: Array[CivilianState] = []
var _panel: ProvincePanel = null


func before_each() -> void:
	_model = Fixture.build()
	_model.resource[_model.index_of(LINKED_TILE.x, LINKED_TILE.y)] = 0
	_model.resource[_model.index_of(VACANT_TILE.x, VACANT_TILE.y)] = 4
	_works = LandWorks.new()
	_works.set_improvement(_model, LINKED_TILE, 2)
	_works.set_improvement(_model, OFF_ROAD_TILE, 1)
	_works.set_prospected(0, _model, OFF_ROAD_TILE)
	_units = []
	_panel = ProvincePanel.new()
	add_child(_panel)


func after_each() -> void:
	if is_instance_valid(_panel):
		_panel.free()
	_panel = null


# --- the title block ---------------------------------------------------------


## A province's holder is named by its kind, so a tribe's land never reads as a
## crown's (wiki: factions — three governing types).
func test_the_head_names_the_kind_of_court_that_holds_the_land() -> void:
	var head := ProvinceSheetHead.new()
	add_child(head)
	var data: ProvinceState = _model.province_data(0)
	var cases: Array = [
		[
			FactionCatalog.PLAYER_FACTION,
			"Crown of %s" % FactionCatalog.name_of(FactionCatalog.PLAYER_FACTION),
		],
		[6, "Minor nation of Genoa"],
		[9, "Tribe of the Aztec"],
		[-1, "Unclaimed territory"],
	]
	for spec: Array in cases:
		data.owner = int(spec[0])
		head.show_province(data)
		assert_eq(head.owner_label.text, String(spec[1]))
	head.free()


# --- the estate block --------------------------------------------------------


func test_the_dossier_lists_every_estate_not_just_the_headline() -> void:
	_show()
	var rows: Array[Dictionary] = _panel._resources.lines()
	assert_eq(rows.size(), 4, "four resource tiles, not the province's one headline")
	var tiles: Array[Vector2i] = []
	for row: Dictionary in rows:
		tiles.append(row["tile"])
	assert_true(tiles.has(LINKED_TILE), "the timber tile")
	assert_true(tiles.has(VACANT_TILE), "the grain tile")
	assert_true(tiles.has(OFF_ROAD_TILE), "the iron tile")
	assert_true(tiles.has(Fixture.TIMBER_TILE), "the province's other timber tile")


func test_each_estate_says_whether_it_is_developed_and_linked() -> void:
	_show()
	var by_tile: Dictionary = _by_tile()
	assert_eq(int(by_tile[LINKED_TILE]["level"]), 2, "developed")
	assert_true(bool(by_tile[LINKED_TILE]["connected"]), "and linked")
	assert_eq(int(by_tile[VACANT_TILE]["level"]), 0, "bare")
	assert_true(bool(by_tile[VACANT_TILE]["connected"]), "but on the road")
	assert_eq(int(by_tile[OFF_ROAD_TILE]["level"]), 1, "developed")
	assert_false(bool(by_tile[OFF_ROAD_TILE]["connected"]), "and cut off")
	var words: Array[String] = _row_text(_panel._resources, LINKED_TILE)
	assert_true(words.has("L2"), "the level is printed: %s" % [words])
	assert_true(words.has("linked"), "the capital link is printed: %s" % [words])
	words = _row_text(_panel._resources, OFF_ROAD_TILE)
	assert_true(words.has("no road"), "a cut-off estate says so: %s" % [words])


## Every estate carries its own commodity medallion; a row whose good is not in
## the catalog keeps the category pictogram rather than losing its mark.
func test_an_estate_shows_its_goods_medallion() -> void:
	_show()
	var art: Array[Node] = _panel._resources.find_children("*", "TextureRect", true, false)
	assert_gt(art.size(), 0, "the estate block draws medallions")
	var plain: Control = _panel._resources._art({"commodity": "", "icon": "ore"})
	assert_true(plain is Icon, "an unknown good falls back to the category pictogram")
	plain.free()


func test_the_roads_row_names_the_estates_that_reach_the_crown() -> void:
	_show()
	assert_eq(_panel._grid.road.text, "1 of 2 developed estates linked")
	assert_true(_panel._grid.road.tooltip_text.contains("4 estates surveyed"))


func test_a_province_with_no_developed_estate_says_so() -> void:
	_works = LandWorks.new()
	_show()
	assert_eq(_panel._grid.road.text, "No developed estate yet")


# --- the rows the player complained about ------------------------------------


func test_the_dossier_keeps_no_population_or_capital_row() -> void:
	_show()
	var captions: Array[String] = _captions(_panel._grid)
	assert_false(captions.has("Population"), "population has no rule behind it")
	assert_false(captions.has("Capital"), "the header badge already says CAPITAL")
	assert_true(captions.has("Terrain"))
	assert_true(captions.has("Roads"))


func test_the_town_row_names_the_town_level() -> void:
	_show()
	assert_eq(_panel._grid.town.text, "Level 1")
	_model.provinces[0].town_development = 4
	_show()
	assert_eq(_panel._grid.town.text, "Level 4 · full")


## The town row's tip names the path the province on screen actually offers: a
## Builder in a crown's own land, a Merchant's deed in a Minor or Tribe province
## (wiki: civilian-units § Merchant; DR-20261112-01). A Builder a crown may not
## send there is not advice.
func test_the_town_row_names_the_path_that_province_offers() -> void:
	_show()
	assert_true(
		_panel._grid.town.tooltip_text.contains("A Builder raises the town"),
		"a crown's own town is its Builder's work"
	)
	_model.provinces[1].owner = 6
	_model.provinces[1].town_tile = Fixture.RIVAL_GRAIN_TILE
	_panel.set_data(_model, _works, _units, null, Vector2i(0, 0), 0, {}, {})
	_panel.refresh(_model, 1)
	assert_true(
		_panel._grid.town.tooltip_text.contains("Merchant"),
		"a Minor's town grows only from a deed: %s" % _panel._grid.town.tooltip_text
	)
	assert_false(
		_panel._grid.town.tooltip_text.contains("A Builder raises the town"),
		"the tip never names a Builder a crown cannot send there"
	)
	assert_eq(
		DossierCopy.town_tip(null), DossierCopy.TOWN_TIP,
		"a missing province falls back to the Builder line"
	)


# --- the town order's gate ---------------------------------------------------


func test_the_town_order_stays_shut_until_national_bureaucracy() -> void:
	_show({})
	assert_true(_panel._orders.town_button.disabled, "no tech, no order")
	assert_true(
		_panel._orders.town_button.tooltip_text.contains("National Bureaucracy"),
		"the button says what it waits for: %s" % _panel._orders.town_button.tooltip_text
	)
	_show({"national_bureaucracy": true})
	assert_false(_panel._orders.town_button.disabled, "researched, the order opens")


func test_a_fully_developed_town_closes_the_order() -> void:
	_model.provinces[0].town_development = 4
	_show({"national_bureaucracy": true})
	assert_true(_panel._orders.town_button.disabled)
	assert_true(_panel._orders.town_button.tooltip_text.contains("fully developed"))


func test_a_foreign_province_offers_no_town_order() -> void:
	_model.provinces[1].town_tile = Fixture.RIVAL_GRAIN_TILE
	_panel.set_data(
		_model, _works, _units, null, Vector2i(0, 0), 0, {},
		{"national_bureaucracy": true}
	)
	_panel.refresh(_model, 1)
	assert_true(_panel._orders.town_button.disabled)
	assert_true(_panel._orders.town_button.tooltip_text.contains("not held by your crown"))


# --- the dock affordance -----------------------------------------------------


func test_every_dock_button_is_a_bare_glyph() -> void:
	var panels: Array = [_panel, FleetPanel.new(), ArmyPanel.new(), CivilianPanel.new()]
	for i in range(1, panels.size()):
		add_child(panels[i])
	for panel: Variant in panels:
		# Force dossiers keep the seal on their shared header; the sheets that
		# still own it expose `_dock` directly.
		var header: DossierHeader = panel.get("_header") as DossierHeader
		var dock: Button = header.dock if header != null else panel.get("_dock") as Button
		assert_true(dock != null, "%s has a dock button" % panel.get_class())
		panel.set_dock_affordance("▶", "Dock right")
		assert_eq(dock.text, "▶", "the glyph and nothing else")
		assert_false(dock.text.contains("Dock"), "no word on the button")
		assert_true(
			dock.custom_minimum_size.x <= 40.0 and dock.custom_minimum_size.y <= 40.0,
			"a corner button, not a bar: %s" % dock.custom_minimum_size
		)
	for i in range(1, panels.size()):
		(panels[i] as Node).free()


# --- helpers -----------------------------------------------------------------


func _show(tech: Dictionary = {}) -> void:
	_panel.set_data(_model, _works, _units, null, Vector2i(0, 0), 0, {}, tech)
	_panel.refresh(_model, 0)


func test_the_estate_block_names_the_ground_still_to_survey() -> void:
	_show()
	# The fixture's iron tile is already prospected; the bare hills are not.
	var text: String = _panel._resources.survey_text()
	assert_true(text.contains("Unsurveyed ground"), text)
	assert_true(text.contains("1 tile"), text)


func test_an_empty_estate_block_still_names_the_ground_to_read() -> void:
	var block := ProvinceResources.new()
	add_child(block)
	block.render([], 3)
	assert_true(block._empty.text.contains("No estates charted"))
	assert_true(block._empty.text.contains("3 tiles"))
	assert_true(block.survey_text().contains("3 tiles"))
	# A fully read province says nothing, and keeps the plain empty line.
	block.render([], 0)
	assert_true(block._empty.text.begins_with("No charted"))
	assert_eq(block.survey_text(), "")
	block.free()


func _by_tile() -> Dictionary:
	var by_tile: Dictionary = {}
	for row: Dictionary in _panel._resources.lines():
		by_tile[row["tile"]] = row
	return by_tile


## Every label printed on the estate block's line for one tile.
func _row_text(block: ProvinceResources, tile: Vector2i) -> Array[String]:
	var words: Array[String] = []
	var rows: Array[Dictionary] = block.lines()
	for i in rows.size():
		if rows[i]["tile"] != tile:
			continue
		var line: Node = block._body.get_child(i)
		for node: Node in line.find_children("*", "Label", true, false):
			words.append((node as Label).text)
	return words


func _captions(grid: GridContainer) -> Array[String]:
	var captions: Array[String] = []
	for node: Node in grid.get_children():
		var label := node as Label
		if label != null and not label.text.is_empty():
			captions.append(label.text)
	return captions
