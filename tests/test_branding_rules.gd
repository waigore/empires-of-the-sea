extends GdToolsTest
## The app's face: the project icon and the Android launcher layers it ships
## (REQ-P1-02 period look, REQ-P1-03 not placeholder-as-final, REQ-P1-08
## intentional icons; issue #887). Asset wiring only — no scene boot, so the
## suite stays a file read.

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
	var img := _load(ICON_PATH)
	if img == null:
		assert_true(false, "the project icon must exist and load")
		return
	assert_eq(img.get_width(), ICON_SIZE, "the icon is a %d px square" % ICON_SIZE)
	assert_eq(img.get_height(), ICON_SIZE, "the icon is a %d px square" % ICON_SIZE)
	assert_false(_is_flat(img), "the icon must carry real art, not a flat disc")
	assert_ne(
		"#%s" % img.get_pixel(ICON_SIZE / 2, ICON_SIZE / 2).to_html(false),
		PLACEHOLDER_FILL,
		"the placeholder disc colour must be gone"
	)

func test_project_icon_is_wired() -> void:
	var project := _read("res://project.godot")
	assert_true(
		project.contains('config/icon="res://icon.png"'),
		"project.godot must point config/icon at the carrack mark"
	)

func test_launcher_layers_exist_at_their_sizes() -> void:
	for name: String in LAUNCHER_SIZES:
		var path: String = BRANDING_DIR + name
		assert_true(FileAccess.file_exists(path), "%s must exist" % path)
		var img := _load(path)
		if img == null:
			assert_true(false, "%s must load" % path)
			continue
		assert_eq(img.get_width(), LAUNCHER_SIZES[name], "%s width" % name)
		assert_eq(img.get_height(), LAUNCHER_SIZES[name], "%s height" % name)

func test_adaptive_foreground_keeps_art_off_the_crop_edge() -> void:
	var img := _load(BRANDING_DIR + "launcher_foreground_432.png")
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
	var presets := _read(PRESETS_PATH)
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

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return img

## True when every sampled pixel is the same colour (the old flat disc).
func _is_flat(img: Image) -> bool:
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

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)