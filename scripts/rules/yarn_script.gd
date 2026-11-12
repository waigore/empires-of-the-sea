class_name YarnScript
extends RefCounted
## The Yarn (Spinner) subset the court's dialogue is authored in (wiki:
## dialogue-content-and-yarn § Design intent, § Architecture: lines, variables
## and options are authored content, separate from the rules that decide
## outcomes).
##
## A source is a run of nodes:
## [codeblock]
## title: DialoguePoint/reactive/standing_war
## tags: category:reactive mood:dismissive
## ---
## The war stands.
## -> Accept <<jump DialoguePoint/diplomatic/peace_made>>
## ===
## [/codeblock]
##
## A body holds plain lines (with `#tags`), `->` options (with an optional
## `<<command>>` and its own `#tags`), `<<set $x = ...>>`, `<<if>>` /
## `<<elseif>>` / `<<else>>` / `<<endif>>`, `<<jump Node>>` and `<<stop>>`.
## Parsing is pure and reports the first malformed line, so authored content
## fails at load rather than mid-scene (REQ-P2-01, REQ-P3-03).

const NODE_END: String = "==="
const BODY_START: String = "---"

## The whole program, or `{ok: false, error: <the first bad line>}`. A program
## is `{ok, error, nodes}` where each node is `{title, tags, steps}`.
static func parse(source: String) -> Dictionary:
	var nodes: Dictionary = {}
	var raw_lines: PackedStringArray = source.split("\n")
	var title: String = ""
	var tags: Array[String] = []
	var at: int = 0
	while at < raw_lines.size():
		var raw: String = String(raw_lines[at]).strip_edges()
		at += 1
		if raw.is_empty() or raw.begins_with("//"):
			continue
		if raw.begins_with("title:"):
			title = raw.substr(6).strip_edges()
			tags = []
			if title.is_empty():
				return _fail("line %d: a node needs a title" % at)
			if nodes.has(title):
				return _fail("line %d: '%s' is authored twice" % [at, title])
			continue
		if raw.begins_with("tags:"):
			tags = _words(raw.substr(5))
			continue
		if raw == BODY_START:
			if title.is_empty():
				return _fail("line %d: a body has no title" % at)
			var base: int = at
			var body: Array = []
			while at < raw_lines.size() and String(raw_lines[at]).strip_edges() != NODE_END:
				body.append(raw_lines[at])
				at += 1
			if at >= raw_lines.size():
				return _fail("line %d: node '%s' has no %s" % [at, title, NODE_END])
			at += 1
			var built: Dictionary = _steps(body, base)
			if not built.has("steps"):
				return _fail(String(built.get("error", "the body cannot be read")))
			nodes[title] = {"title": title, "tags": tags, "steps": built["steps"]}
			title = ""
			tags = []
			continue
		return _fail("line %d: '%s' is outside a node" % [at, raw])
	if not title.is_empty():
		return _fail("line %d: node '%s' has no body" % [at, title])
	return {"ok": true, "error": "", "nodes": nodes}


static func node_names(program: Dictionary) -> Array[String]:
	var names: Array[String] = []
	var nodes: Variant = program.get("nodes", {})
	if typeof(nodes) != TYPE_DICTIONARY:
		return names
	for name: String in (nodes as Dictionary).keys():
		names.append(name)
	names.sort()
	return names


static func _steps(body: Array, base: int) -> Dictionary:
	var cursor: Dictionary = {"at": 0}
	var block: Dictionary = _block(body, cursor, base, [])
	if not block.has("steps"):
		return {"error": String(block.get("error", "the body cannot be read"))}
	if block.has("terminator"):
		return {
			"error": "line %d: '<<%s>>' has no opening" % [
				int(block.get("line", 0)), String(block["terminator"])
			]
		}
	return {"steps": block["steps"]}


## One run of steps, stopping at (and reporting) the first block terminator the
## caller asked for. Nesting is the recursion: an `<<if>>` body is a block too.
static func _block(body: Array, cursor: Dictionary, base: int, stops: Array) -> Dictionary:
	var steps: Array = []
	while int(cursor.get("at", 0)) < body.size():
		var offset: int = int(cursor["at"])
		var text: String = String(body[offset]).strip_edges()
		var line: int = base + offset + 1
		cursor["at"] = offset + 1
		if text.is_empty() or text.begins_with("//"):
			continue
		if text.begins_with("<<"):
			var command: Dictionary = _command(text)
			if command.is_empty():
				return {"error": "line %d: '%s' is not a command" % [line, text]}
			var word: String = String(command["word"])
			if stops.has(word):
				return {"steps": steps, "terminator": word, "rest": command["rest"], "line": line}
			var step_error: String = _fold_command(steps, body, cursor, base, command, line)
			if not step_error.is_empty():
				return {"error": step_error}
			continue
		if text.begins_with("->"):
			var option: Dictionary = _option(text, line)
			if not option.has("option"):
				return {"error": String(option.get("error", ""))}
			_add_option(steps, option["option"])
			continue
		var tagged: Dictionary = _tagged(text)
		steps.append({"kind": "line", "text": tagged["text"], "tags": tagged["tags"]})
	return {"steps": steps}


## Folds one `<<command>>` into the step list; returns "" or the first error.
static func _fold_command(
	steps: Array,
	body: Array,
	cursor: Dictionary,
	base: int,
	command: Dictionary,
	line: int
) -> String:
	var word: String = String(command["word"])
	match word:
		"set", "declare":
			var step: Dictionary = _set_step(String(command["rest"]))
			if not step.has("kind"):
				return "line %d: %s" % [line, String(step.get("error", "the value cannot be read"))]
			steps.append(step)
		"if":
			var folded: Dictionary = _if_step(body, cursor, base, String(command["rest"]), line)
			if not folded.has("step"):
				return String(folded.get("error", ""))
			steps.append(folded["step"])
		"jump":
			var target: String = String(command["rest"]).strip_edges()
			if target.is_empty():
				return "line %d: <<jump>> names no node" % line
			steps.append({"kind": "jump", "node": target})
		"stop":
			steps.append({"kind": "stop"})
		_:
			return "line %d: '<<%s>>' is not a command this runtime reads" % [line, word]
	return ""


## `<<if>>` through its `<<endif>>`, `<<elseif>>`s and `<<else>>` included. The
## conditions are parsed here, so a malformed one fails at load.
static func _if_step(
	body: Array, cursor: Dictionary, base: int, condition: String, line: int
) -> Dictionary:
	var branches: Array = []
	var else_steps: Array = []
	var ast: Dictionary = YarnExpr.parse(condition)
	if ast.is_empty():
		return {"error": "line %d: the condition '%s' cannot be read" % [line, condition]}
	while true:
		var block: Dictionary = _block(body, cursor, base, ["elseif", "else", "endif"])
		if not block.has("steps"):
			return {"error": String(block.get("error", ""))}
		branches.append({"ast": ast, "steps": block["steps"]})
		var terminator: String = String(block.get("terminator", ""))
		if terminator == "endif":
			break
		if terminator.is_empty():
			return {"error": "line %d: <<if>> has no <<endif>>" % line}
		if terminator == "else":
			var tail: Dictionary = _block(body, cursor, base, ["endif"])
			if not tail.has("steps"):
				return {"error": String(tail.get("error", ""))}
			if String(tail.get("terminator", "")) != "endif":
				return {"error": "line %d: <<else>> has no <<endif>>" % line}
			else_steps = tail["steps"]
			break
		ast = YarnExpr.parse(String(block.get("rest", "")))
		if ast.is_empty():
			return {"error": "line %d: the condition '%s' cannot be read" % [line, block.get("rest", "")]}
	return {"step": {"kind": "if", "branches": branches, "else_steps": else_steps}}


static func _set_step(rest: String) -> Dictionary:
	var text: String = rest.strip_edges()
	if not text.begins_with("$"):
		return {"error": "'%s' does not name a variable" % text}
	var equals_at: int = text.find("=")
	var name: String = text.substr(1, equals_at - 1 if equals_at >= 0 else -1).strip_edges()
	var value: String = text.substr(equals_at + 1).strip_edges() if equals_at >= 0 else "false"
	if name.is_empty() or not name.is_valid_identifier():
		return {"error": "'%s' is not a variable name" % name}
	var ast: Dictionary = YarnExpr.parse(value)
	if ast.is_empty():
		return {"error": "the value '%s' cannot be read" % value}
	return {"kind": "set", "name": name, "ast": ast}


static func _option(text: String, line: int) -> Dictionary:
	var body: String = text.substr(2).strip_edges()
	var command: String = ""
	var open_at: int = body.find("<<")
	if open_at >= 0:
		var close_at: int = body.find(">>", open_at)
		if close_at < 0:
			return {"error": "line %d: the option's command is not closed" % line}
		command = body.substr(open_at + 2, close_at - open_at - 2).strip_edges()
		body = (body.substr(0, open_at) + body.substr(close_at + 2)).strip_edges()
	var tagged: Dictionary = _tagged(body)
	if String(tagged["text"]).is_empty():
		return {"error": "line %d: an option has no text" % line}
	return {"option": {"text": tagged["text"], "command": command, "tags": tagged["tags"]}}


static func _add_option(steps: Array, option: Dictionary) -> void:
	if not steps.is_empty() and String(steps[-1].get("kind", "")) == "options":
		steps[-1]["options"].append(option)
		return
	steps.append({"kind": "options", "options": [option]})


## `<<word rest>>` split once; `{}` when the caller's brackets are malformed.
static func _command(text: String) -> Dictionary:
	if not text.ends_with(">>"):
		return {}
	var inner: String = text.substr(2, text.length() - 4).strip_edges()
	if inner.is_empty():
		return {}
	var space_at: int = inner.find(" ")
	if space_at < 0:
		return {"word": inner, "rest": ""}
	return {"word": inner.substr(0, space_at), "rest": inner.substr(space_at + 1).strip_edges()}


## Strips trailing `#tags` off a line or an option, keeping the authored text
## (and its punctuation) as written.
static func _tagged(text: String) -> Dictionary:
	var tags: Array[String] = []
	var body: String = text.strip_edges()
	while true:
		var hash_at: int = body.rfind(" #")
		if hash_at < 0:
			break
		tags.push_front(body.substr(hash_at + 2).strip_edges())
		body = body.substr(0, hash_at).strip_edges()
	if body.begins_with("#"):
		tags.push_front(body.substr(1).strip_edges())
		body = ""
	return {"text": body.strip_edges(), "tags": tags}


static func _words(text: String) -> Array[String]:
	var found: Array[String] = []
	for word: String in text.split(" ", false):
		var trimmed: String = word.strip_edges()
		if not trimmed.is_empty():
			found.append(trimmed)
	return found


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "nodes": {}}
