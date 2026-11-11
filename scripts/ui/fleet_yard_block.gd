class_name FleetYardBlock
extends VBoxContainer
## The fleet dossier's shipyard drawer: the toggle, the launch rows and the
## break-up rows with their confirm arm (wiki: ships-and-naval § Ship build
## economy, § Ship muster and the breaker's yard). Lifted out of FleetPanel so
## the dossier keeps the header, the status lines and the sections while this
## block owns only the yard (REQ-P3-01). It reads plain data and emits intents;
## FleetYard owns every rule (REQ-P3-02).

signal action_pressed(action: String)

## Breaking up a paid-for hull asks once: a second tap inside this window
## confirms and an expired arm does nothing (DR-20261109-01).
const ARM_SECONDS: float = 5.0

var _button: Button = null
var _scroll: ScrollContainer = null
var _box: VBoxContainer = null
var _timer: Timer = null
var _open: bool = false
var _armed_hull: String = ""
var _fleet: FleetState = null
var _is_player: bool = false
var _rows: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_button = UiRowBuilder.button("Shipyard", 36.0, 0.0)
	_button.visible = false
	_button.pressed.connect(func() -> void: set_open(not _open))
	add_child(_button)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 168)
	_scroll.visible = false
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_box)
	# The arm expires on its own; a freed dossier takes the timer with it.
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = ARM_SECONDS
	_timer.timeout.connect(_clear_arm)
	add_child(_timer)


## Opens or closes the drawer without rebuilding the dossier.
func set_open(open: bool) -> void:
	_open = open and _button.visible
	_apply_open()
	if _open:
		_fill()


func is_open() -> bool:
	return _open


## A fresh fleet: the yard closes unless it may stay, and the rows are redrawn.
func show_rows(
	fleet: FleetState, rows: Array[Dictionary], is_player: bool, keep_open: bool
) -> void:
	_fleet = fleet
	_is_player = is_player
	_rows = rows
	_button.visible = is_player and not rows.is_empty()
	_open = keep_open and _button.visible
	if not _open:
		_armed_hull = ""
	_apply_open()
	if _open:
		_fill()


## The capital slip: no squadron afloat, but the yard still lists what to launch.
func show_slip(rows: Array[Dictionary], is_player: bool) -> void:
	show_rows(null, rows, is_player, true)


## The break-up drawer takes the yard's place while a join is on offer, so the
## dossier never grows past a phone's sheet (REQ-P1-05).
func set_offer_join(offers_join: bool) -> void:
	_button.visible = _is_player and not _rows.is_empty() and not offers_join
	_open = _open and _button.visible
	_apply_open()


## First tap arms and relabels, the second confirms (DR-20261109-01).
func on_scrap_pressed(hull_id: String) -> void:
	if _armed_hull == hull_id:
		_clear_arm()
		action_pressed.emit("yard:scrap:%s" % hull_id)
		return
	_armed_hull = hull_id
	_fill()
	_timer.start()


func _apply_open() -> void:
	_button.text = "Close shipyard" if _open else "Shipyard"
	_scroll.visible = _open


func _fill() -> void:
	UiRowBuilder.clear(_box)
	_box.add_child(_caption("LAUNCH A HULL"))
	for row: Dictionary in _rows:
		_box.add_child(_build_row(row))
	if _fleet == null or not _is_player:
		return
	_box.add_child(_caption("BREAK UP A HULL"))
	for hull_id: String in _fleet.hulls:
		_box.add_child(_hull_row(hull_id))


func _caption(text: String) -> Label:
	var label := UiRowBuilder.line(11, Palette.TEXT_DIM)
	label.text = text
	return label


func _build_row(row: Dictionary) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	entry.add_child(top)
	var type_id: String = String(row["type_id"])
	top.add_child(UnitMedallion.of_ship(type_id, 30.0))
	var name := UiRowBuilder.line(13, Palette.TEXT)
	name.text = String(row["name"])
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(name)
	var ok: bool = bool(row["ok"])
	var launch := UiRowBuilder.button("Launch", 36.0, 0.0)
	launch.custom_minimum_size = Vector2(84, 40)
	launch.add_theme_font_size_override("font_size", 12)
	launch.disabled = not ok
	launch.tooltip_text = String(row["cost_text"]) if ok else String(row["reason"])
	launch.pressed.connect(func() -> void: action_pressed.emit("yard:build:%s" % type_id))
	top.add_child(launch)
	var detail := UiRowBuilder.line(10, Palette.TEXT_DIM)
	detail.text = String(row["cost_text"]) if ok else String(row["reason"])
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(detail)
	return entry


func _hull_row(hull_id: String) -> Control:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	entry.add_child(row)
	var type_id: String = _fleet.type_of(hull_id)
	row.add_child(UnitMedallion.of_ship(type_id, 30.0))
	var hull_name: String = ShipNames.of(_fleet, hull_id)
	var hull_type: String = ShipStats.display_name(type_id)
	var name := UiRowBuilder.line(13, Palette.TEXT)
	name.text = "%s — %s" % [hull_name, hull_type] if not hull_name.is_empty() else hull_type
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name)
	var armed: bool = _armed_hull == hull_id
	var scrap := UiRowBuilder.button("Confirm scrap" if armed else "Break up", 36.0, 0.0)
	scrap.custom_minimum_size = Vector2(100, 40)
	scrap.add_theme_font_size_override("font_size", 12)
	scrap.tooltip_text = (
		"Break up %s: one peasant returns; no refund." % hull_name
		if armed and not hull_name.is_empty()
		else ("One peasant returns; no refund." if armed else "Break up this hull")
	)
	scrap.pressed.connect(func() -> void: on_scrap_pressed(hull_id))
	row.add_child(scrap)
	# The hull's own combat numbers, so a breaking up is a reasoned choice.
	var stats := UiRowBuilder.line(10, Palette.TEXT_DIM)
	stats.text = NavalStrength.hull_line(type_id)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(stats)
	return entry


func _clear_arm() -> void:
	if _armed_hull.is_empty():
		return
	_armed_hull = ""
	_timer.stop()
	if _open:
		_fill()
