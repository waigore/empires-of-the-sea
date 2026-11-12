class_name YarnExpr
extends RefCounted
## A Yarn `<<if>>` expression (wiki: dialogue-content-and-yarn § Architecture).
## The subset the court's scripts use is small on purpose: `$variables`, numbers,
## quoted strings, `true`/`false`, `+ - * / %`, `== != < <= > >=`, `and`/`or`/
## `not` (also `&&`, `||`, `!`) and parentheses. Parsing yields a tree of plain
## dictionaries and evaluation mutates nothing, so a reloaded campaign reads the
## same branch (REQ-P2-04, REQ-P3-03).
##
## A malformed expression parses to `{}`, so the caller refuses a script at load
## rather than guessing mid-scene (REQ-P2-01).

const _PAIR_OPS: Array[String] = ["==", "!=", "<=", ">=", "&&", "||"]
const _SINGLE_OPS: Array[String] = ["<", ">", "+", "-", "*", "/", "%", "(", ")", "!"]

var _tokens: Array = []
var _at: int = 0


func _init(tokens: Array = []) -> void:
	_tokens = tokens


## The parsed tree, or `{}` when the text is not an expression this runtime
## reads. Callers validate at parse time, so a bad condition never reaches a run.
static func parse(text: String) -> Dictionary:
	var tokens: Array = _tokenize(text)
	if tokens.is_empty():
		return {}
	var cursor := YarnExpr.new(tokens)
	var ast: Dictionary = cursor._or()
	if ast.is_empty() or cursor._at != tokens.size():
		return {}
	return ast


## The value of a parsed expression against a variable store. A variable a
## script never set reads as `null`, so a condition on it is simply false.
static func evaluate(ast: Dictionary, variables: Dictionary) -> Variant:
	match String(ast.get("kind", "")):
		"literal":
			return ast.get("value", null)
		"variable":
			return variables.get(String(ast.get("name", "")), null)
		"op":
			return _apply(ast, variables)
	return null


## Why: a script may gate on a string, a number or a flag, and authored content
## must not care which it used.
static func truthy(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_INT, TYPE_FLOAT:
			return float(value) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return not String(value).is_empty()
	return bool(value)


static func _apply(ast: Dictionary, variables: Dictionary) -> Variant:
	var op: String = String(ast.get("op", ""))
	var a: Variant = evaluate(ast.get("a", {}), variables)
	var b: Variant = evaluate(ast.get("b", {}), variables)
	match op:
		"and":
			return truthy(a) and truthy(b)
		"or":
			return truthy(a) or truthy(b)
		"not":
			return not truthy(a)
		"neg":
			return -_numeric(a)
		"==":
			return _equal(a, b)
		"!=":
			return not _equal(a, b)
		"<":
			return _numeric(a) < _numeric(b)
		"<=":
			return _numeric(a) <= _numeric(b)
		">":
			return _numeric(a) > _numeric(b)
		">=":
			return _numeric(a) >= _numeric(b)
		"+" when typeof(a) == TYPE_STRING or typeof(b) == TYPE_STRING:
			return _text(a) + _text(b)
		"+":
			return _tidy(_numeric(a) + _numeric(b))
		"-":
			return _tidy(_numeric(a) - _numeric(b))
		"*":
			return _tidy(_numeric(a) * _numeric(b))
		"/":
			return 0 if is_zero_approx(_numeric(b)) else _tidy(_numeric(a) / _numeric(b))
		"%":
			return _modulo(_numeric(a), _numeric(b))
	return null


## Why: the court's scripts count variants with `%`, and whole numbers read far
## more plainly in authored content than the float remainder does.
static func _modulo(left: float, right: float) -> Variant:
	if is_zero_approx(right):
		return 0
	if is_equal_approx(left, roundf(left)) and is_equal_approx(right, roundf(right)):
		return int(roundf(left)) % int(roundf(right))
	return fmod(left, right)


static func _equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_STRING and typeof(b) == TYPE_STRING:
		return String(a) == String(b)
	return _numeric(a) == _numeric(b)


static func _numeric(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return 1.0 if bool(value) else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var text: String = String(value).strip_edges()
			return float(text) if text.is_valid_float() else 0.0
	return 0.0


static func _tidy(value: float) -> Variant:
	if is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	return value


static func _text(value: Variant) -> String:
	return "" if value == null else String(value)


static func _tokenize(text: String) -> Array:
	var tokens: Array = []
	var at: int = 0
	var length: int = text.length()
	while at < length:
		var ch: String = text[at]
		if ch == " " or ch == "\t":
			at += 1
			continue
		if ch == "\"" or ch == "'":
			var quoted: Array = _read_string(text, at, ch)
			if quoted.is_empty():
				return []
			tokens.append({"t": "literal", "v": quoted[0]})
			at = int(quoted[1])
			continue
		if ch == "$":
			var name_end: int = at + 1
			while name_end < length and _is_name_char(text[name_end]):
				name_end += 1
			if name_end == at + 1:
				return []
			tokens.append({"t": "variable", "v": text.substr(at + 1, name_end - at - 1)})
			at = name_end
			continue
		if ch >= "0" and ch <= "9":
			var number_end: int = at
			var dotted: bool = false
			while number_end < length and ((text[number_end] >= "0" and text[number_end] <= "9") or
					(text[number_end] == "." and not dotted)):
				dotted = dotted or text[number_end] == "."
				number_end += 1
			var raw: String = text.substr(at, number_end - at)
			tokens.append({"t": "literal", "v": float(raw) if dotted else int(raw)})
			at = number_end
			continue
		if _is_name_char(ch):
			var word_end: int = at
			while word_end < length and _is_name_char(text[word_end]):
				word_end += 1
			var word: String = text.substr(at, word_end - at)
			if word == "and" or word == "or" or word == "not":
				tokens.append({"t": "op", "v": word})
			elif word == "true" or word == "false":
				tokens.append({"t": "literal", "v": word == "true"})
			else:
				return []
			at = word_end
			continue
		var pair: String = text.substr(at, 2)
		if _PAIR_OPS.has(pair):
			tokens.append({"t": "op", "v": "and" if pair == "&&" else ("or" if pair == "||" else pair)})
			at += 2
			continue
		if _SINGLE_OPS.has(ch):
			tokens.append({"t": "op", "v": "not" if ch == "!" else ch})
			at += 1
			continue
		return []
	return tokens


## Quotes read literally: authored lines keep their punctuation, and a broken
## quote refuses the whole script instead of swallowing the rest of the file.
static func _read_string(text: String, at: int, quote: String) -> Array:
	var value: String = ""
	var cursor: int = at + 1
	while cursor < text.length():
		if text[cursor] == quote:
			return [value, cursor + 1]
		value += text[cursor]
		cursor += 1
	return []


static func _is_name_char(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") \
		or ch == "_"


func _or() -> Dictionary:
	var left: Dictionary = _and()
	while _accept("or"):
		left = _joined("or", left, _and())
	return left


func _and() -> Dictionary:
	var left: Dictionary = _comparison()
	while _accept("and"):
		left = _joined("and", left, _comparison())
	return left


func _comparison() -> Dictionary:
	var left: Dictionary = _additive()
	for op: String in ["==", "!=", "<=", ">=", "<", ">"]:
		if _accept(op):
			return _joined(op, left, _additive())
	return left


func _additive() -> Dictionary:
	var left: Dictionary = _multiplicative()
	while not left.is_empty():
		if _accept("+"):
			left = _joined("+", left, _multiplicative())
		elif _accept("-"):
			left = _joined("-", left, _multiplicative())
		else:
			break
	return left


func _multiplicative() -> Dictionary:
	var left: Dictionary = _unary()
	while not left.is_empty():
		var op: String = ""
		for candidate: String in ["*", "/", "%"]:
			if _accept(candidate):
				op = candidate
				break
		if op.is_empty():
			break
		left = _joined(op, left, _unary())
	return left


func _unary() -> Dictionary:
	if _accept("not"):
		return _joined("not", _unary(), {})
	if _accept("-"):
		return _joined("neg", _unary(), {})
	return _atom()


func _atom() -> Dictionary:
	if _accept("("):
		var inner: Dictionary = _or()
		if inner.is_empty() or not _accept(")"):
			return {}
		return inner
	var token: Dictionary = _take()
	match String(token.get("t", "")):
		"literal":
			return {"kind": "literal", "value": token.get("v", null)}
		"variable":
			return {"kind": "variable", "name": String(token.get("v", ""))}
	return {}


static func _joined(op: String, left: Dictionary, right: Dictionary) -> Dictionary:
	var unary: bool = op == "not" or op == "neg"
	if left.is_empty() or (not unary and right.is_empty()):
		return {}
	return {"kind": "op", "op": op, "a": left, "b": right}


func _accept(op: String) -> bool:
	if _at >= _tokens.size():
		return false
	if String(_tokens[_at].get("t", "")) != "op":
		return false
	if String(_tokens[_at].get("v", "")) != op:
		return false
	_at += 1
	return true


func _take() -> Dictionary:
	if _at >= _tokens.size():
		return {}
	var token: Dictionary = _tokens[_at]
	_at += 1
	return token
