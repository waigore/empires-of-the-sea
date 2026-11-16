class_name FleetCombineBlock
extends VBoxContainer
## The fleet dossier's combine drawer: every other squadron of the crown in the
## same station with the one tap that folds this one into her (wiki:
## ships-and-naval § Ship instances; DR-20261116-13). It reads the rules' own
## rows and emits intents; FleetCombine decides what may join (REQ-P3-02,
## REQ-P3-03).

signal action_pressed(action: String)

var _button: Button = null
var _scroll: ScrollContainer = null
var _box: VBoxContainer = null
var _note: Label = null
var _open: bool = false
var _rows: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_note = UiRowBuilder.line(11, Palette.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	add_child(_note)
	_button = UiRowBuilder.button("Combine the squadron", 36.0, 0.0)
	_button.visible = false
	_button.pressed.connect(func() -> void: set_open(not _open))
	add_child(_button)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 132)
	_scroll.visible = false
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_box)


## Opens or closes the drawer without rebuilding the dossier.
func set_open(open: bool) -> void:
	_open = open and _button.visible
	_apply_open()
	if _open:
		_fill()


func is_open() -> bool:
	return _open


## A fresh squadron: the drawer closes unless it may stay, and the rows redraw.
## A squadron that may join nothing prints the gate's own reason instead of a
## press, so a phone never has to hover for the rule (REQ-P1-07).
func show_rows(
	model: MapModel,
	roster: Array[FleetState],
	fleet: FleetState,
	is_player: bool,
	keep_open: bool
) -> void:
	_rows = []
	if is_player:
		_rows = FleetCombine.rows(model, roster, fleet)
	var joinable: int = 0
	for row: Dictionary in _rows:
		if bool(row["ok"]):
			joinable += 1
	# A squadron standing alone has nothing to combine and nothing to explain.
	var offered: bool = is_player and not _rows.is_empty()
	_button.visible = offered and joinable > 0
	_note.visible = offered
	_note.text = FleetCombine.NOTE if joinable > 0 else _first_reason()
	_open = keep_open and _button.visible
	_apply_open()
	if _open:
		_fill()


func _apply_open() -> void:
	_button.text = "Close combine" if _open else "Combine the squadron"
	_scroll.visible = _open


func _first_reason() -> String:
	for row: Dictionary in _rows:
		var reason: String = String(row["reason"])
		if not reason.is_empty():
			return reason
	return ""


func _fill() -> void:
	UiRowBuilder.clear(_box)
	for row: Dictionary in _rows:
		_box.add_child(_build_row(row))


## One squadron: her flagship's medallion, the hull count she brings and the one
## tap that folds this one into her. A squadron the rules hold back keeps its row
## and prints why.
func _build_row(row: Dictionary) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	entry.add_child(top)
	var type_id: String = String(row["type"])
	top.add_child(UnitMedallion.of_ship(type_id, 30.0))
	var into: String = String(row["name"])
	var hulls: int = int(row["hulls"])
	var label := UiRowBuilder.line(13, Palette.TEXT)
	label.text = "%s — %d hull%s" % [into, hulls, "" if hulls == 1 else "s"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(label)
	var ok: bool = bool(row["ok"])
	var press := UiRowBuilder.button("Combine", 36.0, 0.0)
	press.custom_minimum_size = Vector2(84, 40)
	press.add_theme_font_size_override("font_size", 12)
	press.disabled = not ok
	press.tooltip_text = "Fold this squadron into her" if ok else String(row["reason"])
	var target_id: int = int(row["fleet"])
	press.pressed.connect(func() -> void: action_pressed.emit("combine:%d" % target_id))
	top.add_child(press)
	if not ok:
		var why := UiRowBuilder.line(10, Palette.TEXT_DIM)
		why.text = String(row["reason"])
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(why)
	return entry
