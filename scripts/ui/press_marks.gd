class_name PressMarks
extends RefCounted
## The book a sheet keeps for its presses: each press's caption as the rules
## worded it, and the keys one counsel reading names. A sheet registers a press
## once, asks the book to print it, and the press that reading names leads with
## the counsel's mark while the rest read plainly (DR-20261122-23).
##
## The caption is the caller's own words, never what the button last showed, so a
## mark is added and lifted again without doubling a glyph or losing a price the
## rules re-worded between two readings (REQ-P5-06, RUB-P3-01). The book holds no
## node and reads no state: a sheet still owns its buttons, and this owns only the
## words they print.

## The counsel's mark: the glyph every marked press, row and name in the crown's
## sheets leads with.
const MARK: String = "▸"

## key → the press's own caption, as the rules worded it.
var _captions: Dictionary = {}
## The keys the last reading named.
var _keys: Dictionary = {}


## Registers one press's caption — the rules' own words, which the mark never
## rewrites — so every later reading prints from a clean face.
func set_caption(key: String, caption: String) -> void:
	if key.is_empty():
		return
	_captions[key] = caption


## The caption a press prints now: marked when the reading names its key,
## otherwise the rules' own words.
func text(key: String) -> String:
	var caption: String = String(_captions.get(key, ""))
	if caption.is_empty():
		return ""
	return ("%s %s" % [MARK, caption]) if _keys.has(key) else caption


## Whether the reading names any press at all — the condition a legend stands on.
func any() -> bool:
	return not _keys.is_empty()


## Replaces the reading with the one just asked, so the next `text` answers it.
func mark(keys: Dictionary) -> void:
	_keys = keys.duplicate() if keys != null else {}


## The keys the last reading named, for a sheet that hands them on.
func keys() -> Dictionary:
	return _keys
