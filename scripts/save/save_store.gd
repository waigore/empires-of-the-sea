class_name SaveStore
extends RefCounted
## Local save slots under user:// (desktop and mobile share this path).
## Files are Godot text literals of built-in Variants: ints, vectors and typed
## packed arrays survive the round trip, and a corrupt file reads as empty.

const DIR: String = "user://saves"
const SLOT_COUNT: int = 5
const PREFIX: String = "slot_"
const SUFFIX: String = ".sav"


static func path_for(slot: int, dir: String = DIR) -> String:
	return "%s/%s%d%s" % [dir, PREFIX, clampi(slot, 1, SLOT_COUNT), SUFFIX]


static func save_slot(slot: int, data: Dictionary, dir: String = DIR) -> bool:
	if data.is_empty() or not SaveCodec.is_valid(data):
		return false
	return write(path_for(slot, dir), data)


static func load_slot(slot: int, dir: String = DIR) -> Dictionary:
	return read(path_for(slot, dir))


static func has_slot(slot: int, dir: String = DIR) -> bool:
	return FileAccess.file_exists(path_for(slot, dir))


static func delete_slot(slot: int, dir: String = DIR) -> bool:
	var path: String = path_for(slot, dir)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## Writes a plain variant dictionary; returns false on any I/O failure.
## The data lands in a temporary file first, so a crash cannot truncate the
## slot that is already on disk.
static func write(path: String, data: Dictionary) -> bool:
	_ensure_parent(path)
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(var_to_str(data))
	file.close()
	var err: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)
	)
	if err != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	return true


## Reads a save file, returning {} for missing, unreadable or corrupt saves.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = str_to_var(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parsed
	return data


## One row per slot for the save/load browsers.
static func slots(dir: String = DIR) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for slot in range(1, SLOT_COUNT + 1):
		var data: Dictionary = load_slot(slot, dir)
		var row: Dictionary = {"slot": slot, "exists": not data.is_empty()}
		if not data.is_empty():
			row.merge(SaveCodec.summary(data), true)
		rows.append(row)
	return rows


static func _ensure_parent(path: String) -> void:
	var directory: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
