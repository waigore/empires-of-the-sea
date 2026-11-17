extends GdToolsTest
## The app's face: the project icon and the Android launcher layers it ships
## (REQ-P1-02 period look, REQ-P1-03 not placeholder-as-final, REQ-P1-08
## intentional icons; issue #887). Asset wiring only — no scene boot, so the
## suite stays a file read.

const ICON_PATH := "res://icon.svg"
const PRESETS_PATH := "res://export_presets.cfg"
const BRANDING_DIR := "res://assets/art/branding/"
## The old placeholder's disc colour: the mark must not fall back to it.
const PLACEHOLDER_FILL := "#3d8fd1"
const LAUNCHER_SIZES := {
	"launcher_main_192.png": 192,
	"launcher_foreground_432.png": 432,
	"launcher_background_432.png": 432,
	"launcher_monochrome_432.png": 432,
}

func test_project_icon_is_the_carrack_mark() -> void:
	var text := _read(ICON_PATH)
	assert_ne(text, "", "the project icon must exist")
	assert_true(text.contains("viewBox"), "the icon must be a scalable mark")
	assert_true(text.contains("carrack"), "the icon must be the carrack mark")
	assert_false(text.contains(PLACEHOLDER_FILL), "the placeholder disc must be gone")
	assert_gt(text.length(), 1000, "the icon must carry real art, not a stub")

func test_project_icon_is_wired() -> void:
	var project := _read("res://project.godot")
	assert_true(
		project.contains('config/icon="res://icon.svg"'),
		"project.godot must point config/icon at the mark"
	)

func test_launcher_layers_exist_at_their_sizes() -> void:
	for name: String in LAUNCHER_SIZES:
		var path: String = BRANDING_DIR + name
		assert_true(FileAccess.file_exists(path), "%s must exist" % path)
		var img := Image.new()
		assert_eq(img.load(path), OK, "%s must load" % path)
		assert_eq(img.get_width(), LAUNCHER_SIZES[name], "%s width" % name)
		assert_eq(img.get_height(), LAUNCHER_SIZES[name], "%s height" % name)

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

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
