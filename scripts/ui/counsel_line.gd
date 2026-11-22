class_name CounselLine
extends Label
## The crown's one gold counsel line: the court's own reading of a sheet, dressed,
## gated and worded in one place (REQ-P3-01, REQ-P3-02, REQ-P5-06).
##
## A sheet wires `source` to the pass that answers it — a line already worded, or
## a pick whose `line` is the sentence — and `args` to what that pass asks with.
## `sync` prints the answer, holds the pick it read (so a row's `▸` and the
## sentence come off one read, REQ-P4-01) and stands the line down when nothing is
## named. A `gate` that answers false (a closed sheet) asks the pass nothing,
## because the walk is a planner pass no one is looking at (REQ-P4-02).
##
## A sheet that reads its pick once at the refresh prints it with `show_value`
## instead, and marks its rows off `keys`. No sheet restates the gold dress, the
## capital or the full stop (REQ-P5-06, RUB-P3-01).

## The pass that answers the line: a String already worded, or a pick Dictionary
## whose `line` is the sentence. Unwired prints nothing.
var source: Callable = Callable()
## The arguments `source` is asked with, in the sheet's own reading order.
var args: Array = []
## True when the sheet is up. Unwired always asks; a sheet hands `is_open` so a
## closed sheet reads nothing (REQ-P4-02).
var gate: Callable = Callable()
## The pick the last reading answered, or {} for a plain line. A sheet that marks
## its rows keys them off this one read (DR-20261122-03, DR-20261122-04).
var pick: Dictionary = {}


## The line, dressed gold and wrapped, hidden until a reading stands it up.
## `host` takes it where the sheet mounts it; a body hook may mount it instead.
static func make(host: Container = null) -> CounselLine:
	var line := CounselLine.new()
	if host != null:
		host.add_child(line)
	return line


func _init() -> void:
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Palette.GOLD)
	visible = false


## Asks the pass through the gate and prints its answer.
func sync() -> void:
	show_value(read_value())


## The raw answer, or null while the sheet is shut or the line is unwired.
func read_value() -> Variant:
	if gate.is_valid() and not bool(gate.call()):
		return null
	if not source.is_valid():
		return null
	return source.callv(args)


## Prints an answer the sheet already holds — a pick read once at the refresh —
## or stands the line down. A pick prints as one capital sentence; a line prints
## as the pass worded it.
func show_value(value: Variant) -> void:
	var line: String = text_of(value)
	text = line
	visible = not line.is_empty()


## The words one answer prints, holding the pick it carries.
func text_of(value: Variant) -> String:
	if value is Dictionary:
		pick = value
		return MapPlayPickProse.sentence_of(pick)
	pick = {}
	if value is String:
		return value
	return ""


## The rows this reading names, keyed the way the sheet's own rows key
## themselves, so a mark is one lookup and a row the pass would leave alone never
## looks busy (DR-20261122-03).
func keys() -> Dictionary:
	var marks: Variant = pick.get("keys", {})
	if marks is Dictionary:
		return marks
	return {}
