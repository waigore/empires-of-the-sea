# gdlint: disable=max-public-methods
extends GdToolsTest
## Lean chrome + audio boot: HudCampaignEnd + GameHud routing, branding,
## heraldry, TileEdges, OrderVerdict, PlayScreen bridge, ChartTap, HudSheet,
## counsel-pick prose, playtest capture, and the mix / director / soundtrack
## (REQ-P3-01, REQ-P1-02/03/06/08, REQ-P3-02, REQ-P3-04). Folded from
## test_audio_rules so coverage pays one Godot process instead of two. The
## full calendar-cap MapScreen theme lives in test_campaign_rules; this suite
## stays the leftovers boot (docs/testing.md).

const MapFixture = preload("res://tests/map_fixture.gd")
const Fixture = preload("res://tests/map_fixture.gd")

## Playtest capture scratch folder (folded from test_playtest_capture).
const CAPTURE_DIR: String = "user://test_playtest_capture"

var _host: Control = null
var _overlay: VictoryOverlay = null
var _seal: Button = null
var _glow: Panel = null
var _end: HudCampaignEnd = null
var _hud: GameHud = null
var _suite_setup: String = ""


func before_all() -> void:
	InputActions.ensure_actions()
	# Audio score cases mount lazily onto this host (folded from test_audio_rules).
	_audio_host = self
	_world_snapshot = Fixture.snapshot(Fixture.world())


func before_each() -> void:
	_remove_capture_dir(CAPTURE_DIR)
	# Mix/director never mount; park the score chart between soundtrack cases.
	Fixture.park_screen(_screen)


func after_each() -> void:
	match _suite_setup:
		"chrome":
			_teardown_chrome()
		"audio_mix":
			_teardown_audio_mix()
		"audio_director":
			_teardown_audio_director()
		"map_soundtrack":
			_after_soundtrack()
		"app_shell":
			_after_shell()
	_suite_setup = ""


func after_all() -> void:
	_remove_capture_dir(CAPTURE_DIR)
	if is_instance_valid(_app):
		_app.free()
	_app = null
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	_audio = null
	_score = null
	_pristine = {}
	_world_snapshot = []
	_audio_host = null


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


# --- folded: playtest capture (issue #1393) ------------------------------------
## Session metadata, report composite, overlay chrome and controller state.
## Capture IO (viewport grab, ffmpeg) stays a desktop hand-check; these cases
## prove the pure shapes so headless CI never needs a display or encoder.

func _remove_capture_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for sub: String in dir.get_directories():
		_remove_capture_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _play() -> PlaySession:
	var play: PlaySession = PlaySession.new()
	play.map_seed = 1500
	play.turn = 12
	play.player_faction = 0
	play.region_index = 0
	return play


# --- metadata ---------------------------------------------------------------


func test_meta_carries_session_parameters() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "2026-11-23T05:13:17")
	assert_eq(int(meta["seed"]), 1500, "the map seed rides every artifact")
	assert_eq(int(meta["turn"]), 12, "the turn rides every artifact")
	assert_eq(int(meta["year"]), TurnTime.year_for_turn(12), "the year is derived")
	assert_eq(str(meta["crown"]), "Spain", "the crown is named")
	assert_eq(int(meta["crown_id"]), 0, "the crown id is kept")
	assert_eq(str(meta["region"]), "Old World", "the region is named")
	assert_eq(str(meta["build"]), GameVersion.as_string(), "the build is named")
	assert_eq(str(meta["commit"]), "dev", "an unbaked build says dev")
	assert_eq(str(meta["platform"]), PlaytestPlatform.label(), "the platform is named")
	assert_eq(str(meta["timestamp"]), "2026-11-23T05:13:17", "the stamp is kept")


func test_meta_handles_a_missing_session() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(null, "stamp")
	assert_eq(int(meta["seed"]), 0, "no session, no seed")
	assert_eq(str(meta["crown"]), PlaytestCaptureMeta.UNKNOWN, "no session, no crown")
	assert_eq(str(meta["region"]), PlaytestCaptureMeta.UNKNOWN, "no session, no region")
	assert_eq(str(meta["timestamp"]), "stamp", "the stamp still lands")


func test_meta_names_the_observer_seat() -> void:
	var play: PlaySession = _play()
	play.observer_mode = true
	assert_eq(PlaytestCaptureMeta.crown_name(play), "Observer", "the observer holds no crown")


func test_meta_region_out_of_range_is_unknown() -> void:
	assert_eq(PlaytestCaptureMeta.region_label(-1), PlaytestCaptureMeta.UNKNOWN)
	assert_eq(PlaytestCaptureMeta.region_label(99), PlaytestCaptureMeta.UNKNOWN)


func test_session_dir_name_is_filesystem_safe() -> void:
	var name: String = PlaytestCaptureMeta.session_dir_name(1500, "2026-11-23T05:13:17")
	assert_eq(name, "session-2026-11-23-051317-seed1500", "no colon or T in a folder name")
	assert_false(name.contains(":"), "a colon would break Windows")
	assert_false(name.contains("T"), "the ISO T is replaced")


# --- report -----------------------------------------------------------------


func _report() -> Dictionary:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "2026-11-23T05:13:17")
	var item: Dictionary = PlaytestReport.entry(
		"screenshot", "shot-0001.png", "The fleet is stuck on the reef.", meta
	)
	return PlaytestReport.compose(meta, [item])


func test_markdown_lists_the_capture_and_its_comment() -> void:
	var text: String = PlaytestReport.to_markdown(_report())
	assert_true(text.contains("# Playtest report"), "the page has a title")
	assert_true(text.contains("Seed: 1500"), "the header carries the seed")
	assert_true(text.contains("shot-0001.png"), "the capture is listed")
	assert_true(text.contains("The fleet is stuck on the reef."), "the comment is listed")
	assert_true(text.contains("Turn: 12"), "the capture carries its turn")


func test_markdown_says_when_nothing_is_captured() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "stamp")
	var text: String = PlaytestReport.to_markdown(PlaytestReport.compose(meta, []))
	assert_true(text.contains("_No captures yet._"), "an empty report says so")


func test_json_round_trips() -> void:
	var report: Dictionary = _report()
	var parsed: Variant = JSON.parse_string(PlaytestReport.to_json(report))
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the JSON is an object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	assert_eq(int(parsed["meta"]["seed"]), 1500, "the seed survives the round trip")
	assert_eq(str(parsed["entries"][0]["comment"]), "The fleet is stuck on the reef.")


func test_write_creates_both_faces() -> void:
	assert_true(PlaytestReport.write(CAPTURE_DIR, _report()), "the report writes")
	assert_true(FileAccess.file_exists(CAPTURE_DIR.path_join(PlaytestReport.REPORT_MD)))
	assert_true(FileAccess.file_exists(CAPTURE_DIR.path_join(PlaytestReport.REPORT_JSON)))
	var md: FileAccess = FileAccess.open(CAPTURE_DIR.path_join(PlaytestReport.REPORT_MD), FileAccess.READ)
	assert_true(md.get_as_text().contains("shot-0001.png"), "the Markdown is on disk")
	md.close()


func test_write_refuses_an_empty_folder() -> void:
	assert_false(PlaytestReport.write("", _report()), "no folder, no report")


func test_issue_draft_uses_the_comment_and_session() -> void:
	var report: Dictionary = _report()
	var draft: Dictionary = PlaytestReport.issue_draft(
		report["entries"][0], report["meta"]
	)
	assert_eq(str(draft["title"]), "[Playtest] The fleet is stuck on the reef.")
	assert_eq(draft["labels"], ["todo", "bug"], "a defect draft is todo + bug")
	assert_true(str(draft["body"]).contains("Seed: 1500"), "the body carries the seed")
	assert_true(str(draft["body"]).contains("shot-0001.png"), "the body names the file")


func test_issue_draft_falls_back_to_the_kind() -> void:
	var meta: Dictionary = PlaytestCaptureMeta.build(_play(), "stamp")
	var item: Dictionary = PlaytestReport.entry("video", "video-0001", "", meta)
	var draft: Dictionary = PlaytestReport.issue_draft(item, meta, "enhancement")
	assert_eq(str(draft["title"]), "[Playtest] Video capture", "no comment, kind title")
	assert_eq(draft["labels"], ["todo", "enhancement"], "the caller picks the label")
	assert_true(str(draft["body"]).contains("_No comment typed._"), "the body says so")


# --- overlay ----------------------------------------------------------------


func test_overlay_toggles_mode_and_comment_sheet() -> void:
	var overlay: PlaytestCaptureOverlay = PlaytestCaptureOverlay.new()
	add_child(overlay)
	assert_false(overlay.is_mode_on(), "the mode starts off")
	assert_false(overlay.shot_button.visible, "the shot seal is hidden while off")
	overlay.set_mode(true)
	assert_true(overlay.is_mode_on(), "the mode turns on")
	assert_true(overlay.shot_button.visible, "the shot seal appears")
	assert_true(overlay.record_button.visible, "the record seal appears")
	overlay.prompt_comment("video")
	assert_true(overlay.is_prompting(), "a finished capture opens the sheet")
	assert_true(overlay.comment_edit.has_focus(), "the sheet takes the keyboard")
	overlay.close_prompt()
	assert_false(overlay.is_prompting(), "the sheet closes")
	overlay.set_mode(false)
	assert_false(overlay.shot_button.visible, "turning off hides the seals")
	overlay.free()


func test_overlay_emits_its_buttons() -> void:
	var overlay: PlaytestCaptureOverlay = PlaytestCaptureOverlay.new()
	add_child(overlay)
	var seen: Array[String] = []
	overlay.toggle_pressed.connect(func() -> void: seen.append("toggle"))
	overlay.screenshot_pressed.connect(func() -> void: seen.append("shot"))
	overlay.record_pressed.connect(func() -> void: seen.append("record"))
	overlay.comment_submitted.connect(func(text: String) -> void: seen.append("save:" + text))
	overlay.comment_skipped.connect(func() -> void: seen.append("skip"))
	overlay.toggle_button.pressed.emit()
	overlay.shot_button.pressed.emit()
	overlay.record_button.pressed.emit()
	overlay.set_mode(true)
	overlay.prompt_comment("screenshot")
	overlay.comment_edit.text = "A comment"
	overlay.save_button.pressed.emit()
	assert_eq(seen, ["toggle", "shot", "record", "save:A comment"], "every seal answers")
	overlay.prompt_comment("screenshot")
	overlay.skip_button.pressed.emit()
	assert_eq(seen[-1], "skip", "skip answers too")
	overlay.set_recording(true)
	assert_eq(overlay.record_button.text, "Stop", "recording flips the seal")
	overlay.set_status("Ready")
	assert_eq(overlay.status_text(), "Ready", "the status line reads back")
	overlay.free()


# --- controller -------------------------------------------------------------


func _capture() -> PlaytestCapture:
	var capture: PlaytestCapture = PlaytestCapture.new()
	capture.name = "PlaytestCaptureProbe"
	capture.play = _play()
	capture.root_dir = CAPTURE_DIR
	add_child(capture)
	return capture


func test_capture_is_supported_on_desktop() -> void:
	assert_true(PlaytestCapture.supported(), "the CI host is a desktop")
	assert_true(PlaytestPlatform.is_desktop(), "the platform says desktop too")


func test_platform_label_names_the_os() -> void:
	assert_true(PlaytestPlatform.label().length() > 2, "the report names the OS")
	assert_true(PlaytestPlatform.label().contains(" "), "the OS line carries a version")


func test_platform_reports_a_headless_display_in_the_suite() -> void:
	# gd-tools always boots a headless Godot, so no drawable frame exists here.
	assert_false(PlatformHost.has_display(), "the suite has no drawable frame")


func test_toggle_creates_the_session_and_report() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	assert_true(capture.enabled, "the mode turns on")
	assert_true(capture.session_dir.begins_with(CAPTURE_DIR), "the session lands under the root")
	assert_true(FileAccess.file_exists(capture.report_path()), "the report exists at once")
	assert_eq(capture.overlay.status_text(), "Ready", "the overlay says ready")
	capture.toggle_mode()
	assert_false(capture.enabled, "the mode turns off")
	capture.free()


func test_shot_and_record_hotkeys_wait_for_the_mode() -> void:
	var capture: PlaytestCapture = _capture()
	capture._unhandled_input(_action(InputActions.PLAYTEST_SHOT))
	assert_eq(capture.session_dir, "", "a shot while off writes nothing")
	capture._unhandled_input(_action(InputActions.PLAYTEST_TOGGLE))
	assert_true(capture.enabled, "the toggle always answers")
	capture._unhandled_input(_action(InputActions.PLAYTEST_RECORD))
	assert_true(capture.recording, "record starts while on")
	capture._unhandled_input(_action(InputActions.PLAYTEST_RECORD))
	assert_false(capture.recording, "record stops while on")
	capture.free()


func test_comment_attaches_to_the_last_capture() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("screenshot", "shot-0001.png", "", capture._meta)
	)
	capture._pending_comment = 0
	capture.submit_comment("  The reef hides the fleet.  ")
	assert_eq(
		str(capture.entries[0]["comment"]), "The reef hides the fleet.",
		"the comment is trimmed and attached"
	)
	assert_false(capture.overlay.is_prompting(), "saving closes the sheet")
	capture.free()


func test_skip_leaves_the_comment_empty() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("screenshot", "shot-0001.png", "", capture._meta)
	)
	capture._pending_comment = 0
	capture.skip_comment()
	assert_eq(str(capture.entries[0]["comment"]), "", "skip keeps it empty")
	capture.free()


func test_issue_drafts_cover_every_capture() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("screenshot", "shot-0001.png", "One", capture._meta)
	)
	capture.entries.append(
		PlaytestReport.entry("video", "video-0001", "Two", capture._meta)
	)
	var drafts: Array[Dictionary] = capture.issue_drafts("enhancement")
	assert_eq(drafts.size(), 2, "one draft per capture")
	assert_eq(str(drafts[1]["title"]), "[Playtest] Two", "the second draft is the video")
	assert_eq(drafts[0]["labels"], ["todo", "enhancement"], "the label is passed through")
	capture.free()


func test_encode_args_name_the_frame_pattern_and_output() -> void:
	var args: PackedStringArray = PlaytestCapture.encode_args("/tmp/frame-%04d.jpg", "/tmp/v.mp4")
	assert_eq(args[0], "-y", "overwrite the old file")
	assert_eq(args[2], str(PlaytestCapture.FPS), "the capture rate is named")
	assert_eq(args[4], "/tmp/frame-%04d.jpg", "the frame pattern is named")
	assert_eq(args[-1], "/tmp/v.mp4", "the output is named")


func test_finish_encode_keeps_the_frames_when_no_video_landed() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	capture.entries.append(
		PlaytestReport.entry("video", "video-0001", "", capture._meta)
	)
	capture._video_dir = CAPTURE_DIR.path_join("video-0001")
	capture._encode_entry = 0
	capture._finish_encode()
	assert_eq(capture.overlay.status_text(), "Video frames saved", "the frames stay usable")
	assert_eq(str(capture.entries[0]["file"]), "video-0001", "the entry keeps the folder")
	capture.free()


func test_a_headless_grab_never_crashes_the_mode() -> void:
	var capture: PlaytestCapture = _capture()
	capture.toggle_mode()
	await capture.capture_screenshot()
	assert_true(
		capture.overlay.status_text() in ["Shot 1 saved", "Capture failed"],
		"a headless grab either saves or says it failed"
	)
	capture.free()


func _action(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event

# --- folded: audio mix / director / soundtrack ----------------------------
## One Godot boot with the chrome leftovers (docs/testing.md). Mix and
## director stay pure; soundtrack mounts lazily on `_audio_host`.

const TEMP_PATH := "user://test_audio_mix.cfg"
const audio_director_TEMP_PATH := "user://test_audio_director.cfg"

var _mix: AudioMix = null
var _director: AudioDirector = null

func _setup_audio_mix() -> void:
	_suite_setup = "audio_mix"
	_mix = AudioMix.new()
	_remove_temp()

func _setup_audio_director() -> void:
	_suite_setup = "audio_director"
	_audio_director_remove_temp()
	_director = AudioDirector.new()
	_director.settings_path = audio_director_TEMP_PATH
	add_child(_director)

func _teardown_audio_mix() -> void:
	_remove_temp()
	_mix = null

func _teardown_audio_director() -> void:
	if is_instance_valid(_director):
		_director.queue_free()
	_director = null
	_audio_director_remove_temp()

# --- test_audio_mix ---

func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))

func test_defaults_leave_music_under_the_effects() -> void:
	_setup_audio_mix()
	assert_true(_mix.music < _mix.sfx)
	assert_between(_mix.music, 0.4, 0.8)
	assert_false(_mix.muted)

func test_volumes_clamp_to_the_unit_range() -> void:
	_setup_audio_mix()
	assert_eq(_mix.set_music(2.5), 1.0)
	assert_eq(_mix.set_sfx(-3.0), 0.0)
	assert_eq(_mix.set_music(0.35), 0.35)

func test_mute_drops_both_buses_to_silence() -> void:
	_setup_audio_mix()
	_mix.set_music(0.6)
	_mix.set_sfx(0.7)
	_mix.set_muted(true)
	assert_eq(_mix.music_db(), AudioMix.MUTE_DB)
	assert_eq(_mix.sfx_db(), AudioMix.MUTE_DB)
	assert_true(_mix.toggle_muted() == false)
	assert_almost_eq(_mix.music_db(), linear_to_db(0.6), 0.01)

func test_zero_volume_is_silent_even_when_unmuted() -> void:
	_setup_audio_mix()
	_mix.set_muted(false)
	_mix.set_sfx(0.0)
	assert_eq(_mix.sfx_db(), AudioMix.MUTE_DB)

func test_save_and_load_round_trip() -> void:
	_setup_audio_mix()
	_mix.set_music(0.24)
	_mix.set_sfx(0.91)
	_mix.set_muted(true)
	assert_true(_mix.save(TEMP_PATH))

	var reloaded := AudioMix.new()
	assert_true(reloaded.load_from(TEMP_PATH))
	assert_almost_eq(reloaded.music, 0.24, 0.001)
	assert_almost_eq(reloaded.sfx, 0.91, 0.001)
	assert_true(reloaded.muted)

func test_missing_settings_file_keeps_defaults() -> void:
	_setup_audio_mix()
	var fresh := AudioMix.new()
	assert_false(fresh.load_from("user://definitely_not_saved.cfg"))
	assert_almost_eq(fresh.music, AudioMix.MUSIC_DEFAULT, 0.001)
	assert_false(fresh.muted)

func test_reset_restores_shipping_defaults() -> void:
	_setup_audio_mix()
	_mix.set_music(0.1)
	_mix.set_sfx(0.1)
	_mix.set_muted(true)
	_mix.reset()
	assert_almost_eq(_mix.music, AudioMix.MUSIC_DEFAULT, 0.001)
	assert_almost_eq(_mix.sfx, AudioMix.SFX_DEFAULT, 0.001)
	assert_false(_mix.muted)

# --- test_audio_director ---

func _audio_director_remove_temp() -> void:
	if FileAccess.file_exists(audio_director_TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(audio_director_TEMP_PATH))

func test_unknown_events_are_refused() -> void:
	_setup_audio_director()
	assert_false(_director.play_event("kraken_scream"))
	assert_eq(_director.cues.played, 0)
	assert_eq(_director.cues.last_event, "")

func test_a_known_cue_plays_on_a_pooled_voice() -> void:
	_setup_audio_director()
	assert_true(_director.play_event(AudioEvents.UI_CLICK))
	assert_eq(_director.cues.last_event, AudioEvents.UI_CLICK)
	assert_eq(_director.cues.played, 1)
	var voices: Array = _director.cues.voices()
	assert_eq(voices.size(), AudioDirector.SFX_VOICES)
	var busy: int = 0
	for player: AudioStreamPlayer in voices:
		if player.playing:
			busy += 1
	assert_eq(busy, 1)

func test_the_pool_never_overruns_its_voices() -> void:
	_setup_audio_director()
	for _step in AudioDirector.SFX_VOICES * 3:
		_director.play_event(AudioEvents.UI_CLICK)
	assert_eq(_director.cues.voices().size(), AudioDirector.SFX_VOICES)
	assert_eq(_director.cues.played, AudioDirector.SFX_VOICES * 3)

func test_music_beds_load_and_loop() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_eq(_director.current_track_id(), MusicPlaylist.SPANISH_MAIN)
	var stream := _director.live_bed().stream as AudioStreamOggVorbis
	assert_not_null(stream)
	assert_true(stream.loop)
	assert_true(_director._ambience.playing)

func test_unknown_beds_are_refused() -> void:
	_setup_audio_director()
	assert_false(_director.play_music("sea_shanty_404"))
	assert_eq(_director.current_track_id(), "")

func test_restarting_the_same_bed_does_not_restart_playback() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	var player: AudioStreamPlayer = _director.live_bed()
	var playback: float = player.get_playback_position()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_eq(_director.live_bed(), player)
	assert_almost_eq(_director.live_bed().get_playback_position(), playback, 0.5)

func test_switching_beds_crossfades_to_the_other_player() -> void:
	_setup_audio_director()
	_director.play_music(MusicPlaylist.AGE_OF_DISCOVERY)
	var first: AudioStreamPlayer = _director.live_bed()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	assert_ne(_director.live_bed(), first)
	assert_eq(_director.current_track_id(), MusicPlaylist.SPANISH_MAIN)

func test_mute_silences_the_bed_and_the_ambience() -> void:
	_setup_audio_director()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	_director.set_muted(true)
	assert_eq(_director.live_bed().volume_db, AudioDirector.SILENT_DB)
	assert_eq(_director._ambience.volume_db, AudioDirector.SILENT_DB)
	_director.set_muted(false)
	assert_almost_eq(_director.live_bed().volume_db,
		linear_to_db(_director.mix.music), 0.01)

## A driven run asks for no fades: the bed lands on its knob on the same frame
## the desk is told to play it, with no Tween left to resolve (docs/testing.md
## § Speed rules).
func test_a_driven_run_lands_its_bed_while_the_knobs_are_read() -> void:
	_setup_audio_director()
	_director.fade_scale = 0.0
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_almost_eq(
		_director.live_bed().volume_db, linear_to_db(_director.mix.music), 0.01
	)
	assert_true(_director.fader.pending().is_empty(), "no fade waits behind the bed")
	_director.set_muted(true)
	assert_eq(_director.live_bed().volume_db, AudioDirector.SILENT_DB)
	_director.set_muted(false)
	assert_true(_director.fader.pending().is_empty(), "nor behind the mute")

func test_a_stinger_lands_with_the_bed_when_the_drive_asks_for_no_fades() -> void:
	_setup_audio_director()
	_director.fade_scale = 0.0
	_director.play_music(MusicPlaylist.BROADSIDES)
	_director.set_muted(true)
	assert_true(_director.play_stinger(MusicPlaylist.SPANISH_MAIN), "a stinger still lands")
	_director.set_muted(false)
	_director.land_fades()
	assert_true(_director.fader.pending().is_empty(), "every fade is ended")
	assert_almost_eq(
		_director.live_bed().volume_db, linear_to_db(_director.mix.music), 0.01
	)
	assert_eq(_director.current_track_id(), MusicPlaylist.BROADSIDES)

## Live fades still resolve when a driven run lands them: the Tween steps out,
## then the live bed sits on its mix knob (docs/testing.md § Speed rules).
func test_land_fades_steps_pending_bed_tweens() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	assert_false(_director.fader.pending().is_empty(), "a live crossfade waits")
	_director.land_fades()
	assert_true(_director.fader.pending().is_empty(), "every fade is stepped out")
	assert_almost_eq(
		_director.live_bed().volume_db, linear_to_db(_director.mix.music), 0.01
	)

## Mute keeps the bed silent after a land: the desk must not restore volume
## over a muted mix (the smoke mute assert left it at silence).
func test_land_fades_keeps_silence_when_muted() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	_director.set_muted(true)
	_director.land_fades()
	assert_eq(_director.live_bed().volume_db, AudioDirector.SILENT_DB)

## Stopping the bed clears the track; landing then leaves the stopped player
## alone instead of writing a mix knob onto an empty desk.
func test_land_fades_skips_restore_when_no_bed() -> void:
	_setup_audio_director()
	assert_true(_director.play_music(MusicPlaylist.SPANISH_MAIN))
	_director.stop_music()
	assert_eq(_director.current_track_id(), "")
	_director.land_fades()
	assert_eq(_director.current_track_id(), "")
	assert_true(_director.fader.pending().is_empty())

func test_volume_changes_are_clamped_and_broadcast() -> void:
	_setup_audio_director()
	var seen: Array = []
	_director.mix_changed.connect(func(music: float, sfx: float, muted: bool) -> void:
		seen.append({"music": music, "sfx": sfx, "muted": muted})
	)
	_director.set_music_volume(4.0)
	_director.set_sfx_volume(-1.0)
	_director.set_muted(true)
	assert_eq(seen.size(), 3)
	assert_almost_eq(float(seen[0]["music"]), 1.0, 0.001)
	assert_almost_eq(float(seen[1]["sfx"]), 0.0, 0.001)
	assert_true(bool(seen[2]["muted"]))

func test_toggle_mute_flips_the_flag() -> void:
	_setup_audio_director()
	assert_false(_director.is_muted())
	_director.toggle_mute()
	assert_true(_director.is_muted())
	_director.toggle_mute()
	assert_false(_director.is_muted())

func test_stingers_play_without_stopping_the_bed() -> void:
	_setup_audio_director()
	_director.play_music(MusicPlaylist.SPANISH_MAIN)
	var bed: AudioStreamPlayer = _director.live_bed()
	assert_true(_director.play_stinger(MusicPlaylist.VICTORY))
	assert_eq(_director.live_bed(), bed)
	assert_true(bed.playing)
	assert_false((_director.cues.voices()[0].stream as AudioStreamOggVorbis).loop)


## The rotate (issue #1154): a bed plays once, unlooped, and the desk hands the
## next one over when it ends.
func test_the_rotate_plays_a_bed_once_and_steps_to_the_next() -> void:
	_setup_audio_director()
	assert_true(_director.play_rotation(MusicPlaylist.AGE_OF_DISCOVERY))
	assert_true(_director.rotating)
	assert_eq(_director.current_track_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	var stream := _director.live_bed().stream as AudioStreamOggVorbis
	assert_false(stream.loop, "a rotate bed ends so the next can start")
	_director._on_bed_finished()
	assert_eq(_director.current_track_id(), MusicPlaylist.COURT)


## The bed's own end is the hand-off: the player's `finished` steps the rotate
## without waiting on any timer of ours.
func test_a_finished_rotate_bed_steps_the_rotate() -> void:
	_setup_audio_director()
	_director.play_rotation(MusicPlaylist.COURT)
	_director._on_bed_finished()
	assert_eq(_director.current_track_id(),
		MusicPlaylist.next_in_rotation(MusicPlaylist.COURT))
	assert_true(_director.rotating)


## A bed that is not the live one ending (the tail of a crossfade) moves nothing.
func test_a_stale_bed_ending_leaves_the_rotate_alone() -> void:
	_setup_audio_director()
	_director.play_rotation(MusicPlaylist.COURT)
	var before: String = _director.current_track_id()
	_director._on_bed_finished(_director.sleeping_bed())
	assert_eq(_director.current_track_id(), before)


## An explicit bed (the battle tune) pauses the rotate; the rotate does not step
## under it, and it keeps its loop.
func test_an_explicit_bed_pauses_the_rotate() -> void:
	_setup_audio_director()
	_director.play_rotation(MusicPlaylist.AGE_OF_DISCOVERY)
	assert_true(_director.play_music(MusicPlaylist.BROADSIDES))
	assert_false(_director.rotating)
	assert_true((_director.live_bed().stream as AudioStreamOggVorbis).loop)
	_director._on_bed_finished()
	assert_false(_director.rotating, "no rotate under an explicit bed")
	assert_eq(_director.current_track_id(), MusicPlaylist.BROADSIDES)


func test_a_stinger_is_not_a_rotate_bed() -> void:
	_setup_audio_director()
	assert_false(_director.play_rotation(MusicPlaylist.VICTORY))
	assert_false(_director.rotating)
	assert_eq(_director.current_track_id(), "")


## The mix rules do not change under the rotate: mute silences it, the music
## knob still sets it, and the sea swell joins it.
func test_the_rotate_obeys_the_mix() -> void:
	_setup_audio_director()
	assert_true(_director.play_rotation(MusicPlaylist.COURT))
	assert_true(_director._ambience.playing, "the swell joins a rotate bed")
	_director.set_muted(true)
	assert_eq(_director.live_bed().volume_db, AudioDirector.SILENT_DB)
	_director.set_muted(false)
	assert_almost_eq(_director.live_bed().volume_db,
		linear_to_db(_director.mix.music), 0.01)
	_director.set_music_volume(0.3)
	assert_almost_eq(_director.live_bed().volume_db, linear_to_db(0.3), 0.01)


# --- the desk's books (REQ-P3-01: each one answers on its own) ---------------

## The cue book answers without a desk: it names the request, counts it, hands
## out a free voice first and keeps its round bounded when every voice is busy.
func test_the_cue_book_names_counts_and_rounds_its_voices() -> void:
	var book := AudioVoicePool.new()
	assert_eq(book.last_event, "")
	assert_eq(book.played, 0)
	book.note(AudioEvents.UI_CLICK)
	assert_eq(book.last_event, AudioEvents.UI_CLICK, "a cue is named as asked")
	var voices: Array[AudioStreamPlayer] = []
	for index in 2:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	book.adopt(voices, AudioDirector.SILENT_DB)
	assert_eq(book.voices().size(), 2)
	assert_eq(book.voices()[0].volume_db, AudioDirector.SILENT_DB, "a voice starts mute")
	var stream: AudioStream = load(AudioEvents.path_for(AudioEvents.UI_CLICK)) as AudioStream
	var first: AudioStreamPlayer = book.take()
	assert_eq(first, voices[0], "a free voice takes the first cue")
	first.stream = stream
	first.play()
	var second: AudioStreamPlayer = book.take()
	assert_eq(second, voices[1], "the next free voice follows")
	second.stream = stream
	second.play()
	assert_eq(book.played, 2)
	# Every voice busy: the round hands them out in turn instead of piling up.
	assert_eq(book.take(), voices[0], "a spent round comes back to the first voice")
	assert_false(voices[0].playing, "the spent voice is stopped for the next cue")
	assert_eq(book.next_voice(), voices[0], "a stopped voice is free again")
	assert_eq(book.played, 3)
	book.hush(AudioDirector.SILENT_DB)
	assert_null(AudioVoicePool.new().take(), "an empty book hands no voice")
	for voice: AudioStreamPlayer in voices:
		voice.free()


## The bed deck turns the pair and keeps the knobs: one bed live, the other mute
## until a switch warms it (REQ-P1-06).
func test_the_bed_deck_turns_its_pair() -> void:
	var deck := AudioBedDeck.new()
	assert_null(deck.live(), "no beds, no live bed")
	assert_null(deck.waiting())
	var beds: Array[AudioStreamPlayer] = []
	for index in 2:
		var bed := AudioStreamPlayer.new()
		add_child(bed)
		beds.append(bed)
	deck.adopt(beds, AudioDirector.SILENT_DB)
	assert_eq(deck.live(), beds[0])
	assert_eq(deck.waiting(), beds[1])
	assert_eq(deck.live_index(), 0)
	assert_eq(deck.turn(), beds[1], "a switch warms the waiting bed")
	assert_eq(deck.live_index(), 1)
	assert_eq(deck.waiting(), beds[0])
	deck.rest_knobs(linear_to_db(0.4), AudioDirector.SILENT_DB)
	assert_almost_eq(beds[1].volume_db, linear_to_db(0.4), 0.01, "the live bed keeps the mix")
	assert_eq(beds[0].volume_db, AudioDirector.SILENT_DB, "the sleeping bed stays mute")
	for bed: AudioStreamPlayer in beds:
		bed.free()
	var lone: Array[AudioStreamPlayer] = [AudioStreamPlayer.new()]
	var single := AudioBedDeck.new()
	single.adopt(lone, AudioDirector.SILENT_DB)
	assert_eq(single.turn(), lone[0], "one bed is its own waiting bed")
	lone[0].free()


## The shelf reads each stream once and answers a missing path with null.
func test_the_shelf_reads_a_stream_once() -> void:
	var shelf := AudioStreamShelf.new()
	assert_null(shelf.stream(""), "an empty path reads nothing")
	assert_null(shelf.stream("res://assets/audio/sfx/missing_cue.ogg"), "a missing file reads nothing")
	var first: AudioStream = shelf.stream(MusicPlaylist.AMBIENCE)
	assert_not_null(first)
	assert_eq(shelf.stream(MusicPlaylist.AMBIENCE), first, "the shelf keeps the one stream")


## The loop rule is the shelf's: an Ogg bed follows the flag, and a null stream
## is left alone.
func test_the_shelf_sets_the_loop_on_every_bed() -> void:
	var ogg := AudioStreamOggVorbis.new()
	AudioStreamShelf.set_loop(ogg, true)
	assert_true(ogg.loop)
	AudioStreamShelf.set_loop(ogg, false)
	assert_false(ogg.loop)
	var wav := AudioStreamWAV.new()
	AudioStreamShelf.set_loop(wav, true)
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	AudioStreamShelf.set_loop(wav, false)
	assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	AudioStreamShelf.set_loop(null, true)


## The rotate book keeps its own place: a start names the tune, a hold forgets
## it, and a stopped book names nothing.
func test_the_rotate_book_keeps_its_place() -> void:
	var book := MusicRotation.new()
	assert_false(book.running)
	assert_eq(book.track(), "")
	book.start(MusicPlaylist.COURT)
	assert_true(book.running)
	assert_eq(book.track(), MusicPlaylist.COURT)
	assert_eq(book.next(), MusicPlaylist.next_in_rotation(MusicPlaylist.COURT))
	book.start()
	assert_eq(book.track(), MusicPlaylist.COURT, "an unnamed start keeps the tune")
	book.hold()
	assert_false(book.running)
	assert_eq(book.track(), "")


func test_mix_settings_persist_to_disk() -> void:
	_setup_audio_director()
	_director.set_music_volume(0.33)
	_director.set_muted(true)
	_director._save_timer.timeout.emit()
	var reloaded := AudioMix.new()
	assert_true(reloaded.load_from(audio_director_TEMP_PATH))
	assert_almost_eq(reloaded.music, 0.33, 0.01)
	assert_true(reloaded.muted)

# --- map_soundtrack ---
## Integration: the score — the app shell's launch bed, the real map screen's era
## beds, cues on player moments, battle music and the sound seals (REQ-P1-06).

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const map_soundtrack_TEMP_PATH := "user://test_map_soundtrack.cfg"

## Score cases share one chart: under coverage a mount costs ~1 s and a re-seat
## from the pristine save ~0.15 s (`Fixture.suite_reset`). Mount lazily on the
## first soundtrack case so the ~37 mix/director cases never pay a MapScreen
## under coverage (docs/testing.md § Speed rules; same pattern as battle HUD /
## research sheet). Static because gd-tools hands each case a fresh instance: a
## shell case frees the chart, and the next soundtrack case must find the one
## the suite mounted. The shell's cases share one shell the same way; the first
## frees the chart so the two never share one WorldMap instance.
static var _screen: MapScreen = null
static var _audio: AudioDirector = null
static var _score: MapSoundtrack = null
static var _pristine: Dictionary = {}
static var _world_snapshot: Array = []
## The shell the last shell case left standing (the shell is the suite's other
## expensive mount, so all its cases share one). The first shell case frees the
## map chart so the shell and the suite never share one WorldMap instance.
static var _app: Node = null
## The before_all instance owns the mount, so a remount after a shell case
## outlives the case that asked for it.
static var _audio_host: Node = null


func _mount_soundtrack() -> void:
	Fixture.restore(Fixture.world(), _world_snapshot)
	_screen = Fixture.attach_screen(_audio_host)
	_audio = _screen.get_node("Audio") as AudioDirector
	_audio.settings_path = map_soundtrack_TEMP_PATH
	_audio.fade_scale = 0.0
	_score = _screen.get_node("Soundtrack") as MapSoundtrack
	_pristine = Fixture.suite_capture(_screen)


## Re-seats the shared chart at the top of turn 1 and puts the mix and the era
## bed back where the mount left them, so a case reads the score it expects.
func _setup_map_soundtrack() -> void:
	_suite_setup = "map_soundtrack"
	if not is_instance_valid(_screen):
		_mount_soundtrack()
	else:
		Fixture.restore(Fixture.world(), _world_snapshot)
		Fixture.suite_reset(_screen, _pristine, Fixture.world())
	_audio.set_music_volume(AudioMix.MUSIC_DEFAULT)
	_audio.set_sfx_volume(AudioMix.SFX_DEFAULT)
	_audio.set_muted(false)
	# The rotate carries across cases on the shared director; stop it so a case
	# always starts from the era bed its calendar names.
	_audio.stop_music(0.0)
	_score._sync_bed()


## The mount outlives the case; only the suite's own mix file is dropped.
func _after_soundtrack() -> void:
	Fixture.restore(Fixture.world(), _world_snapshot)
	Fixture.park_screen(_screen)
	if FileAccess.file_exists(map_soundtrack_TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(map_soundtrack_TEMP_PATH))


func test_the_campaign_opens_on_the_renaissance_bed() -> void:
	_setup_map_soundtrack()
	assert_not_null(_audio)
	assert_not_null(_score)
	assert_eq(_audio.current_track_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(_audio.last_track_id, MusicPlaylist.AGE_OF_DISCOVERY)


func test_the_soundtrack_wires_the_director() -> void:
	_setup_map_soundtrack()
	assert_eq(_score.audio, _audio)
	assert_eq(_score.screen, _screen)


func test_selecting_a_province_plays_a_cue_pair() -> void:
	_setup_map_soundtrack()
	var before: int = _audio.cues.played
	var province_id: int = Fixture.inland_province(_screen.model)
	MapPlayInput.on_tapped(
		_screen.play, _screen.model.province_center(province_id) * MapScreen.TILE_SIZE
	)
	assert_eq(_audio.cues.last_event, AudioEvents.PANEL_OPEN)
	assert_eq(_audio.cues.played, before + 2)


func test_clearing_the_selection_closes_the_panel_audibly() -> void:
	_setup_map_soundtrack()
	var inland: Vector2 = (
		_screen.model.province_center(Fixture.inland_province(_screen.model))
		* MapScreen.TILE_SIZE
	)
	MapPlayInput.on_tapped(_screen.play, inland)
	MapPlayInput.deselect(_screen.play)
	assert_eq(_audio.cues.last_event, AudioEvents.PANEL_CLOSE)


func test_deselecting_a_fleet_does_not_sound_another_selection() -> void:
	_setup_map_soundtrack()
	_screen.ship_layer.select(_screen.ship_layer.ships[0])
	assert_eq(_audio.cues.last_event, AudioEvents.FLEET_SELECT)
	MapPlayInput.deselect(_screen.play)
	assert_eq(_audio.cues.last_event, AudioEvents.PANEL_CLOSE)


func test_civilian_selection_and_moves_sound() -> void:
	_setup_map_soundtrack()
	var unit: CivilianState = _screen.civilian_layer.units[0]
	_screen.civilian_layer.select(unit)
	assert_eq(_audio.cues.last_event, AudioEvents.CIVILIAN_SELECT)
	var before: int = _audio.cues.played
	_screen.civilian_layer.unit_moved.emit(unit, {"ok": true})
	assert_eq(_audio.cues.last_event, AudioEvents.CIVILIAN_MOVE)
	_screen.civilian_layer.unit_moved.emit(unit, {"ok": false, "reason": "blocked"})
	assert_eq(_audio.cues.last_event, AudioEvents.ORDER_DENIED)
	assert_eq(_audio.cues.played, before + 2)


func test_ending_a_turn_rings_the_bell_and_coins() -> void:
	# The score reads the chart's own `turn_ended`. A live close rings exactly
	# this signal and is proven once, on the suite that already ends a turn
	# (`test_a_map_screen`); a rival pass here would only re-prove it under
	# coverage (docs/testing.md § Speed rules).
	_setup_map_soundtrack()
	var before: int = _audio.cues.played
	var closed: int = _screen.play.turn
	_screen.turn_ended.emit(closed + 1)
	assert_eq(_audio.cues.last_event, AudioEvents.COIN)
	assert_gte(_audio.cues.played, before + 2)


func test_selecting_a_fleet_sounds_the_ship_bell() -> void:
	_setup_map_soundtrack()
	var ship: Ship = _screen.ship_layer.ships[0]
	_screen.ship_layer.select(ship)
	assert_eq(_audio.cues.last_event, AudioEvents.FLEET_SELECT)


func test_a_battle_brings_the_battle_bed_and_a_salute() -> void:
	_setup_map_soundtrack()
	_screen.turn = 30
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), MusicPlaylist.SPANISH_MAIN)

	var battle: Dictionary = {
		"zone": 0,
		"attacker": MapScreen.PLAYER_FACTION,
		"defender": 1,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["hull_a"],
	}
	var before: int = _audio.cues.played
	_score._on_battle_resolved([battle] as Array[Dictionary])
	assert_eq(_audio.current_track_id(), MusicPlaylist.BROADSIDES)
	assert_gte(_audio.cues.played, before + 2)


func test_a_battle_bed_survives_the_turn_end() -> void:
	# As above: the bed's rule is the score's read of the close, not the rival
	# pass that raises it. The bed holds while the battle timer runs and its
	# expiry hands the era back.
	_setup_map_soundtrack()
	var battle: Dictionary = {
		"zone": 0,
		"attacker": MapScreen.PLAYER_FACTION,
		"defender": 1,
		"outcome": NavalCombat.Outcome.STALEMATE,
		"attacker_lost": [],
		"defender_lost": [],
	}
	_score._on_battle_resolved([battle] as Array[Dictionary])
	assert_eq(_audio.current_track_id(), MusicPlaylist.BROADSIDES)
	_screen.turn_ended.emit(_screen.play.turn)
	assert_eq(_audio.current_track_id(), MusicPlaylist.BROADSIDES)
	_score._battle_timer.timeout.emit()
	assert_eq(
		_audio.current_track_id(),
		MusicPlaylist.bed_id_for_year(TurnTime.START_YEAR),
		"the era bed returns once the battle music is spent"
	)


## A siege answers with its battery, and a silenced battery lets the stone fall:
## the breach cue lands last so the player hears the wall come down.
func test_a_siege_plays_its_battery_and_the_breach() -> void:
	_setup_map_soundtrack()
	var battle: Dictionary = {
		"attacker": MapScreen.PLAYER_FACTION,
		"defender": 1,
		"outcome": ArmyCombat.Outcome.DEFENDER_VICTORY,
		"battle_mode": "siege",
		"fort_level": 1,
		"quick": {"fort_downgraded": true, "fort_after": 0},
		"attacker_lost": [],
		"defender_lost": [],
	}
	var before: int = _audio.cues.played

	_score._on_battle_resolved([battle] as Array[Dictionary])

	assert_eq(_audio.cues.last_event, AudioEvents.WALL_BREACH, "the breach lands last")
	assert_gte(_audio.cues.played, before + 2, "battery and breach both sound")


func test_a_lost_battle_plays_the_knell() -> void:
	_setup_map_soundtrack()
	var battle: Dictionary = {
		"zone": 0,
		"attacker": 1,
		"defender": MapScreen.PLAYER_FACTION,
		"outcome": NavalCombat.Outcome.SIDE1_VICTORY,
		"attacker_lost": [],
		"defender_lost": ["hull_a"],
	}
	assert_eq(_score._player_outcome([battle] as Array[Dictionary]), -1)
	assert_eq(_score._player_outcome([]), 0)


func test_the_era_bed_follows_the_calendar() -> void:
	_setup_map_soundtrack()
	_screen.turn = 101
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), MusicPlaylist.GILDED_MINUET)


## The rotate (issue #1154): a turn close leaves the tune alone, and only a new
## calendar era calls the calendar's bed back.
func test_a_turn_close_keeps_the_rotate_where_it_is() -> void:
	_setup_map_soundtrack()
	_audio._on_bed_finished()
	var playing: String = _audio.current_track_id()
	assert_eq(playing, MusicPlaylist.COURT)
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), playing, "the turn close restarts nothing")
	assert_true(_audio.rotating)


func test_a_new_era_re_anchors_the_rotate() -> void:
	_setup_map_soundtrack()
	_audio._on_bed_finished()
	_screen.turn = 101
	_score._sync_bed()
	assert_eq(_audio.current_track_id(), MusicPlaylist.GILDED_MINUET)
	assert_true(_audio.rotating, "the new era keeps rotating")


## The rotate's own end steps the bed under the map: the score owns no timer for
## it, the director's hand-off does.
func test_the_rotate_steps_under_the_map() -> void:
	_setup_map_soundtrack()
	var first: String = _audio.current_track_id()
	_audio._on_bed_finished()
	assert_ne(_audio.current_track_id(), first)
	assert_eq(_audio.current_track_id(), MusicPlaylist.next_in_rotation(first))


## The map carries no sound seal: the mix desk lives in its pause menu, wired
## to the same director the score uses (REQ-P1-06).
func test_the_pause_menu_desk_drives_the_mix() -> void:
	_setup_map_soundtrack()
	var desk: SoundDesk = _screen.game_menu.sound_desk
	assert_not_null(desk, "the map folds the mix desk into its pause menu")
	_screen.game_menu.open()
	assert_not_null(desk.music, "the desk arrives with the menu")

	desk.music.value = 0.2
	assert_almost_eq(_audio.mix.music, 0.2, 0.01)
	desk.sfx.value = 0.45
	assert_almost_eq(_audio.mix.sfx, 0.45, 0.01)

	desk.mute.button_pressed = true
	desk.mute.pressed.emit()
	assert_true(_audio.is_muted())
	_screen.game_menu.close()


func test_the_desk_shows_the_authoritative_mix() -> void:
	_setup_map_soundtrack()
	var desk: SoundDesk = _screen.game_menu.sound_desk
	assert_not_null(desk)
	_audio.set_muted(true)
	assert_true(desk.mute.button_pressed)
	assert_eq(desk.mute.text, "UNMUTE")
	_audio.set_muted(false)
	assert_false(desk.mute.button_pressed)


## Pure case: the binding is the InputMap's, so it pays no chart re-seat.
func test_the_mute_key_is_bound() -> void:
	InputActions.ensure_actions()
	assert_true(InputMap.has_action(InputActions.MUTE))
	var keys: Array = InputMap.action_get_events(InputActions.MUTE)
	assert_gt(keys.size(), 0)


# --- app shell ---------------------------------------------------------------


## A shell case reads the app, never the suite's chart: `_boot_shell` drops the
## chart on the shell's first mount, and a case that asks for no chart must not
## mount one back (docs/testing.md § Speed rules: pure cases skip the re-seat).
func _setup_shell() -> void:
	_suite_setup = "app_shell"


## The shell leaves the shared world as it found it; only the suite's own mix
## file was written.
func _after_shell() -> void:
	Fixture.restore(Fixture.world(), _world_snapshot)
	if FileAccess.file_exists(map_soundtrack_TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(map_soundtrack_TEMP_PATH))


## The shell cases share one mount: the first asks for it, each case returns to
## the title and drops the director state the last case left, and `after_all`
## frees it (docs/testing.md § Speed rules: one mount per suite). The shell
## rides the shared world with the suite's own mix file, so the player's
## settings are never touched.
func _boot_shell() -> Node:
	if is_instance_valid(_app):
		return _app
	# Drop the map-screen mount from `_setup_map_soundtrack` so the shell and the
	# screen never share one WorldMap instance under the same suite.
	if is_instance_valid(_screen):
		_screen.free()
	_screen = null
	_audio = null
	_score = null
	Fixture.restore(Fixture.world(), _world_snapshot)
	var app: Node = MAIN.instantiate()
	app.size_override = Vector2i(Fixture.WORLD_WIDTH, Fixture.WORLD_HEIGHT)
	# Observer / campaign doors reuse the shared chart so shell cases do not
	# roll a world under coverage just to assert the score.
	app.preset_world = Fixture.world()
	add_child(app)
	# Keep the shell's mix out of the player's own settings file.
	app.audio.settings_path = map_soundtrack_TEMP_PATH
	app.audio.set_music_volume(AudioMix.MUSIC_DEFAULT)
	app.audio.set_sfx_volume(AudioMix.SFX_DEFAULT)
	app.audio.set_muted(false)
	_app = app
	return app


## Back to a fresh title with the mix where the mount left it. The bed and its
## swell are the launch page's own doing, so this silences them and rebuilds the
## page: a case must hear `play_menu_bed` start them, not inherit the last
## case's. The page swap also frees whatever screen the last case left.
func _reseat_shell(app: Node) -> void:
	app.audio.set_muted(false)
	app.audio.set_music_volume(AudioMix.MUSIC_DEFAULT)
	app.audio.set_sfx_volume(AudioMix.SFX_DEFAULT)
	app.audio.stop_music(0.0)
	app.audio._ambience.stop()
	app.audio.land_fades()
	app._show_main_menu()


## M is the shell's shortcut now, so it answers before any page claims the key.
func _press_mute_key() -> void:
	InputActions.ensure_actions()
	var down := InputEventKey.new()
	down.physical_keycode = KEY_M
	down.pressed = true
	get_viewport().push_input(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_M
	up.pressed = false
	get_viewport().push_input(up)


func test_the_title_screen_opens_on_the_sea_bed() -> void:
	_setup_shell()
	var app: Node = _boot_shell()
	_reseat_shell(app)
	assert_true(app.current_page is MainMenu, "the title screen is the entry point")
	assert_eq(MusicPlaylist.menu_bed_id(), MusicPlaylist.AGE_OF_DISCOVERY)
	assert_eq(app.audio.current_track_id(), MusicPlaylist.menu_bed_id())
	assert_true(app.audio._ambience.playing, "the swell joins the launch bed")


func test_the_title_page_carries_the_sound_seal() -> void:
	_setup_shell()
	var app: Node = _boot_shell()
	_reseat_shell(app)
	var seal: AudioControls = (app.current_page as MainMenu).audio_controls
	assert_not_null(seal, "the launch page offers the mix desk")
	seal.music_slider().value = 0.25
	assert_almost_eq(app.audio.mix.music, 0.25, 0.01)
	seal._trigger.pressed.emit()
	assert_true(seal.is_open(), "the desk opens over the title")
	seal.mute_button().button_pressed = true
	seal.mute_button().pressed.emit()
	assert_true(app.audio.is_muted(), "the title desk silences the score")
	assert_true(seal.mute_button().button_pressed, "the seal mirrors the mix")
	seal.mute_button().button_pressed = false
	seal.mute_button().pressed.emit()
	assert_false(app.audio.is_muted())


func test_a_campaign_takes_the_launch_director_over() -> void:
	_setup_shell()
	var app: Node = _boot_shell()
	_reseat_shell(app)
	# The observer is the cheapest campaign door (no setup / charge pages).
	app._start_observer()
	var screen: MapScreen = app.current_screen
	assert_not_null(screen, "the debug door installs a campaign")
	if screen == null:
		return
	var score: MapSoundtrack = screen.get_node("Soundtrack") as MapSoundtrack
	assert_eq(score.audio, app.audio, "the campaign shares the shell director")
	assert_eq(
		app.audio.current_track_id(), MusicPlaylist.menu_bed_id(),
		"the launch bed keeps playing into the first turn"
	)
	assert_true(app.audio.live_bed().playing, "the bed never stopped")
	await get_tree().process_frame
	assert_null(screen.get_node_or_null("Audio"), "the scene's own director retires")


func test_the_title_bed_is_the_bed_the_campaign_opens_on() -> void:
	_setup_shell()
	assert_eq(
		MusicPlaylist.menu_bed_id(),
		MusicPlaylist.bed_id_for_year(TurnTime.START_YEAR)
	)


## The launch bed is not one loop any more (issue #1154): the title rotates on to
## the next bed when the first ends, with the swell still running.
func test_the_title_bed_rotates_on() -> void:
	_setup_shell()
	var app: Node = _boot_shell()
	_reseat_shell(app)
	assert_true(app.audio.rotating, "the launch starts the rotate")
	assert_eq(app.audio.current_track_id(), MusicPlaylist.menu_bed_id())
	app.audio._on_bed_finished()
	assert_eq(
		app.audio.current_track_id(),
		MusicPlaylist.next_in_rotation(MusicPlaylist.menu_bed_id())
	)
	assert_true(app.audio._ambience.playing, "the swell carries over the hand-off")


func test_returning_to_the_title_brings_the_sea_bed_back() -> void:
	_setup_shell()
	var app: Node = _boot_shell()
	_reseat_shell(app)
	app._start_observer()
	assert_not_null(app.current_screen)
	if app.current_screen == null:
		return
	app.audio.play_music(MusicPlaylist.BROADSIDES)
	assert_eq(app.audio.current_track_id(), MusicPlaylist.BROADSIDES)
	app.current_screen.main_menu_requested.emit()
	assert_true(app.current_page is MainMenu, "the title comes back")
	assert_eq(app.audio.current_track_id(), MusicPlaylist.menu_bed_id())


func test_the_mute_shortcut_answers_on_the_title_screen() -> void:
	_setup_shell()
	var app: Node = _boot_shell()
	_reseat_shell(app)
	var before: bool = app.audio.is_muted()
	_press_mute_key()
	assert_eq(app.audio.is_muted(), not before, "M silences the launch bed")
	_press_mute_key()
	assert_eq(app.audio.is_muted(), before, "M restores the mix")
