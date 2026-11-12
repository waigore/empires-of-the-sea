class_name YarnRunner
extends RefCounted
## Runs one parsed [YarnScript] node (wiki: dialogue-content-and-yarn §
## Architecture: the game layer sets the variables, jumps to the node and maps
## an option's command to a resume payload).
##
## The runner is plain state — a stack of step frames, a variable store and the
## node it is reading — so it never touches a node tree and a reloaded campaign
## replays the same lines (REQ-P2-04, REQ-P3-03). `advance()` yields one beat at
## a time: a spoken line, an option group, or the end; sets, conditions and jumps
## are resolved between beats and never reach the caller.

var variables: Dictionary = {}

var _program: Dictionary = {}
var _stack: Array = []
var _pending: Array = []
var _node: String = ""
var _done: bool = false


func _init(program: Dictionary, vars: Dictionary = {}) -> void:
	_program = program
	variables = vars.duplicate(true)


## Begins a node. False when the program has no such node, so a script that
## jumps into a title nobody authored fails loudly at its caller.
func start(node: String) -> bool:
	var nodes: Dictionary = _program.get("nodes", {})
	if not nodes.has(node):
		return false
	_node = node
	_done = false
	_pending = []
	_stack = [{"steps": (nodes[node] as Dictionary).get("steps", []), "at": 0}]
	return true


## The next beat: `{kind: "line", text, tags}`, `{kind: "options", options}`,
## `{kind: "done"}`, or `{kind: "error", error}` for a jump into a missing node.
func advance() -> Dictionary:
	while not _done:
		if not _pending.is_empty():
			return {"kind": "options", "options": _pending}
		var step: Dictionary = _next_step()
		if step.is_empty():
			_done = true
			break
		match String(step.get("kind", "")):
			"line":
				return {
					"kind": "line",
					"text": interpolate(String(step.get("text", ""))),
					"tags": step.get("tags", []),
				}
			"set":
				variables[String(step.get("name", ""))] = YarnExpr.evaluate(
					step.get("ast", {}), variables
				)
			"if":
				_enter(step)
			"jump":
				if not _jump(String(step.get("node", ""))):
					_done = true
					return {
						"kind": "error",
						"error": "unknown node '%s'" % String(step.get("node", "")),
					}
			"stop":
				_done = true
			"options":
				_pending = step.get("options", [])
				return {"kind": "options", "options": _pending}
	return {"kind": "done"}


## Answers the option group `advance()` last returned, running its command: a
## `<<jump>>` moves the runner, `<<stop>>` ends it. An out-of-range pick (or a
## command this runtime does not run) is refused and the scene is left as it
## was, so a caller never resumes into a half-read option.
func choose(index: int) -> bool:
	if index < 0 or index >= _pending.size():
		return false
	var command: String = String(_pending[index].get("command", ""))
	var parsed: Dictionary = {} if command.is_empty() else _as_command(command)
	var word: String = String(parsed.get("word", ""))
	if not word.is_empty() and word != "jump" and word != "stop":
		return false
	_pending = []
	if word == "jump":
		return _jump(String(parsed.get("rest", "")))
	if word == "stop":
		_done = true
	return true


## Fills `{$variable}` (and `{$a + b}`) into authored text. Anything that is not
## a readable expression is left exactly as written.
func interpolate(text: String) -> String:
	if not text.contains("{$"):
		return text
	var out: String = ""
	var at: int = 0
	while true:
		var open_at: int = text.find("{$", at)
		if open_at < 0:
			out += text.substr(at)
			return out
		var close_at: int = text.find("}", open_at)
		if close_at < 0:
			out += text.substr(at)
			return out
		out += text.substr(at, open_at - at)
		var ast: Dictionary = YarnExpr.parse(text.substr(open_at + 1, close_at - open_at - 1))
		out += _spell(YarnExpr.evaluate(ast, variables)) if not ast.is_empty() \
			else text.substr(open_at, close_at - open_at + 1)
		at = close_at + 1
	return out


## True when the node has nothing left to say: no option group is on offer and
## no step (in this frame or an enclosing one) is left to read.
func at_end() -> bool:
	if not _pending.is_empty():
		return false
	if _done:
		return true
	return not _has_step_left()


func node_name() -> String:
	return _node


func _has_step_left() -> bool:
	for frame: Dictionary in _stack:
		if int(frame.get("at", 0)) < (frame.get("steps", []) as Array).size():
			return true
	return false


func _next_step() -> Dictionary:
	while not _stack.is_empty():
		var frame: Dictionary = _stack[-1]
		var steps: Array = frame.get("steps", [])
		var at: int = int(frame.get("at", 0))
		if at >= steps.size():
			_stack.pop_back()
			continue
		frame["at"] = at + 1
		return steps[at]
	return {}


## Pushes the first branch whose condition holds, else the `<<else>>` block.
func _enter(step: Dictionary) -> void:
	for branch: Variant in step.get("branches", []):
		if typeof(branch) != TYPE_DICTIONARY:
			continue
		var ast: Dictionary = (branch as Dictionary).get("ast", {})
		if YarnExpr.truthy(YarnExpr.evaluate(ast, variables)):
			_stack.append({"steps": (branch as Dictionary).get("steps", []), "at": 0})
			return
	var fallback: Array = step.get("else_steps", [])
	if not fallback.is_empty():
		_stack.append({"steps": fallback, "at": 0})


func _jump(node: String) -> bool:
	var nodes: Dictionary = _program.get("nodes", {})
	if not nodes.has(node):
		return false
	_node = node
	_pending = []
	_stack = [{"steps": (nodes[node] as Dictionary).get("steps", []), "at": 0}]
	return true


static func _as_command(text: String) -> Dictionary:
	var inner: String = text.strip_edges()
	if inner.begins_with("<<"):
		inner = inner.substr(2).strip_edges()
	if inner.ends_with(">>"):
		inner = inner.substr(0, inner.length() - 2).strip_edges()
	var space_at: int = inner.find(" ")
	if space_at < 0:
		return {"word": inner, "rest": ""}
	return {"word": inner.substr(0, space_at), "rest": inner.substr(space_at + 1).strip_edges()}


static func _spell(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return ""
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_FLOAT:
			var number: float = float(value)
			return str(int(roundf(number))) if is_equal_approx(number, roundf(number)) else str(number)
	return str(value)
