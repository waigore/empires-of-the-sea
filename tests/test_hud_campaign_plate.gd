extends GdToolsTest
## Lean coverage for HudCampaignEnd, GameHud's routing into it, and the app's
## icon / launcher branding (REQ-P3-01, REQ-P1-02/03/08). The full calendar-cap
## MapScreen theme lives in test_campaign_end; this suite stays lean so a chrome
## or branding extract stays inside the tier-1 5 min budget. Merged from
## test_branding_rules (one Godot boot for both).

var _host: Control = null
var _overlay: VictoryOverlay = null
var _seal: Button = null
var _glow: Panel = null
var _end: HudCampaignEnd = null
var _hud: GameHud = null


func before_each() -> void:
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


func after_each() -> void:
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
	var state := VictoryState.military(FactionCatalog.PLAYER_FACTION, 10)
	_hud.show_victory(state, FactionCatalog.PLAYER_FACTION, 12)
	assert_true(_hud.campaign_over)
	assert_true(_hud.is_victory_shown())
	assert_true(_seal.disabled)
	assert_eq(_seal.text, HudCampaignEnd.SEALED_TEXT)
	assert_false(_glow.visible)


func test_calendar_cap_and_defeat_raise_the_same_sealed_plate() -> void:
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
