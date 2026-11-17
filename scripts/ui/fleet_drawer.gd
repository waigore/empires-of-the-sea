class_name FleetDrawer
extends VBoxContainer
## One drawer of the fleet dossier: the toggle, the scrolled list and the
## one-tap rows a squadron's orders file through. The split, combine and
## shipyard drawers differ only in the rows they read, the words their toggle
## wears and what their rows spend; the toggle, the open state, the rule line,
## the row shell and the gate's own reason are written once here, so a repaint
## never closes a list under a finger and a phone never has to hover for a
## refusal (REQ-P1-07, REQ-P3-01, REQ-P3-02).
##
## Reads plain data and emits intents; the rules modules decide what may run
## (REQ-P3-02, REQ-P3-03). A drawer never writes state of its own.

signal action_pressed(action: String)

## The words the toggle wears: shut and open, in the drawer's own domain.
var toggle_text: String = ""
var close_text: String = ""
## The list's share of the sheet: a phone reads a few rows before scrolling.
var drawer_height: float = 132.0
## The gap between the drawer's rows.
var row_separation: int = 6
## Drawers that print a rule above the toggle opt in.
var has_note: bool = false

## The drawer's toggle, list and rule line. Kept reachable because the dossier
## and its suites read a drawer through them (REQ-P5-03).
var _button: Button = null
var _scroll: ScrollContainer = null
var _box: VBoxContainer = null
## The rule a drawer prints above its toggle; null on a drawer with none.
var _note: Label = null
var _open: bool = false
var _rows: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	if has_note:
		_note = UiRowBuilder.line(11, Palette.TEXT_DIM)
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.visible = false
		add_child(_note)
	_button = UiRowBuilder.button(toggle_text, 36.0, 0.0)
	_button.visible = false
	_button.pressed.connect(func() -> void: set_open(not _open))
	add_child(_button)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, drawer_height)
	_scroll.visible = false
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", row_separation)
	_scroll.add_child(_box)


## Opens or closes the drawer without rebuilding the dossier.
func set_open(open: bool) -> void:
	_open = open and _button.visible
	_apply_open()
	if _open:
		_fill()


func is_open() -> bool:
	return _open


## The drawer's one gate: a crown's rows, the presses the rules allow, the rule
## printed on the sheet when one takes and the gate's own reason when none does
## (REQ-P1-07). `offered` is the drawer's own domain gate — a squadron of one
## hull offers no split, a lone squadron nothing to combine. A drawer whose rows
## explain rather than press — the yard's refused launches — passes
## `needs_press` false and opens on its rows alone.
func offer(
	rows: Array[Dictionary], is_player: bool, offered: bool, note: String,
	keep_open: bool, needs_press: bool = true
) -> void:
	var allowed: bool = not needs_press
	for row: Dictionary in rows:
		if not needs_press or bool(row.get("ok", false)):
			allowed = true
			break
	# A rival's squadron reads nothing and offers nothing.
	if is_player:
		_rows = rows
	else:
		_rows.clear()
	var shown: bool = is_player and offered
	_button.visible = shown and allowed
	if _note != null:
		_note.visible = shown
		_note.text = note if allowed else _first_reason()
	_open = keep_open and _button.visible
	_apply_open()
	if _open:
		_fill()


## The drawer's toggle and list follow the open state; the words are the
## drawer's own.
func _apply_open() -> void:
	_button.text = close_text if _open else toggle_text
	_scroll.visible = _open


## The first gate's reason a held-back row prints, so the rule reaches the sheet
## even when no press takes.
func _first_reason() -> String:
	for row: Dictionary in _rows:
		var reason: String = String(row.get("reason", ""))
		if not reason.is_empty():
			return reason
	return ""


## Redraws the list from the rows the rules handed over.
func _fill() -> void:
	UiRowBuilder.clear(_box)
	for row: Dictionary in _rows:
		_box.add_child(_build_row(row))


## One row of the list: the medallion, the reading, the one press and the gate's
## own reason under a press it holds back, so every drawer's rows read alike
## (REQ-P1-07). A drawer hands over the words its own domain prints.
func _build_row(row: Dictionary) -> Control:
	var shell: Dictionary = _row_head(String(row.get("type", "")))
	var entry: VBoxContainer = shell["entry"]
	var top: HBoxContainer = shell["top"]
	var ok: bool = bool(row.get("ok", false))
	_row_reading(top, String(row.get("name", "")))
	var press := _row_press(
		top,
		String(row.get("label", "Order")),
		ok,
		String(row.get("tip", "")),
		String(row.get("action", "")),
		float(row.get("width", 84.0))
	)
	var meta: Dictionary = row.get("meta", {})
	for key: String in meta:
		press.set_meta(key, meta[key])
	var detail: String = String(row.get("detail", ""))
	if not detail.is_empty():
		_row_detail(entry, detail)
	else:
		_held_reason(entry, ok, String(row.get("reason", "")))
	return entry


# --- the parts every drawer's row reads alike -------------------------------


## A row's head: the medallion and the line beside it.
func _row_head(type_id: String) -> Dictionary:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	entry.add_child(top)
	top.add_child(UnitMedallion.of_ship(type_id, 30.0))
	return {"entry": entry, "top": top}


## The row's reading: one wrapped line that takes the room the press leaves.
func _row_reading(top: HBoxContainer, text: String) -> Label:
	var label := UiRowBuilder.line(13, Palette.TEXT)
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(label)
	return label


## The row's one press, gated by the rules: the tooltip names the order or the
## refusal, so the rule never hides in a hover a phone cannot show (REQ-P1-07).
func _row_press(
	top: HBoxContainer, label: String, ok: bool, tip: String, action: String,
	width: float = 84.0
) -> Button:
	var press := UiRowBuilder.button(label, 36.0, 0.0)
	press.custom_minimum_size = Vector2(width, 40)
	press.add_theme_font_size_override("font_size", 12)
	press.disabled = not ok
	press.tooltip_text = tip
	# A press that owns its own tap (the yard's break-up arm) hands no intent.
	if not action.is_empty():
		press.pressed.connect(func() -> void: action_pressed.emit(action))
	top.add_child(press)
	return press


## The line under a row: the price, the wait or the hull's own numbers.
func _row_detail(entry: VBoxContainer, text: String) -> Label:
	var detail := UiRowBuilder.line(10, Palette.TEXT_DIM)
	detail.text = text
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(detail)
	return detail


## The gate's own reason under a held-back press, so the rule is read on the
## sheet rather than in a hover (REQ-P1-07).
func _held_reason(entry: VBoxContainer, ok: bool, text: String) -> Label:
	if ok:
		return null
	return _row_detail(entry, text)
