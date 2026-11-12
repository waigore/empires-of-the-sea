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

const SOURCE_LOCALE: String = "en"
const KEY_PREFIX: String = "DialoguePoint"

## The key one authored variant answers to, e.g.
## `DialoguePoint/diplomatic/peace_made/0`.
static func line_key(point: String, index: int) -> String:
	return "%s/%s/%d" % [KEY_PREFIX, point, index]


## A translated line, or the authored one when the key has no translation.
static func translate(key: String, fallback: String) -> String:
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
	var current: String = String(TranslationServer.get_locale())
	return current if not current.is_empty() else SOURCE_LOCALE


static func set_locale(code: String) -> void:
	var wanted: String = code.strip_edges()
	if wanted.is_empty():
		return
	TranslationServer.set_locale(wanted)


## Every locale that can be read: the shipped translations plus the source.
static func locales() -> PackedStringArray:
	var found: PackedStringArray = TranslationServer.get_loaded_locales()
	found.append(SOURCE_LOCALE)
	return found
