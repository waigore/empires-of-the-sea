# gdlint: disable=max-public-methods
extends GdToolsTest
## Lean chrome boot: HudCampaignEnd + GameHud routing, app icon / launcher
## branding, court heraldry, and TileEdges seam walks (REQ-P3-01, REQ-P1-02/03/08).
## The full calendar-cap MapScreen theme lives in test_campaign_end; this suite
## stays lean so a chrome, branding, heraldry or seam extract stays inside the
## tier-1 5 min budget. Merged from test_branding_rules, test_heraldry and
## test_tile_edges (one Godot boot for the leftovers; docs/testing.md).

const MapFixture = preload("res://tests/map_fixture.gd")

var _host: Control = null
var _overlay: VictoryOverlay = null
var _seal: Button = null
var _glow: Panel = null
var _end: HudCampaignEnd = null
var _hud: GameHud = null
var _suite_setup: String = ""


func after_each() -> void:
	match _suite_setup:
		"chrome":
			_teardown_chrome()
	_suite_setup = ""


func _setup_chrome() -> void:
	_suite_setup = "chrome"
	_host = Control.new()
	add_child(_host)
	_overlay = VictoryOverlay.new()
	_host.add_child(_overlay)
	_seal = Button.new()
	_host.add_child(_seal)
	_glow = Panel.new()
	_host.add_child(_glow)
	_end = HudCampaignEnd.new()
	_end.bind(_host, _overlay, _seal, _glow, null)
	_hud = GameHud.new()
	add_child(_hud)
	_hud.campaign_end = _end


func _teardown_chrome() -> void:
	if is_instance_valid(_hud):
		_hud.free()
	if is_instance_valid(_host):
		_host.free()
	_hud = null
	_host = null
	_overlay = null
	_seal = null
	_glow = null
	_end = null


func test_victory_routes_through_the_plate_and_seals_the_door() -> void:
	_setup_chrome()
	var state := VictoryState.military(FactionCatalog.PLAYER_FACTION, 10)
	_hud.show_victory(state, FactionCatalog.PLAYER_FACTION, 12)
	assert_true(_hud.campaign_over)
	assert_true(_hud.is_victory_shown())
	assert_true(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.SEALED_TEXT)
	assert_false(_glow.visible)


func test_calendar_cap_and_defeat_raise_the_same_sealed_plate() -> void:
	_setup_chrome()
	_hud.show_campaign_complete(FactionCatalog.PLAYER_FACTION, 50, FactionCatalog.PLAYER_FACTION)
	assert_true(_hud.campaign_over)
	assert_true(_overlay.is_shown())
	_hud.set_campaign_over(false)
	assert_false(_hud.campaign_over)
	assert_eq(_seal.text, HudCampaignEnd.OPEN_TEXT)
	assert_true(_glow.visible)
	var defeat := DefeatState.terminal_fall(
		FactionCatalog.PLAYER_FACTION, FactionCatalog.PLAYER_FACTION + 1, 20
	)
	_hud.show_defeat(defeat, FactionCatalog.PLAYER_FACTION)
	assert_true(_hud.campaign_over)
	assert_true(_hud.is_victory_shown())


func test_auto_seat_mirrors_the_seal_until_the_campaign_ends() -> void:
	_setup_chrome()
	_end.mirror_seat(true, false)
	assert_true(_seal.disabled)
	assert_eq(_seal.text, "AUTO")
	_end.mirror_seat(false, false)
	assert_false(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.OPEN_TEXT)
	_end.mirror_seat(true, true)
	assert_true(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.SEALED_TEXT)


func test_cartouche_routes_the_turn_line_and_minimap_markings() -> void:
	_setup_chrome()
	var cartouche := HudChartCartouche.new()
	var turn_label := Label.new()
	_host.add_child(turn_label)
	# Minimap needs a live tree node; bind without building so routing still runs.
	var mini := Minimap.new()
	_host.add_child(mini)
	cartouche.bind(turn_label, mini)
	_hud.cartouche = cartouche
	_hud.set_turn(3, 1494)
	assert_eq(turn_label.text, "Turn 3  ·  1494")
	_hud.refresh_minimap()
	_hud.update_view_rect(Rect2(0, 0, 10, 10))
	# set_minimap with a null model is a no-op inside Minimap; the route still
	# counts as covered when cartouche is bound.
	_hud.set_minimap(null, Vector2(32, 32), null)

# --- app icon / launcher branding (from test_branding_rules) --------------------
## The project icon and Android launcher layers (REQ-P1-02/03/08; issue #887).
## Asset wiring only — rides this lean chrome suite so branding PRs stay inside
## the tier-1 budget without a second coverage boot (docs/testing.md).

const ICON_PATH := "res://icon.png"
const PRESETS_PATH := "res://export_presets.cfg"
const BRANDING_DIR := "res://assets/art/branding/"
## The old placeholder's disc colour: the mark must not fall back to it.
const PLACEHOLDER_FILL := "#3d8fd1"
const ICON_SIZE := 1024
const LAUNCHER_SIZES := {
	"launcher_main_192.png": 192,
	"launcher_foreground_432.png": 432,
	"launcher_background_432.png": 432,
	"launcher_monochrome_432.png": 432,
}

func test_project_icon_is_the_carrack_mark() -> void:
	var img := _branding_load(ICON_PATH)
	if img == null:
		assert_true(false, "the project icon must exist and load")
		return
	assert_eq(img.get_width(), ICON_SIZE, "the icon is a %d px square" % ICON_SIZE)
	assert_eq(img.get_height(), ICON_SIZE, "the icon is a %d px square" % ICON_SIZE)
	assert_false(_branding_is_flat(img), "the icon must carry real art, not a flat disc")
	assert_ne(
		"#%s" % img.get_pixel(ICON_SIZE / 2, ICON_SIZE / 2).to_html(false),
		PLACEHOLDER_FILL,
		"the placeholder disc colour must be gone"
	)

func test_project_icon_is_wired() -> void:
	var project := _branding_read("res://project.godot")
	assert_true(
		project.contains('config/icon="res://icon.png"'),
		"project.godot must point config/icon at the carrack mark"
	)

func test_launcher_layers_exist_at_their_sizes() -> void:
	for name: String in LAUNCHER_SIZES:
		var path: String = BRANDING_DIR + name
		assert_true(FileAccess.file_exists(path), "%s must exist" % path)
		var img := _branding_load(path)
		if img == null:
			assert_true(false, "%s must load" % path)
			continue
		assert_eq(img.get_width(), LAUNCHER_SIZES[name], "%s width" % name)
		assert_eq(img.get_height(), LAUNCHER_SIZES[name], "%s height" % name)

func test_project_icon_corners_are_transparent() -> void:
	var img := _branding_load(ICON_PATH)
	if img == null:
		assert_true(false, "the project icon must exist and load")
		return
	var edge := img.get_width() - 1
	for point: Vector2i in [
		Vector2i(0, 0), Vector2i(edge, 0), Vector2i(0, edge), Vector2i(edge, edge),
	]:
		assert_lt(
			img.get_pixel(point.x, point.y).a,
			0.5,
			"the icon must be transparent outside the medallion (issue #920)"
		)
	assert_gt(
		img.get_pixel(img.get_width() / 2, img.get_height() / 2).a,
		0.5,
		"the medallion must stay opaque in the middle of the icon"
	)

func test_launcher_main_corners_are_transparent() -> void:
	var img := _branding_load(BRANDING_DIR + "launcher_main_192.png")
	if img == null:
		assert_true(false, "the legacy launcher icon must exist and load")
		return
	var edge := img.get_width() - 1
	for point: Vector2i in [
		Vector2i(0, 0), Vector2i(edge, 0), Vector2i(0, edge), Vector2i(edge, edge),
	]:
		assert_lt(
			img.get_pixel(point.x, point.y).a,
			0.5,
			"the launcher icon must be transparent outside the medallion (issue #920)"
		)

func test_adaptive_background_stays_a_plate() -> void:
	var img := _branding_load(BRANDING_DIR + "launcher_background_432.png")
	if img == null:
		assert_true(false, "the adaptive background must exist and load")
		return
	assert_gt(
		img.get_pixel(0, 0).a,
		0.5,
		"the adaptive background is the one layer the platform needs opaque"
	)

func test_adaptive_foreground_keeps_art_off_the_crop_edge() -> void:
	var img := _branding_load(BRANDING_DIR + "launcher_foreground_432.png")
	if img == null:
		assert_true(false, "the adaptive foreground must exist and load")
		return
	var edge := img.get_width() - 1
	assert_lt(img.get_pixel(0, 0).a, 0.5, "the adaptive foreground corners must be clear")
	assert_lt(img.get_pixel(edge, edge).a, 0.5, "the adaptive foreground corners must be clear")
	assert_gt(
		img.get_pixel(img.get_width() / 2, img.get_height() / 2).a,
		0.5,
		"the medallion must sit in the middle of the adaptive foreground"
	)

func test_android_presets_wire_every_launcher_layer() -> void:
	var presets := _branding_read(PRESETS_PATH)
	assert_ne(presets, "", "export presets must exist")
	var wired := 0
	for line: String in presets.split("\n"):
		if not line.begins_with("launcher_icons/"):
			continue
		var value := line.get_slice('"', 1)
		assert_ne(value, "", "every launcher slot must be wired: %s" % line)
		assert_true(FileAccess.file_exists(value), "%s must exist" % value)
		wired += 1
	assert_gte(wired, 4, "both Android presets must declare the launcher layers")

func _branding_load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return img

## True when every sampled pixel is the same colour (the old flat disc).
func _branding_is_flat(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(0, 0)
	for point: Vector2i in [
		Vector2i(w / 2, h / 2), Vector2i(w / 3, h / 3), Vector2i(2 * w / 3, h / 3),
		Vector2i(w / 3, 2 * h / 3), Vector2i(2 * w / 3, 2 * h / 3),
	]:
		if not img.get_pixel(point.x, point.y).is_equal_approx(first):
			return false
	return true

func _branding_read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

# --- court heraldry (folded from test_heraldry) ---------------------------------
## Pure blazon tables plus the three surfaces that wear them (wiki: diplomacy
## § The court sheet; DR-20261118-30). Rides the lean chrome boot so heraldry
## edits do not pay a second coverage process (docs/testing.md).

const CHARGES: int = 18


## Every court in the catalog has arms the sheet can paint.
func test_every_court_has_arms() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		assert_false(arms.is_empty(), "no arms for %s" % faction["name"])
		assert_eq(String(arms["name"]), String(faction["name"]))


## No two courts wear the same shield: a crest that repeated would be a second
## colour wash and nothing more (REQ-P1-08).
func test_no_two_courts_wear_the_same_shield() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		var key: String = "%s|%s|%s" % [
			(arms["field"] as Color).to_html(false),
			String(arms["charge"]),
			String(arms["division"]),
		]
		assert_false(seen.has(key), "%s repeats %s" % [faction["name"], seen.get(key, "")])
		seen[key] = faction["name"]
	assert_eq(seen.size(), FactionCatalog.count())


## A charge and its division are dealt as one disposition, so two courts that
## share a charge are parted by their field's division and never read as one
## shield (the roster outgrows the charge table by a few).
func test_each_court_has_its_own_disposition() -> void:
	var seen: Dictionary = {}
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		var key: String = "%s|%s" % [String(arms["charge"]), String(arms["division"])]
		assert_false(seen.has(key), "%s repeats %s" % [faction["name"], seen.get(key, "")])
		seen[key] = faction["name"]
	assert_eq(seen.size(), FactionCatalog.count())
	assert_true(FactionCatalog.count() <= CHARGES * 3, "the divisions carry the overflow")


## The field is the crown's own catalog colour, so a province on the chart and
## its court on the sheet can never disagree about who owns it (REQ-P2-03).
func test_the_field_is_the_crowns_own_colour() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var id: int = int(faction["id"])
		assert_eq(FactionHeraldry.blazon(id)["field"], FactionCatalog.color_of(id))


## A charge never sinks into its field: the tincture is the metal on a dark
## colour and the sheet's ink on a light one (REQ-P1-07).
func test_the_charge_never_sinks_into_its_field() -> void:
	for faction: Dictionary in FactionCatalog.all():
		var arms: Dictionary = FactionHeraldry.blazon(int(faction["id"]))
		var field: Color = arms["field"]
		var ink: Color = arms["tincture"]
		assert_true(
			absf(FactionHeraldry.luminance(field) - FactionHeraldry.luminance(ink)) > 0.25,
			"%s's charge is too close to its field" % faction["name"]
		)


## The bordure reads the rank the court sheet already sorts by: a Great Power's
## bright gilt, a Minor Nation's dim one, a Tribe's plain ink (wiki: factions).
func test_the_bordure_reads_the_rank() -> void:
	for id: int in FactionCatalog.great_power_ids():
		assert_eq(FactionHeraldry.blazon(id)["bordure"], FactionHeraldry.BORDURE_GREAT_POWER)
	for id: int in FactionCatalog.minor_ids():
		assert_eq(FactionHeraldry.blazon(id)["bordure"], FactionHeraldry.BORDURE_MINOR)
	for id: int in FactionCatalog.tribe_ids():
		assert_eq(FactionHeraldry.blazon(id)["bordure"], FactionHeraldry.BORDURE_TRIBE)


## Arms are the court's, not the session's: the same court reads the same shield
## every time it is asked.
func test_arms_are_stable() -> void:
	var first: Dictionary = FactionHeraldry.blazon(2)
	for i in 5:
		assert_eq(FactionHeraldry.blazon(2), first, "the %d read moved" % i)


## A court the catalog does not know wears nothing, and its crest keeps the
## footprint a row reserved for it.
func test_an_unknown_court_wears_nothing() -> void:
	assert_true(FactionHeraldry.blazon(-1).is_empty())
	assert_true(FactionHeraldry.blazon(999).is_empty())
	assert_eq(FactionHeraldry.position_of(999), -1)
	var crest := FactionCrest.of(999)
	add_child(crest)
	assert_true(crest.arms.is_empty())
	assert_eq(crest.custom_minimum_size, Vector2(FactionCrest.ROW_SIZE, FactionCrest.ROW_SIZE))
	crest.free()


## A crest takes the size its sheet asks for and never swallows a tap: the court
## row's own press stays the row's (REQ-P1-05).
func test_a_crest_keeps_its_size_and_lets_the_press_through() -> void:
	var row := FactionCrest.of(1)
	add_child(row)
	assert_eq(row.custom_minimum_size, Vector2(FactionCrest.ROW_SIZE, FactionCrest.ROW_SIZE))
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(String(row.arms["name"]), "England")
	var head := FactionCrest.of(1, FactionCrest.HEAD_SIZE)
	add_child(head)
	assert_eq(head.custom_minimum_size, Vector2(FactionCrest.HEAD_SIZE, FactionCrest.HEAD_SIZE))
	head.free()
	row.free()


# --- the shield's data (FactionCrestMarks) ------------------------------------


## The shield is a closed heater outline inside the box it was given, so it can
## never spill outside its row.
func test_the_shield_stays_inside_its_box() -> void:
	var centre := Vector2(20, 20)
	var half: float = 16.0
	var outline: PackedVector2Array = FactionCrestMarks.shield_points(centre, half)
	assert_eq(outline.size(), FactionCrestMarks.SHIELD.size())
	for point: Vector2 in outline:
		assert_true(absf(point.x - centre.x) <= half + 0.01, "%s is off the box" % point)
		assert_true(absf(point.y - centre.y) <= half + 0.01, "%s is off the box" % point)


## Every charge the table deals paints at least one mark, in the tincture the
## field earned — so a shield always bears something and never draws blank. The
## tower's gate is the one mark cut in the field, so the tower reads as a tower.
func test_every_charge_paints_at_least_one_mark() -> void:
	var ink: Color = Palette.GOLD_PALE
	var field: Color = Palette.NAVY
	for charge: String in FactionHeraldry.CHARGES:
		var marks: Array[Dictionary] = FactionCrestMarks.charge_marks(
			charge, Vector2(24, 24), 12.0, ink, field
		)
		assert_true(marks.size() > 0, "%s paints nothing" % charge)
		var inked: int = 0
		for mark: Dictionary in marks:
			assert_true(
				["rect", "poly", "line", "polyline", "arc", "circle"].has(String(mark["kind"])),
				"%s's mark is not a shape the painter draws" % charge
			)
			assert_true(
				mark["color"] == ink or mark["color"] == field,
				"%s's mark is in neither the tincture nor the field" % charge
			)
			if mark["color"] == ink:
				inked += 1
		assert_true(inked > 0, "%s bears no ink at all" % charge)


## A charge the table does not know still draws a roundel rather than nothing.
func test_an_unknown_charge_still_paints() -> void:
	var marks: Array[Dictionary] = FactionCrestMarks.charge_marks(
		"not_a_charge", Vector2(10, 10), 6.0, Palette.INK, Palette.PAPER
	)
	assert_eq(marks.size(), 1)
	assert_eq(String(marks[0]["kind"]), "circle")


## The division parts a field with the party colour, and a plain field takes no
## line at all.
func test_the_division_parts_the_field() -> void:
	assert_eq(
		FactionCrestMarks.division_marks(Vector2(10, 10), 8.0, Palette.GOLD, "plain").size(), 0
	)
	assert_eq(
		FactionCrestMarks.division_marks(Vector2(10, 10), 8.0, Palette.GOLD, "quarterly").size(), 2
	)
	var bend: Array[Dictionary] = FactionCrestMarks.division_marks(
		Vector2(10, 10), 8.0, Palette.GOLD, "per_bend"
	)
	assert_eq(bend.size(), 1)
	assert_eq(String(bend[0]["kind"]), "poly")


## Re-arming a crest for another court repaints it rather than stacking a second
## shield: the dossier's head keeps one control over every open (REQ-P4-04).
func test_a_crest_re_arms_for_another_court() -> void:
	var crest := FactionCrest.of(1)
	add_child(crest)
	crest.set_faction(2)
	assert_eq(crest.arms, FactionHeraldry.blazon(2))
	assert_eq(String(crest.arms["name"]), "France")
	crest.set_faction(-1)
	assert_true(crest.arms.is_empty())
	crest.free()


# --- the three surfaces that wear the arms -----------------------------------


## Every court row wears its own arms before its name, one shield per court, so a
## crown finds a court by sight (REQ-P1-07, REQ-P1-08).
func test_every_court_row_wears_its_own_arms() -> void:
	var panel: DiplomacyPanel = _court_panel()
	var crests: Array[FactionCrest] = []
	for node: Node in panel._list.find_children("*", "FactionCrest", true, false):
		crests.append(node as FactionCrest)
	var rows: int = 0
	for node: Node in panel._list.get_children():
		if node is HBoxContainer:
			rows += 1
	assert_eq(crests.size(), rows, "one shield per court row")
	assert_true(rows > 1, "the sheet lists more than one court")
	var seen: Dictionary = {}
	for crest: FactionCrest in crests:
		var id: int = int(crest.arms.get("faction", -1))
		assert_false(seen.has(id), "a court wears one shield, not two")
		seen[id] = true
		assert_eq(crest.arms["field"], FactionCatalog.color_of(id), "the chart's own colour")
	panel.free()


## The open court's page wears the arms of the court it names, over the name.
func test_the_open_courts_page_wears_the_arms_it_names() -> void:
	var panel: DiplomacyPanel = _court_panel()
	panel.select_faction(6)
	var found: FactionCrest = null
	for node: Node in panel._detail.find_children("*", "FactionCrest", true, false):
		found = node as FactionCrest
	assert_not_null(found, "the open court shows its shield")
	assert_eq(found.arms, FactionHeraldry.blazon(6), "Genoa's own arms")
	assert_true(_has_text(panel._detail, "Genoa"))
	panel.free()


## The dossier's head wears the arms of the court it is open on, and re-arms for
## the next court rather than stacking a second shield (REQ-P4-04).
func test_the_dossier_head_wears_the_courts_arms() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	var sheet := CourtDossierScreen.new()
	add_child(sheet)
	sheet.show_for(state, null, 0, 1)
	assert_eq(sheet._arms.arms, FactionHeraldry.blazon(1), "England's arms")
	sheet.show_for(state, null, 0, 6)
	assert_eq(sheet._arms.arms, FactionHeraldry.blazon(6), "Genoa's arms after")
	sheet.free()


## A court sheet with the crown's own relations, mounted the way the HUD mounts
## it: the list and the open court's page, no chart behind them.
func _court_panel() -> DiplomacyPanel:
	var state := DiplomacyState.new()
	state.initialize(1)
	var panel := DiplomacyPanel.new()
	add_child(panel)
	panel.refresh(state, null, 0, 2500)
	return panel


func _has_text(node: Node, needle: String) -> bool:
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if _has_text(child, needle):
			return true
	return false

# --- tile edges (folded from test_tile_edges) ------------------------------------
## Province/sea seam walks every charted layer inks from — pure data, no node
## (REQ-P3-01, REQ-P3-03). Rides the lean chrome boot with heraldry and branding.


const TILE_EDGE_UNIT: float = 22.0


func _charted_after_first_region() -> MapModel:
	return MapFixture.region()


## A seam pair spans exactly one tile edge of the unit the caller asked for.
func test_a_seam_pair_spans_one_tile_edge() -> void:
	var top: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.TOP, TILE_EDGE_UNIT)
	assert_eq(top, PackedVector2Array([Vector2(44.0, 66.0), Vector2(66.0, 66.0)]))
	var right: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.RIGHT, TILE_EDGE_UNIT)
	assert_eq(right, PackedVector2Array([Vector2(66.0, 66.0), Vector2(66.0, 88.0)]))
	var bottom: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.BOTTOM, TILE_EDGE_UNIT)
	assert_eq(bottom, PackedVector2Array([Vector2(66.0, 88.0), Vector2(44.0, 88.0)]))
	var left: PackedVector2Array = TileEdges.pair(2, 3, TileEdges.Edge.LEFT, TILE_EDGE_UNIT)
	assert_eq(left, PackedVector2Array([Vector2(44.0, 88.0), Vector2(44.0, 66.0)]))


## Off-grid steps read the model's sentinel, so the walk's outside test is the
## chart's edge and not a missing-province test.
func test_an_off_chart_tile_reads_as_outside() -> void:
	var model: MapModel = _charted_after_first_region()
	assert_eq(model.province_at(-1, 0), MapModel.NO_ID)
	assert_eq(model.sea_zone_at(model.width, 0), MapModel.NO_ID)


## A closed province outline traces each seam once and stays on that province's
## own tiles.
func test_a_province_outline_keeps_every_seam_once_and_bounded() -> void:
	var model: MapModel = _charted_after_first_region()
	var province: int = MapFixture.inland_province(model)
	var mine := func(x: int, y: int) -> bool:
		return model.province_at(x, y) == province
	var seams: Array[PackedVector2Array] = TileEdges.province_seams(model, mine, TILE_EDGE_UNIT)
	assert_gt(seams.size(), 3, "an inland province inks a closed outline")
	var seen: Dictionary = {}
	for path: PackedVector2Array in seams:
		assert_eq(path.size(), 2)
		var key: String = str(path)
		assert_false(seen.has(key), "a seam is inked once")
		seen[key] = true
		for point: Vector2 in path:
			assert_true(point.x >= 0.0 and point.y >= 0.0)
			assert_true(point.x <= float(model.width) * TILE_EDGE_UNIT)
			assert_true(point.y <= float(model.height) * TILE_EDGE_UNIT)


## The subdivisions read only the right and bottom steps, so the coast and the
## province ink never trace the same seam twice on the inset.
func test_division_slots_read_only_the_forward_steps() -> void:
	var model: MapModel = _charted_after_first_region()
	var province: int = MapFixture.inland_province(model)
	var mine := func(x: int, y: int) -> bool:
		return model.province_at(x, y) == province
	var forward: Array[PackedVector2Array] = TileEdges.province_seams(
		model, mine, TILE_EDGE_UNIT, TileEdges.Look.OUTSIDE,
		[TileEdges.Edge.RIGHT, TileEdges.Edge.BOTTOM]
	)
	var all_slots: Array[PackedVector2Array] = TileEdges.province_seams(model, mine, TILE_EDGE_UNIT)
	assert_lt(forward.size(), all_slots.size(), "half the slots ink a little over half")
	for path: PackedVector2Array in forward:
		var width: float = absf(path[1].x - path[0].x)
		var height: float = absf(path[1].y - path[0].y)
		assert_true(width < 0.01 or height < 0.01)


## A coast is a land tile's seam against the sea: every seam is one tile edge
## long — never a diagonal — and it always borders charted land.
func test_a_coast_is_every_edge_whose_neighbour_is_land() -> void:
	var model: MapModel = _charted_after_first_region()
	var land := func(x: int, y: int) -> bool:
		return model.is_land(x, y)
	var coast: Array[PackedVector2Array] = TileEdges.province_seams(
		model, land, TILE_EDGE_UNIT, TileEdges.Look.COAST
	)
	assert_gt(coast.size(), 0, "a generated region has a coast")
	for path: PackedVector2Array in coast:
		assert_eq(path.size(), 2)
		var run_along_x: float = absf(path[1].x - path[0].x)
		var run_along_y: float = absf(path[1].y - path[0].y)
		assert_true(run_along_x < 0.01 or run_along_y < 0.01, "a seam is one tile edge")
		assert_almost_eq(maxf(run_along_x, run_along_y), TILE_EDGE_UNIT, 0.01)
		assert_true(_starts_on_land(model, path), "the ink starts on land")


## A division is only a seam between two charted crowned provinces: coast and
## fog never ink a border of their own.
func test_a_division_leaves_coast_and_fog_to_their_own_ink() -> void:
	var model: MapModel = _charted_after_first_region()
	var every_tile := func(_x: int, _y: int) -> bool:
		return true
	var divide := func(x: int, y: int) -> bool:
		return model.province_at(x, y) != MapModel.NO_ID
	var divided: Array[PackedVector2Array] = TileEdges.province_seams(
		model, divide, TILE_EDGE_UNIT, TileEdges.Look.DIVIDE
	)
	assert_gt(divided.size(), 0, "crowned provinces share borders")
	for path: PackedVector2Array in divided:
		var a: Vector2 = path[0]
		var b: Vector2 = path[1]
		var step: Vector2 = (b - a).normalized()
		var mid: Vector2 = (a + b) * 0.5
		# The pair runs along the seam; the two crowns sit a half tile either
		# side of it, and both of them must be charted land.
		var side: Vector2 = Vector2(step.y, step.x) * TILE_EDGE_UNIT * 0.5
		var left: Vector2i = Vector2i(
			int(floorf((mid.x + side.x) / TILE_EDGE_UNIT)), int(floorf((mid.y + side.y) / TILE_EDGE_UNIT))
		)
		var right: Vector2i = Vector2i(
			int(floorf((mid.x - side.x) / TILE_EDGE_UNIT)), int(floorf((mid.y - side.y) / TILE_EDGE_UNIT))
		)
		assert_true(model.is_land(left.x, left.y), "a division runs between crowned land")
		assert_true(model.is_land(right.x, right.y), "a division runs between crowned land")
		assert_ne(model.province_at(left.x, left.y), model.province_at(right.x, right.y))
	var whole_chart: Array[PackedVector2Array] = TileEdges.province_seams(
		model, every_tile, TILE_EDGE_UNIT, TileEdges.Look.DIVIDE
	)
	assert_gte(whole_chart.size(), divided.size(), "a wider reading keeps every crowned seam")


## A neighbour reading lets a caller leave a step to another ink: the inset's
## fog hides its own seams rather than drawing a border into the unknown.
func test_a_neighbour_reading_can_leave_a_step_to_other_ink() -> void:
	var model: MapModel = _charted_after_first_region()
	var province: int = MapFixture.inland_province(model)
	var mine := func(x: int, y: int) -> bool:
		return model.province_at(x, y) == province
	var every_step := func(_x: int, _y: int) -> bool:
		return true
	var only_east := func(x: int, y: int) -> bool:
		return x >= model.width / 2
	var clipped: Array[PackedVector2Array] = TileEdges.province_seams(
		model, mine, TILE_EDGE_UNIT, TileEdges.Look.OUTSIDE, [], only_east
	)
	for path: PackedVector2Array in clipped:
		for point: Vector2 in path:
			assert_true(point.x / TILE_EDGE_UNIT >= model.width / 2.0 - 1.0, "a clipped step stays out of the left half")
	var unclipped: Array[PackedVector2Array] = TileEdges.province_seams(
		model, mine, TILE_EDGE_UNIT, TileEdges.Look.OUTSIDE, [], every_step
	)
	assert_gte(unclipped.size(), clipped.size(), "reading every neighbour keeps at least the clipped seams")


## The land tile a coast seam belongs to: the pair is vertical on the left or
## right of a tile and horizontal on its top or bottom, so the owner is the
## land side of it.
func _starts_on_land(model: MapModel, path: PackedVector2Array) -> bool:
	var mid: Vector2 = (path[0] + path[1]) * 0.5
	var near := Vector2i(int(floorf(mid.x / TILE_EDGE_UNIT)), int(floorf(mid.y / TILE_EDGE_UNIT)))
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if model.is_land(near.x + dx, near.y + dy):
				return true
	return false


## No chart, no ink: a layer mounted before its region builds gets an empty list.
func test_a_missing_or_unmeasured_chart_inks_nothing() -> void:
	var everywhere := func(_x: int, _y: int) -> bool:
		return true
	var model: MapModel = _charted_after_first_region()
	var empty_chart: MapModel = MapModel.new()
	var inks: Dictionary = {
		"a sea with no chart": TileEdges.sea_seams(null, everywhere, TILE_EDGE_UNIT).size(),
		"a province with no chart": TileEdges.province_seams(null, everywhere, TILE_EDGE_UNIT).size(),
		"the walk with no chart": TileEdges.seams(null, everywhere, Callable(), TileEdges.Look.COAST, TILE_EDGE_UNIT).size(),
		"the walk with no region reading": TileEdges.seams(
			model, everywhere, Callable(), TileEdges.Look.OUTSIDE, TILE_EDGE_UNIT
		).size(),
		"the walk with no tile reading": TileEdges.seams(
			model, Callable(), model.province_at, TileEdges.Look.COAST, TILE_EDGE_UNIT
		).size(),
		"an inset that has not measured its tile": TileEdges.province_seams(model, everywhere, 0.0).size(),
		"a chart that was never generated": TileEdges.sea_seams(empty_chart, everywhere, TILE_EDGE_UNIT).size(),
	}
	assert_eq(empty_chart.width * empty_chart.height, 0, "an empty chart has no tiles")
	for case: String in inks.keys():
		assert_eq(int(inks[case]), 0, "%s inks nothing" % case)


## Every slot of the wheel, so the hill, the wall, the coast and the step that
## leaves the chart all ink on the side they belong to.
func test_each_edge_step_points_at_its_neighbour() -> void:
	assert_eq(TileEdges.step(TileEdges.Edge.TOP), Vector2i(0, -1))
	assert_eq(TileEdges.step(TileEdges.Edge.RIGHT), Vector2i(1, 0))
	assert_eq(TileEdges.step(TileEdges.Edge.BOTTOM), Vector2i(0, 1))
	assert_eq(TileEdges.step(TileEdges.Edge.LEFT), Vector2i(-1, 0))
	assert_eq(TileEdges.ALL_EDGES.size(), 4)


## A sea zone inks its own ring: every zone's border draws, and none of them is
## drawn twice for the same tile.
func test_a_sea_zone_inks_its_own_ring() -> void:
	var model: MapModel = _charted_after_first_region()
	var zone: SeaZoneState = model.sea_zones[0]
	var mine := func(x: int, y: int) -> bool:
		return model.sea_zone_at(x, y) == zone.id
	var seams: Array[PackedVector2Array] = TileEdges.sea_seams(model, mine, TILE_EDGE_UNIT)
	assert_gt(seams.size(), 3, "a sea zone inks a closed ring")
	var seen: Dictionary = {}
	for path: PackedVector2Array in seams:
		assert_eq(path.size(), 2)
		var key: String = str(path)
		assert_false(seen.has(key), "a zone seam is inked once")
		seen[key] = true
