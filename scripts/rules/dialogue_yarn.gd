class_name DialogueYarn
extends RefCounted
## The court's standing word, authored as Yarn (wiki: dialogue-content-and-yarn
## § Design intent: lines, variables and options are authored content, separate
## from the rules that decide outcomes).
##
## Each node's title is the point's stable content key, `DialoguePoint/
## <category>/<situation>`, so a line keeps its key when it moves out of
## GDScript and a translation can follow it (REQ-P2-05). The node's `tags:` line
## carries the point's `category:` and its `mood:` faces, and its body carries
## the variants. [DialogueCatalog] merges this table with its own, so every
## caller keeps asking one class.
##
## Presentation only: the lines below are read back into a court's voice and
## never feed an outcome (REQ-P2-03).

const KEY_PREFIX: String = "DialoguePoint/"

const SOURCE: String = """
// The court's standing word by relation band. One node per point; the band
// itself is chosen by the rules, so a line can never move a court's stand.
title: DialoguePoint/reactive/standing_war
tags: category:reactive mood:dismissive
---
The war stands. We shall speak again when one of us tires.
Our courts have nothing to add to the guns.
===

title: DialoguePoint/reactive/standing_alliance
tags: category:reactive mood:pleased
---
Your court is always welcome here, and your squadrons beside ours.
The alliance holds. Long may it suit us both.
===

title: DialoguePoint/reactive/standing_friendly
tags: category:reactive mood:gracious mood:pleased
---
You will always find a friend of our court in this harbour.
Our doors are open to your envoy, at any hour.
===

title: DialoguePoint/reactive/standing_cold
tags: category:reactive mood:skeptical mood:dismissive
---
We have little to say to your court.
Our clerks record your name, and nothing warmer.
===

title: DialoguePoint/reactive/standing_neutral
tags: category:reactive mood:calculating mood:considering
---
Our clerks record your name; nothing more today.
The court is civil, and no more than civil.
===
"""

## How many beats one node may yield before the reader gives up: authored content
## is data, so a jump that loops must not hang a panel refresh (REQ-P4-02).
const BEAT_LIMIT: int = 200

static var _program: Dictionary = {}
static var _table: Dictionary = {}


static func program() -> Dictionary:
	if _program.is_empty():
		_program = YarnScript.parse(SOURCE)
	return _program


## Point name → `{category, moods, lines}`, the same shape [DialogueCatalog]
## authors by hand. A node whose body reads to no line is left out, so a typo in
## authored content falls back to the caller's own table instead of silencing a
## court.
static func table() -> Dictionary:
	if _table.is_empty():
		_table = _read_program()
	return _table


static func points() -> Array[String]:
	var found: Array[String] = []
	for point: String in table().keys():
		found.append(point)
	found.sort()
	return found


static func has_point(point: String) -> bool:
	return table().has(point)


static func category_for(point: String) -> String:
	var entry: Dictionary = _entry(point)
	return String(entry.get("category", ""))


static func lines_for(point: String) -> Array:
	var raw: Variant = _entry(point).get("lines", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


static func moods_for(point: String) -> Array:
	var raw: Variant = _entry(point).get("moods", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


## One authored variant, picked by the caller's stable salt so a reloaded
## campaign speaks the same words (REQ-P2-04).
static func line_for(point: String, salt: int) -> String:
	var lines: Array = lines_for(point)
	if lines.is_empty():
		return ""
	return String(lines[absi(salt) % lines.size()])


static func _read_program() -> Dictionary:
	var built: Dictionary = {}
	var nodes: Dictionary = program().get("nodes", {})
	for title: String in nodes.keys():
		if not title.begins_with(KEY_PREFIX):
			continue
		var node: Dictionary = nodes[title]
		var lines: Array = _spoken_lines(String(node.get("title", "")))
		if lines.is_empty():
			continue
		var tags: Array = node.get("tags", [])
		built[title.substr(KEY_PREFIX.length())] = {
			"category": _tag_value(tags, "category"),
			"moods": _tag_values(tags, "mood"),
			"lines": lines,
		}
	return built


## Reads a node through the runtime, which is what makes conditions, jumps and
## variables work in authored content. An option group ends the reading: a
## standing word is spoken, never asked.
static func _spoken_lines(title: String) -> Array:
	var found: Array = []
	var runner := YarnRunner.new(program())
	if not runner.start(title):
		return found
	for _beat in BEAT_LIMIT:
		var beat: Dictionary = runner.advance()
		match String(beat.get("kind", "")):
			"line":
				found.append(String(beat.get("text", "")))
			"done", "error":
				return found
			_:
				return found
	return found


static func _tag_value(tags: Array, key: String) -> String:
	var found: Array = _tag_values(tags, key)
	return String(found[0]) if not found.is_empty() else ""


static func _tag_values(tags: Array, key: String) -> Array:
	var found: Array = []
	for tag: Variant in tags:
		var text: String = String(tag)
		if text.begins_with("%s:" % key):
			found.append(text.substr(key.length() + 1))
	return found


static func _entry(point: String) -> Dictionary:
	var raw: Variant = table().get(point, {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}
