class_name DialogueLocale
extends RefCounted
## The court's words carry a stable key, so a translation can follow a line
## without touching code (wiki: dialogue-content-and-yarn § Design intent:
## "Content keys must be stable so authored scripts and localization stay
## aligned").
##
## Every authored line reads as `DialoguePoint/<category>/<situation>/<variant>`
## through Godot's [TranslationServer]. An untranslated key falls back to the
## authored source line, so the source language is never lost and a shipped
## `.po` / `.translation` fills one point at a time (REQ-P2-05). No rule reads a
## translated string (REQ-P2-03).
##
## Tongues are content: every `.po` in [constant SHIPPED_DIR] is registered on
## the first line a court speaks, so a build learns a translation without a
## project setting, and the out-of-map settings page can offer it by name (wiki:
## dialogue-content-and-yarn; DR-20261113-06, DR-20261113-09). Nothing on the
## rules path reads which tongue is running beyond the key lookup itself.

const SOURCE_LOCALE: String = "en"
const KEY_PREFIX: String = "DialoguePoint"
## Where the tongues live: a `.po` dropped here is a tongue the build knows.
const SHIPPED_DIR: String = "res://assets/locales"
## The tongues this build ships. The scan finds the same files; the list keeps
## them known when a pack cannot be listed.
const SHIPPED: Array[String] = [
	"res://assets/locales/fr.po",
	"res://assets/locales/es.po",
]
## A tongue's own name, so the picker prints Français rather than FR.
const NATIVE_NAMES: Dictionary = {
	"en": "English",
	"de": "Deutsch",
	"es": "Español",
	"fr": "Français",
	"it": "Italiano",
	"nl": "Nederlands",
	"pt": "Português",
}

## path → the locale code it answers (empty when the file holds no table).
static var _registered: Dictionary = {}


## The key one authored variant answers to, e.g.
## `DialoguePoint/diplomatic/peace_made/0`.
static func line_key(point: String, index: int) -> String:
	return "%s/%s/%d" % [KEY_PREFIX, point, index]


## A translated line, or the authored one when the key has no translation.
static func translate(key: String, fallback: String) -> String:
	load_shipped()
	var found: String = String(TranslationServer.translate(key))
	if found.is_empty() or found == key:
		return fallback
	return found


## Registers one shipped tongue once per path, and says whether it added a
## table. A build with no file — or a project whose assets were never imported —
## is not an error: every line keeps the authored source, so a court is never
## silent (REQ-P2-05).
static func register(path: String) -> bool:
	var wanted: String = path.strip_edges()
	if wanted.is_empty() or _registered.has(wanted):
		return false
	_registered[wanted] = ""
	if not ResourceLoader.exists(wanted):
		return false
	var words: Variant = load(wanted)
	if not (words is Translation):
		return false
	var table: Translation = words as Translation
	TranslationServer.add_translation(table)
	_registered[wanted] = String(table.locale)
	return true


## Registers every tongue this build ships.
static func load_shipped() -> void:
	for path: String in shipped_paths():
		register(path)


## Every tongue file this build knows, in one stable order: the shipped list
## first, then any `.po` a translator dropped beside them by name.
static func shipped_paths() -> PackedStringArray:
	var found: PackedStringArray = []
	for path: String in SHIPPED:
		if ResourceLoader.exists(path):
			found.append(path)
	var dir: DirAccess = DirAccess.open(SHIPPED_DIR)
	if dir == null:
		return found
	var extra: Array[String] = []
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".po"):
			continue
		var path: String = SHIPPED_DIR.path_join(file_name)
		if found.has(path) or not ResourceLoader.exists(path):
			continue
		extra.append(path)
	extra.sort()
	for path: String in extra:
		found.append(path)
	return found


## Every tongue a reader can pick, source first: `{code, name, path}`. The
## source tongue has no file — it is the authored line itself.
static func tongues() -> Array[Dictionary]:
	load_shipped()
	var rows: Array[Dictionary] = [
		{"code": SOURCE_LOCALE, "name": native_name(SOURCE_LOCALE), "path": ""},
	]
	for path: String in _registered.keys():
		var code: String = String(_registered[path])
		if code.is_empty() or code == SOURCE_LOCALE:
			continue
		rows.append({"code": code, "name": native_name(code), "path": path})
	return rows


## A tongue's own name, read from the root of a locale code (`fr_CA` reads
## Français). A code no table names still gets a legible label.
static func native_name(code: String) -> String:
	var root: String = code.strip_edges().to_lower().get_slice("_", 0)
	if root.is_empty():
		return SOURCE_LOCALE.to_upper()
	if NATIVE_NAMES.has(root):
		return String(NATIVE_NAMES[root])
	return root.to_upper()


## One variant of one point, in the locale the game is running.
static func line(point: String, index: int, source: String) -> String:
	return translate(line_key(point, index), source)


## The locale a campaign reads. The source language is the fallback, so a court
## always has a word to speak.
static func locale() -> String:
	var current: String = String(TranslationServer.get_locale())
	return current if not current.is_empty() else SOURCE_LOCALE


static func set_locale(code: String) -> void:
	var wanted: String = code.strip_edges()
	if wanted.is_empty():
		return
	TranslationServer.set_locale(wanted)


## The tongue the device itself asks for: what a reader who never picked one
## reads, and what the picker returns to. A device with no tongue set (a bare
## POSIX `C` locale, or none at all) reads the source, as the engine would.
static func device_locale() -> String:
	var code: String = OS.get_locale().strip_edges()
	var bare: String = code.to_upper()
	if code.is_empty() or bare == "C" or bare == "POSIX":
		return SOURCE_LOCALE
	return code


## Reads the device's own tongue again, undoing an explicit choice. Returns the
## locale the engine settles on, which is what a court now prints in.
static func follow_device() -> String:
	TranslationServer.set_locale(device_locale())
	return locale()


## Every locale that can be read: the shipped translations plus the source.
static func locales() -> PackedStringArray:
	var found: PackedStringArray = TranslationServer.get_loaded_locales()
	if not found.has(SOURCE_LOCALE):
		found.append(SOURCE_LOCALE)
	return found
