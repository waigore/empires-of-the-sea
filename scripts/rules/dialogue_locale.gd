class_name DialogueLocale
extends RefCounted
## The court's words carry a stable key, so a translation can follow a line
## without touching code (wiki: dialogue-content-and-yarn § Design intent:
## "Content keys must be stable so authored scripts and localization stay
## aligned").
##
## Every authored line reads as `DialoguePoint/<category>/<situation>/<variant>`
## through Godot's [TranslationServer]. A shipped tongue (`SHIPPED`, one `.po` per
## tongue) fills the keys it names; an untranslated key falls back to the authored
## source line, so the source language is never lost and a file fills one point at
## a time (REQ-P2-05, DR-20261113-06). No rule reads a translated string
## (REQ-P2-03).

const SOURCE_LOCALE: String = "en"
const KEY_PREFIX: String = "DialoguePoint"
## The tongues that ship with the game, one `.po` per tongue. A file fills the
## lines its own keys name and leaves the rest to the authored English, so a
## tongue arrives as content and no code learns its name (DR-20261113-06). The
## list is read once, on the first line a court speaks.
const SHIPPED: PackedStringArray = ["res://assets/locales/fr.po"]

static var _loaded: bool = false


## The key one authored variant answers to, e.g.
## `DialoguePoint/diplomatic/peace_made/0`.
static func line_key(point: String, index: int) -> String:
	return "%s/%s/%d" % [KEY_PREFIX, point, index]


## Register every shipped tongue with the [TranslationServer], once. Godot reads
## the reader's own tongue from the OS, so a French device speaks French without
## a setting being found; a file that cannot be read is skipped, never fatal.
static func load_shipped() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in SHIPPED:
		var table: Variant = load(path)
		if table is Translation:
			TranslationServer.add_translation(table)


## A translated line, or the authored one when the key has no translation.
static func translate(key: String, fallback: String) -> String:
	load_shipped()
	var found: String = String(TranslationServer.translate(key))
	if found.is_empty() or found == key:
		return fallback
	return found


## One variant of one point, in the locale the game is running.
static func line(point: String, index: int, source: String) -> String:
	return translate(line_key(point, index), source)


## The locale a campaign reads. The source language is the fallback, so a court
## always has a word to speak.
static func locale() -> String:
	load_shipped()
	var current: String = String(TranslationServer.get_locale())
	return current if not current.is_empty() else SOURCE_LOCALE


static func set_locale(code: String) -> void:
	var wanted: String = code.strip_edges()
	if wanted.is_empty():
		return
	TranslationServer.set_locale(wanted)


## Every locale that can be read: the shipped translations plus the source.
static func locales() -> PackedStringArray:
	load_shipped()
	var found: PackedStringArray = TranslationServer.get_loaded_locales()
	found.append(SOURCE_LOCALE)
	return found
