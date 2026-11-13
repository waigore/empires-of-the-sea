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
## One tongue ships today: the French words in [constant SHIPPED], loaded once
## on the first line a court speaks, so a build with no file still speaks the
## source (wiki: dialogue-content-and-yarn; DR-20261113-06). The reader's own
## tongue decides — the [TranslationServer] reads the OS locale, and a line the
## file does not answer keeps the English variant.

const SOURCE_LOCALE: String = "en"
const KEY_PREFIX: String = "DialoguePoint"
## The one shipped tongue: its file names the locale, so a `.po` dropped beside
## it (or renamed) is content the build learns without a project setting.
const SHIPPED: String = "res://assets/locales/fr.po"

static var _shipped: Dictionary = {}

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


## Registers a shipped tongue once per path. A build that has no file — or a
## project whose assets were never imported — is not an error: every line keeps
## the authored source, so a court is never silent (REQ-P2-05).
static func load_shipped(path: String = SHIPPED) -> void:
	if _shipped.has(path):
		return
	_shipped[path] = true
	if not ResourceLoader.exists(path):
		return
	var words: Variant = load(path)
	if words is Translation:
		TranslationServer.add_translation(words as Translation)


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
