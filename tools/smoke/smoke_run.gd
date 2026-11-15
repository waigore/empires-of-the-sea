extends RefCounted
## The e2e smoke's own state: the live tree, the campaign under test, the sound
## director the HUD pass read, the work tiles queued for the end-of-turn asserts
## and every assert taken so far. Each step in tools/smoke/ takes one run and
## prints through `check`, so the gate reads as one ordered ladder of named steps
## instead of one long body (REQ-P3-01, docs/testing.md § E2E smoke).
##
## No `class_name`: the driver and its steps preload this file, so a fresh
## clone, a manual run and the gd-tools cache all resolve it the same way.

## The smoke's scratch slot, wiped before the campaign starts and after it ends.
const SAVE_DIR: String = "user://e2e_smoke_saves"
const SAVE_SLOT: int = 1

var tree: SceneTree = null
## The main scene the launch step mounted; the persistence step returns to it.
var main: Node = null
## The campaign under test, set once the chart and the charge are answered.
var screen: MapScreen = null
## The music/sound director the HUD pass found, and its cue count before the turn.
var audio: AudioDirector = null
var cues_before: int = 0
## Tiles the civilian and army passes queued for the end-of-turn asserts.
var works: Dictionary = {}

var _failures: PackedStringArray = PackedStringArray()


func _init(p_tree: SceneTree) -> void:
	tree = p_tree


## One assert: printed as the smoke always has, and kept for the exit code.
func check(ok: bool, label: String) -> void:
	if ok:
		print("e2e_smoke: PASS %s" % label)
	else:
		printerr("e2e_smoke: FAIL %s" % label)
		_failures.append(label)


## Recursive label text search: the smoke reads what the player would read.
func has_text(node: Node, needle: String) -> bool:
	if node == null:
		return false
	if node is Label and String((node as Label).text).contains(needle):
		return true
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child: Node in node.get_children():
		if has_text(child, needle):
			return true
	return false


## True once any assert failed; the driver prints the tally and fails the run.
func failed() -> bool:
	return not _failures.is_empty()


func failure_line() -> String:
	return "%d assert(s) failed: %s" % [_failures.size(), ", ".join(_failures)]


## The smoke's own save directory, cleaned so a rerun never loads a stale slot.
func clean_save_dir() -> void:
	var path: String = ProjectSettings.globalize_path(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
