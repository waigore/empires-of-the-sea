# gdlint: disable=max-public-methods
extends GdToolsTest
## Lean chrome boot: HudCampaignEnd + GameHud routing, app icon / launcher
## branding, court heraldry, TileEdges seam walks, OrderVerdict shape, the
## PlayScreen bridge doubles, ChartTap, HudSheet, and counsel-pick prose
## (REQ-P3-01, REQ-P1-02/03/08, REQ-P3-02, REQ-P3-04). The full calendar-cap
## MapScreen theme lives in test_campaign_end; this suite stays lean so a
## chrome, branding, heraldry, seam, verdict, bridge, tap, sheet or pick-prose
## extract stays inside the tier-1 5 min budget. Merged from test_branding_rules,
## test_heraldry, test_tile_edges, test_order_verdict, test_play_screen,
## test_chart_tap, test_hud_sheet and test_map_play_pick_prose (one Godot boot
## for the leftovers; docs/testing.md).

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


## The dossier names what a rival's leader brings, in the bonus table's own
## words, and a crown that fields no leader (a Minor) names no effect at all
## (wiki: leader-bonuses § Bonus Table, § Acceptance criteria — UI).
func test_the_dossier_names_the_effect_a_rivals_leader_brings() -> void:
	var state := DiplomacyState.new()
	state.initialize(1)
	var sheet := CourtDossierScreen.new()
	add_child(sheet)
	sheet.show_for(state, null, 0, 2)
	assert_true(_has_text(sheet, "Napoleon"), "France's leader reads on its page")
	assert_true(
		_has_text(sheet, LeaderCatalog.bonus_label("napoleon")),
		"and the effect that key publishes"
	)
	sheet.show_for(state, null, 0, 1)
	assert_true(_has_text(sheet, LeaderCatalog.bonus_label("victoria")), "England's own")
	assert_false(_has_text(sheet, "no bonus"), "a Great Power fields a published bonus")
	sheet.show_for(state, null, 0, 6)
	assert_false(_has_text(sheet, "no bonus"), "a Minor fields no leader, so it prints none")
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
## (REQ-P3-01, REQ-P3-03). Rides the lean chrome boot with heraldry and branding
## on a hand-built pocket chart, so the boot pays no world draw.


const TILE_EDGE_UNIT: float = 22.0

## The pocket chart's one inland province: a 6×6 block ringed by the coastal
## province, so `inland_province` reads a closed outline that touches no sea.
const POCKET_WIDTH: int = 14
const POCKET_HEIGHT: int = 12
const POCKET_INLAND := Rect2i(4, 3, 6, 6)
const POCKET_LAND := Rect2i(2, 2, 10, 8)

## The walk reads terrain and province ids only, so the seam cases ink a
## hand-built chart instead of `MapFixture.region()`'s 48×32 `generate`. This
## suite stays a lean chrome boot; paying a world draw for eight pure readings
## broke that (docs/testing.md § Speed rules — tiny fixture first).
static var _pocket_chart: MapModel = null


func _pocket() -> MapModel:
	if _pocket_chart != null:
		return _pocket_chart
	var count: int = POCKET_WIDTH * POCKET_HEIGHT
	var terrain := PackedByteArray()
	terrain.resize(count)
	terrain.fill(MapModel.Terrain.OCEAN)
	var province := PackedInt32Array()
	province.resize(count)
	province.fill(MapModel.NO_ID)
	var sea_zone := PackedInt32Array()
	sea_zone.resize(count)
	sea_zone.fill(0)
	var inland: Array[Vector2i] = []
	var coast: Array[Vector2i] = []
	var open_sea: Array[Vector2i] = []
	for y in POCKET_HEIGHT:
		for x in POCKET_WIDTH:
			var index: int = y * POCKET_WIDTH + x
			if not POCKET_LAND.has_point(Vector2i(x, y)):
				open_sea.append(Vector2i(x, y))
				continue
			sea_zone[index] = MapModel.NO_ID
			terrain[index] = MapModel.Terrain.PLAINS
			if POCKET_INLAND.has_point(Vector2i(x, y)):
				province[index] = 0
				inland.append(Vector2i(x, y))
			else:
				province[index] = 1
				coast.append(Vector2i(x, y))
	var model := MapModel.new()
	model.setup(POCKET_WIDTH, POCKET_HEIGHT)
	model.terrain = terrain
	model.province = province
	model.sea_zone = sea_zone
	model.provinces.append(ProvinceState.create(
		0, "Pocket Inland", inland, Vector2(6.5, 5.5), inland.size(), 0, true
	))
	var ring := ProvinceState.create(
		1, "Pocket Coast", coast, Vector2(2.0, 2.0), coast.size(), 0, false
	)
	ring.coastal = true
	model.provinces.append(ring)
	model.sea_zones.append(SeaZoneState.create(
		0, "Pocket Sea", open_sea, Vector2(0.5, 0.5), open_sea.size()
	))
	_pocket_chart = model
	return _pocket_chart


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
	var model: MapModel = _pocket()
	assert_eq(model.province_at(-1, 0), MapModel.NO_ID)
	assert_eq(model.sea_zone_at(model.width, 0), MapModel.NO_ID)


## A closed province outline traces each seam once and stays on that province's
## own tiles.
func test_a_province_outline_keeps_every_seam_once_and_bounded() -> void:
	var model: MapModel = _pocket()
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
	var model: MapModel = _pocket()
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
	var model: MapModel = _pocket()
	var land := func(x: int, y: int) -> bool:
		return model.is_land(x, y)
	var coast: Array[PackedVector2Array] = TileEdges.province_seams(
		model, land, TILE_EDGE_UNIT, TileEdges.Look.COAST
	)
	assert_gt(coast.size(), 0, "the pocket chart has a coast")
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
	var model: MapModel = _pocket()
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
	var model: MapModel = _pocket()
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
	var model: MapModel = _pocket()
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
	var model: MapModel = _pocket()
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

# --- order verdict (folded from test_order_verdict) ---------------------------

## One home for an order verdict: the accept/refuse shape every army, navy,
## market and court order check returns (REQ-P3-01, REQ-P3-03).


func test_an_allowed_order_is_ok_with_no_reason() -> void:
	assert_eq(OrderVerdict.allow(), {"ok": true, "reason": ""})


func test_a_refused_order_carries_its_reason() -> void:
	assert_eq(
		OrderVerdict.deny("A fleet may only dock in a province it owns."),
		{"ok": false, "reason": "A fleet may only dock in a province it owns."}
	)


func test_an_allowed_order_keeps_the_rules_own_fields() -> void:
	var verdict: Dictionary = OrderVerdict.allow({"unit": "frigate", "cost": 40})
	assert_true(bool(verdict["ok"]), "an accept stays an accept")
	assert_eq(String(verdict["reason"]), "", "an accept has no reason")
	assert_eq(String(verdict["unit"]), "frigate", "the rule's unit rides along")
	assert_eq(int(verdict["cost"]), 40, "the rule's cost rides along")


func test_a_refused_order_keeps_the_rules_denied_fields() -> void:
	var verdict: Dictionary = OrderVerdict.deny("There is no army to split.", {"army": null})
	assert_false(bool(verdict["ok"]), "a refusal stays a refusal")
	assert_eq(String(verdict["reason"]), "There is no army to split.")
	assert_true(verdict.has("army"), "the denied field is present")
	assert_eq(verdict["army"], null, "the denied field reads its empty value")


func test_a_real_order_check_builds_its_verdict_here() -> void:
	var split: Dictionary = ArmyRoster.split([] as Array[ArmyState], null, [] as Array[String], 0)
	assert_false(bool(split.get("ok", true)), "a null army is refused")
	assert_true(split.has("army"), "the refusal carries the army field")
	assert_eq(split["army"], null, "and that field is null")


# --- play screen bridge (folded from test_play_screen) ------------------------

## PlayScreen: the one way a MapPlay* helper speaks to the screen (REQ-P3-02).
## The bridge keeps the host in one place, so a helper never grows a node path
## to the chart.


## A screen double with every signal and door MapScreen offers.
class FakeScreen extends Node:
	signal province_selected(province_id: int)
	signal selection_cleared
	signal coast_charted(province_id: int)
	signal battle_resolved(battles: Array[Dictionary])
	signal raid_resolved(raids: Array[Dictionary])
	signal turn_ended(turn: int)
	signal victory_declared(victory: VictoryState)
	signal defeat_declared(defeat: DefeatState)

	var repaints: int = 0
	var regions: Array[int] = []


	func refresh_political_map() -> void:
		repaints += 1


	func load_region(index: int) -> void:
		regions.append(index)


## A bare Node: none of the screen's signals or doors.
class PlainScreen extends Node:
	pass


func _bridge(host: Node) -> PlayScreen:
	var screen := PlayScreen.new()
	screen.host = host
	return screen


## A headless run binds no host: every airing is inert and the viewport unknown.
func test_an_unbound_screen_stays_silent() -> void:
	var screen := PlayScreen.new()

	assert_eq(screen.viewport(), null, "no host reads no viewport")
	screen.emit_province_selected(3)
	screen.emit_selection_cleared()
	screen.emit_coast_charted(4)
	screen.emit_battle_resolved([] as Array[Dictionary])
	screen.emit_raid_resolved([] as Array[Dictionary])
	screen.emit_turn_ended(9)
	screen.emit_campaign_end(VictoryState.new())
	screen.emit_campaign_end(VictoryState.new(), DefeatState.new())
	screen.refresh_map_views()
	screen.switch_region(1)

	assert_eq(screen.host, null, "an inert bridge stays unbound")


func test_a_bound_screen_hears_the_courts_airings() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)
	var heard: Array = []
	host.province_selected.connect(
		func(province_id: int) -> void: heard.append(["province", province_id])
	)
	host.selection_cleared.connect(func() -> void: heard.append("cleared"))
	host.coast_charted.connect(
		func(province_id: int) -> void: heard.append(["coast", province_id])
	)
	host.turn_ended.connect(func(turn: int) -> void: heard.append(["turn", turn]))
	host.battle_resolved.connect(
		func(battles: Array[Dictionary]) -> void: heard.append(["battle", battles.size()])
	)
	host.raid_resolved.connect(
		func(raids: Array[Dictionary]) -> void: heard.append(["raid", raids.size()])
	)

	screen.emit_province_selected(3)
	screen.emit_selection_cleared()
	screen.emit_coast_charted(4)
	screen.emit_turn_ended(9)
	screen.emit_battle_resolved([] as Array[Dictionary])
	screen.emit_raid_resolved([] as Array[Dictionary])

	assert_eq(
		heard,
		[["province", 3], "cleared", ["coast", 4], ["turn", 9], ["battle", 0], ["raid", 0]],
		"each airing reaches the screen's own signal"
	)
	assert_true(screen.viewport() != null, "a mounted host reads its viewport")
	host.free()


## A land fight and a sea fight both air on the same signal: the host answers
## the plate, not the kind (wiki: dialogue-and-mood § Design intent).
func test_battle_airings_keep_every_record() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)
	var landed: Array = []
	host.battle_resolved.connect(
		func(battles: Array[Dictionary]) -> void: landed.append(battles)
	)
	var battles: Array[Dictionary] = [
		{"province": 2, "attacker": 0, "defender": 1},
		{"zone": 5, "attacker": 0, "defender": 1},
	] as Array[Dictionary]

	screen.emit_battle_resolved(battles)

	assert_eq(landed.size(), 1, "one resolved turn airs once")
	assert_eq((landed[0] as Array).size(), 2, "both fights ride the airing")
	host.free()


## The crown's fall outranks a victory in the same moment, so the screen hears
## one closing, never two (wiki: victory § Great Power defeat).
func test_a_fall_closes_the_screen_before_the_victory() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)
	var heard: Array = []
	host.victory_declared.connect(
		func(victory: VictoryState) -> void: heard.append(["victory", victory])
	)
	host.defeat_declared.connect(
		func(defeat: DefeatState) -> void: heard.append(["defeat", defeat])
	)
	var victory := VictoryState.new()
	var defeat := DefeatState.new()

	screen.emit_campaign_end(victory, defeat)
	assert_eq(heard.size(), 1, "one closing airs")
	assert_eq(heard[0][0], "defeat", "the crown's fall is the closing")

	heard.clear()
	screen.emit_campaign_end(victory)
	assert_eq(heard, [["victory", victory]], "a victory alone airs as a victory")

	heard.clear()
	screen.emit_campaign_end()
	assert_eq(heard, [], "no closing airs nothing")
	host.free()


## A host that never declared the raid signal, or the redraw and region doors,
## stays silent instead of raising: the harness screens are partial.
func test_a_partial_screen_stays_silent() -> void:
	var host := PlainScreen.new()
	add_child(host)
	var screen := _bridge(host)

	screen.emit_raid_resolved([] as Array[Dictionary])
	screen.refresh_map_views()
	screen.switch_region(2)

	assert_true(screen.viewport() != null, "the viewport still answers")
	host.free()


func test_the_map_asks_the_screen_to_redraw_or_swap() -> void:
	var host := FakeScreen.new()
	add_child(host)
	var screen := _bridge(host)

	screen.refresh_map_views()
	screen.switch_region(0)
	screen.switch_region(2)

	assert_eq(host.repaints, 1, "a political change asks one repaint")
	assert_eq(host.regions, [0, 2], "a crossing swaps to the named region")
	host.free()


## The session owns the bridge: binding a host wires it, and a resolved battle
## books the courts then airs on that screen (PlaySession keeps the booking).
func test_the_session_airs_a_battle_through_its_bridge() -> void:
	var play := PlaySession.new()
	assert_true(play.screen != null, "a fresh session carries its screen bridge")
	if play.screen == null:
		return
	var host := FakeScreen.new()
	add_child(host)
	var aired: Array = []
	host.battle_resolved.connect(
		func(battles: Array[Dictionary]) -> void: aired.append(battles.size())
	)

	play.bind_host(host)
	play.emit_battle_resolved([{"province": 1, "attacker": 0, "defender": 1}] as Array[Dictionary])

	assert_eq(play.screen.host, host, "the bound host is the bridge's own")
	assert_eq(aired, [1], "the bridge airs the fight the session booked")
	host.free()


# --- chart tap (folded from test_chart_tap) -----------------------------------
## The chart's tap law (REQ-P3-04): one press slot per input stream, a release
## close to its press is a tap, and the same tap seen twice in one frame is
## answered once. Pure — no viewport, no nodes.

const _TAP_START := Vector2(400.0, 300.0)


func test_a_touch_press_answers_nothing() -> void:
	var taps := ChartTap.new()
	assert_eq(taps.touch(true, 0, _TAP_START), Vector2.INF, "a press is not a tap")


func test_a_touch_release_close_to_its_press_is_a_tap() -> void:
	var taps := ChartTap.new()
	taps.touch(true, 0, _TAP_START)
	assert_eq(
		taps.touch(false, 0, _TAP_START + Vector2(1.0, 1.0)),
		_TAP_START + Vector2(1.0, 1.0)
	)


func test_a_drag_is_not_a_tap() -> void:
	var taps := ChartTap.new()
	taps.touch(true, 0, _TAP_START)
	var far: Vector2 = _TAP_START + Vector2(ChartTap.SLOP + 1.0, 0.0)
	assert_eq(taps.touch(false, 0, far), Vector2.INF, "a pan belongs to the camera")


func test_a_release_without_its_own_press_answers_nothing() -> void:
	var taps := ChartTap.new()
	assert_eq(taps.touch(false, 0, _TAP_START), Vector2.INF, "no press, no tap")
	taps.touch(true, 0, _TAP_START)
	assert_eq(taps.touch(false, 1, _TAP_START), Vector2.INF, "another finger's release")


func test_a_mouse_click_is_a_tap() -> void:
	var taps := ChartTap.new()
	assert_eq(taps.mouse(true, _TAP_START), Vector2.INF)
	assert_eq(taps.mouse(false, _TAP_START), _TAP_START)


func test_a_touch_and_its_emulated_click_keep_their_own_presses() -> void:
	var taps := ChartTap.new()
	taps.touch(true, 0, _TAP_START)
	taps.mouse(true, _TAP_START)
	assert_eq(taps.touch(false, 0, _TAP_START), _TAP_START, "the touch release answers")
	assert_eq(taps.mouse(false, _TAP_START), _TAP_START, "the emulated release answers too")


func test_the_same_tap_in_one_frame_is_a_repeat() -> void:
	var taps := ChartTap.new()
	assert_false(taps.is_repeat(7, _TAP_START), "the first answer is not a repeat")
	taps.mark_answered(7, _TAP_START)
	assert_true(
		taps.is_repeat(7, _TAP_START + Vector2(0.1, 0.0)), "the second path is silent"
	)
	assert_false(taps.is_repeat(8, _TAP_START), "the next frame is a new tap")
	assert_false(
		taps.is_repeat(7, _TAP_START + Vector2(ChartTap.MERGE_DISTANCE + 1.0, 0.0)),
		"a tap elsewhere is its own answer"
	)


# --- hud sheet (folded from test_hud_sheet) -----------------------------------
## HudSheet: one reveal law for every HUD sheet, and HudPanels.every() as the
## single list of sheets on the dock rail and on a door (REQ-P3-01, REQ-P1-05).


class _SheetStubSlot:
	extends HudPanelSlot

	var reveals: int = 0
	var conceals: int = 0

	func reveal(_host: Node, _dock: PanelDock) -> void:
		if open:
			return
		reveals += 1
		open = true

	func conceal(_host: Node, _dock: PanelDock) -> void:
		if not open:
			return
		conceals += 1
		open = false


func test_show_reveals_once_and_repaints_while_open() -> void:
	var slot := _SheetStubSlot.new()
	slot.slides = false
	var painted: Array[String] = []
	HudSheet.show(null, null, slot, func() -> void: painted.append("paint"))
	HudSheet.show(null, null, slot, func() -> void: painted.append("paint"))
	assert_eq(slot.reveals, 1, "a sheet already up is not revealed again")
	assert_eq(painted.size(), 2, "every show paints the newest reading")


func test_hide_sets_aside_once() -> void:
	var slot := _SheetStubSlot.new()
	slot.slides = false
	HudSheet.show(null, null, slot, func() -> void: pass)
	HudSheet.hide(null, null, slot)
	HudSheet.hide(null, null, slot)
	assert_eq(slot.conceals, 1, "the law hands conceal to the slot")
	assert_false(slot.open, "the sheet reads closed after one hide")


func test_show_presses_the_toggles_face_and_hide_lets_it_go() -> void:
	var slot := _SheetStubSlot.new()
	slot.slides = false
	var toggle := CheckBox.new()
	add_child(toggle)
	HudSheet.show(null, null, slot, func() -> void: pass, toggle)
	assert_true(toggle.button_pressed, "the door reads open")
	HudSheet.hide(null, null, slot, toggle)
	assert_false(toggle.button_pressed, "the door reads closed")
	toggle.queue_free()


func test_every_lists_the_rail_and_the_ledgers() -> void:
	var panels := HudPanels.new()
	assert_eq(panels.every().size(), 0, "a bare host names no sheet")
	panels.province = _SheetStubSlot.new()
	panels.fleet = _SheetStubSlot.new()
	panels.civilian = _SheetStubSlot.new()
	panels.army = _SheetStubSlot.new()
	panels.economy = _SheetStubSlot.new()
	panels.research = _SheetStubSlot.new()
	panels.diplomacy = _SheetStubSlot.new()
	assert_eq(panels.selections().size(), 4, "the dock rail keeps four dossiers")
	var all: Array[HudPanelSlot] = panels.every()
	assert_eq(all.size(), 7, "every sheet rides one list")
	for slot: HudPanelSlot in all:
		# The dock side and the lane cover read every entry: a bare null would
		# crash them, so the list never pads itself with empty slots.
		assert_not_null(slot, "every() names only real sheets")


# --- pick prose (folded from test_map_play_pick_prose) ------------------------
## Shared counsel-pick chrome: one sentence, one prose join, one capped line, one
## court line, one gate and one row order.


func test_sentence_opens_and_closes() -> void:
	assert_eq(MapPlayPickProse.sentence(""), "", "no clause, no sentence")
	assert_eq(
		MapPlayPickProse.sentence("the court would raise the farm"),
		"The court would raise the farm.",
		"one capital and a full stop"
	)


func test_a_pick_prints_as_one_sentence() -> void:
	assert_eq(MapPlayPickProse.sentence_of({}), "", "no pick, no sentence")
	assert_eq(
		MapPlayPickProse.sentence_of({"line": "the court would raise the farm"}),
		"The court would raise the farm.",
		"the pick's own clause is the sentence"
	)


func test_join_reads_as_prose() -> void:
	assert_eq(MapPlayPickProse.join([]), "", "empty list")
	assert_eq(MapPlayPickProse.join(["A"]), "A", "one part")
	assert_eq(MapPlayPickProse.join(["A", "B"]), "A and B", "two parts")
	assert_eq(
		MapPlayPickProse.join(["A", "B", "C"]),
		"A, B and C",
		"three parts take a comma and a final and"
	)


func test_capped_counts_the_rest() -> void:
	assert_eq(MapPlayPickProse.capped([], 3), "", "nothing named")
	assert_eq(
		MapPlayPickProse.capped(["A", "B", "C"], 3),
		"A, B and C",
		"under the limit keeps prose join"
	)
	assert_eq(
		MapPlayPickProse.capped(["A", "B", "C", "D", "E"], 3),
		"A, B, C and 2 more",
		"over the limit commas the heads and counts the rest"
	)
	assert_eq(
		MapPlayPickProse.capped(["A", "B"], 3, 2),
		"A, B and 2 more",
		"a repeated clause still counts the crews behind it"
	)
	assert_eq(
		MapPlayPickProse.capped(["A"], 3, 1),
		"A and 1 more",
		"one clause standing for two crews says so"
	)
	assert_eq(MapPlayPickProse.capped(["A"], 0), "", "no room, no line")


func test_a_repeated_clause_collapses_and_still_counts_its_crews() -> void:
	var unique: Dictionary = MapPlayPickProse.unique_clauses(["A", "A", "", "B", "A"])
	var kept: Array[String] = []
	kept.assign(unique.get("clauses", []))
	assert_eq(kept.size(), 2, "each order is named once")
	assert_eq(kept[0], "A", "the first wording holds its place")
	assert_eq(kept[1], "B", "the rest keeps its order")
	assert_eq(int(unique.get("extra", 0)), 2, "both repeats are counted")
	var none: Dictionary = MapPlayPickProse.unique_clauses([])
	assert_eq(int(none.get("extra", 0)), 0, "nothing to count")
	assert_eq((none.get("clauses", []) as Array).size(), 0, "nothing to name")


func test_the_court_line_caps_and_drops_blanks() -> void:
	assert_eq(
		MapPlayPickProse.court_line("the court would send", []),
		"",
		"nothing named, no line"
	)
	assert_eq(
		MapPlayPickProse.court_line("the court would send", ["", ""]),
		"",
		"blank clauses name nothing"
	)
	assert_eq(
		MapPlayPickProse.court_line("the court would send", ["the Leopard", "", "the Tern"]),
		"the court would send the Leopard and the Tern this turn",
		"blanks drop out and a pair reads as prose"
	)
	assert_eq(
		MapPlayPickProse.court_line(
			"the court would put", ["A", "B", "C", "D"], "this phase"
		),
		"the court would put A, B, C and 1 more this phase",
		"a busy line caps and counts the rest"
	)
	assert_eq(
		MapPlayPickProse.court_line("the court would", ["walk its Spy"], ""),
		"the court would walk its Spy",
		"an empty tail closes on the clause alone"
	)


func test_a_sheet_can_name_more_than_the_common_cap() -> void:
	assert_eq(
		MapPlayPickProse.court_line_capped(
			"the court would run", ["A", "B", "C", "D"], "this phase", 4
		),
		"the court would run A, B, C and D this phase",
		"a wide sheet's own cap names the fourth row"
	)
	assert_eq(
		MapPlayPickProse.court_line_capped(
			"the court would run", ["A", "B", "C", "D", "E"], "this phase", 4
		),
		"the court would run A, B, C, D and 1 more this phase",
		"past its own cap it still counts the rest"
	)
	assert_eq(
		MapPlayPickProse.court_line_capped("the court would run", [], "this phase", 4),
		"",
		"nothing named, no line"
	)


## The sheets read their chrome from one place (REQ-P3-01): a sheet that names
## nothing hands the shared line an empty list and prints no headless sentence
## instead of the sheet keeping its own copy of the rule (REQ-P3-02).
func test_a_sheet_that_names_nothing_prints_no_line() -> void:
	assert_eq(MapPlayMarketPick.list_line({}, "offer"), "", "market: no rows")
	assert_eq(MapPlayProductionPick.run_line({}), "", "production: no runs")
	assert_eq(MapPlayRecruitPick.recruit_line({}), "", "recruit: no tiers")


func test_a_silent_pass_earns_a_gate_only_when_something_waited() -> void:
	assert_true(MapPlayPickProse.gate(0, "crews", "none").is_empty(), "nobody waiting")
	var gate: Dictionary = MapPlayPickProse.gate(2, "squadrons", "no sail")
	assert_eq(String(gate["line"]), "no sail", "the gate names the silence")
	assert_eq((gate["squadrons"] as Array).size(), 0, "a gate carries no rows")
	assert_false(gate.has("crews"), "the rows key is the sheet's own")


func test_a_row_key_reads_the_chart_and_the_id() -> void:
	assert_eq(
		MapPlayPickProse.row_key({"region": 2, "army": 7}, "army"),
		"2:7",
		"chart and id"
	)
	assert_eq(
		MapPlayPickProse.row_key({"army": 7}, "army"),
		"-1:7",
		"a row with no chart still keys"
	)
	assert_eq(
		MapPlayPickProse.row_key({"region": 0, "fleet": 3}, "fleet_id", "fleet"),
		"0:3",
		"a heading's own name fills in for the pick's"
	)
	assert_eq(
		MapPlayPickProse.row_key({"region": 0, "fleet_id": 4, "fleet": 3}, "fleet_id", "fleet"),
		"0:4",
		"the pick's own name wins when both are there"
	)


func test_rows_keep_the_order_the_sheet_prints() -> void:
	var rows: Array[Dictionary] = [
		{"region": 0, "army": 2}, {"region": 0, "army": 1}, {"region": 0, "army": 3},
	]
	var printed: Array = [
		{"region": 0, "army": 1}, {"region": 0, "army": 2}, {"region": 0, "army": 3},
	]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, printed, "army")
	assert_eq(int(ordered[0]["army"]), 1, "the sheet's first row leads")
	assert_eq(int(ordered[1]["army"]), 2, "the sheet's second row follows")
	assert_eq(int(ordered[2]["army"]), 3, "the sheet's third row closes")


func test_rows_the_sheet_does_not_print_keep_the_passs_order() -> void:
	var rows: Array[Dictionary] = [
		{"region": 0, "unit_id": 9},
		{"region": 0, "unit_id": 2},
		{"region": 0, "unit_id": 4},
	]
	var printed: Array = [{"region": 0, "unit_id": 2}]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, printed, "unit_id")
	assert_eq(int(ordered[0]["unit_id"]), 2, "the printed row leads")
	assert_eq(int(ordered[1]["unit_id"]), 4, "unprinted rows close behind, id first")
	assert_eq(int(ordered[2]["unit_id"]), 9, "unprinted rows close behind, id first")


func test_an_empty_snapshot_keeps_the_passs_order() -> void:
	var rows: Array[Dictionary] = [{"region": 0, "army": 2}, {"region": 0, "army": 1}]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, [], "army")
	assert_true(ordered == rows, "no printed rows, the pass's own order stands")
	assert_eq(int(ordered[0]["army"]), 2, "the pass's first row leads")


func test_a_duplicated_heading_reads_once_and_ids_break_ties() -> void:
	var rows: Array[Dictionary] = [
		{"region": 0, "army": 5}, {"region": 0, "army": 4}, {"region": 0, "army": 3},
	]
	# Both groups name army 3, so the second copy adds no place on the page.
	var printed: Array = [
		{"region": 0, "army": 3}, {"region": 0, "army": 3},
	]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(rows, printed, "army")
	assert_eq(int(ordered[0]["army"]), 3, "the printed row leads")
	assert_eq(int(ordered[1]["army"]), 4, "the id breaks the tie")
	assert_eq(int(ordered[2]["army"]), 5, "the id breaks the tie")


func test_the_heading_name_reads_a_squadron_group() -> void:
	var squadrons: Array[Dictionary] = [
		{"region": 0, "fleet_id": 2}, {"region": 0, "fleet_id": 1},
	]
	var groups: Array = [{"region": 0, "fleet": 1}, {"region": 0, "fleet": 2}]
	var ordered: Array[Dictionary] = MapPlayPickProse.in_printed_order(
		squadrons, groups, "fleet_id", "fleet"
	)
	assert_eq(int(ordered[0]["fleet_id"]), 1, "a heading's fleet name orders the pick")
	assert_eq(int(ordered[1]["fleet_id"]), 2, "a heading's fleet name orders the pick")


func test_crown_crew_ready_refuses_a_missing_session() -> void:
	assert_false(
		MapPlayPickProse.crown_crew_ready(null),
		"no session, no counsel pick"
	)


func test_crown_ready_refuses_a_missing_session() -> void:
	assert_false(MapPlayPickProse.crown_ready(null), "no session, no counsel pick")


func test_the_crew_gate_stands_on_the_crown_gate() -> void:
	var slim: PlaySession = PlaySession.new()
	slim.ai_mode = AiControl.NOOP
	assert_false(
		MapPlayPickProse.crown_crew_ready(slim),
		"a court with no planner earns no crew counsel either"
	)
	assert_false(
		MapPlayPickProse.crown_ready(slim),
		"a court with no planner reads no counsel at all"
	)
