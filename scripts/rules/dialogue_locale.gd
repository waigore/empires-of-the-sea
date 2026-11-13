class_name DialogueLocale
extends RefCounted
## The court's words carry a stable key so authored lines stay aligned
## (wiki: dialogue-content-and-yarn). English is the only supported language:
## every lookup returns the authored source line (REQ-P2-05). No rule reads a
## translated string (REQ-P2-03).

const SOURCE_LOCALE: String = "en"
const KEY_PREFIX: String = "DialoguePoint"


## The key one authored variant answers to, e.g.
## `DialoguePoint/diplomatic/peace_made/0`.
static func line_key(point: String, index: int) -> String:
	return "%s/%s/%d" % [KEY_PREFIX, point, index]


## English only: the authored line is what the court prints.
static func translate(_key: String, fallback: String) -> String:
	ensure_english()
	return fallback


## One variant of one point, in English.
static func line(point: String, index: int, source: String) -> String:
	return translate(line_key(point, index), source)


## The locale a campaign reads — always English.
static func locale() -> String:
	ensure_english()
	return SOURCE_LOCALE


## English only: any other code is ignored.
static func set_locale(_code: String) -> void:
	ensure_english()


## Pins the engine to English so an OS tongue never steers court copy.
static func ensure_english() -> void:
	if String(TranslationServer.get_locale()) != SOURCE_LOCALE:
		TranslationServer.set_locale(SOURCE_LOCALE)


## The only supported locale.
static func locales() -> PackedStringArray:
	return PackedStringArray([SOURCE_LOCALE])
