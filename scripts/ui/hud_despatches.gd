class_name HudDespatches
extends Control
## The court's despatch lane: toast plates (REQ-P5-05) and the order they print
## in. A battle plate covers the court for seconds at a time, so news raised
## under it waits and prints once the last plate of the turn closes
## (REQ-P5-06).
##
## One module owns the lane: HudChrome mounts it, HudLayout fits it, the Gazette
## asks it to clear the masthead, and the HUD root only forwards news. That
## keeps the lane's geometry, queue and plate construction together instead of
## a mutable node field three screens poke (REQ-P3-01, REQ-P3-02).

## News kept while a plate plays. The battle plate has already told its own
## despatch, so that line is the one the court can spare; the crown's own news
## (a seat lost, a court moved, a crown fallen) is what must survive the cap
## (REQ-P5-06).
const TOAST_QUEUE_CAP: int = 6
## Suites written against the first board still say QUEUE_CAP.
const QUEUE_CAP: int = TOAST_QUEUE_CAP

## The column the plates stack in. Presentation only; readable so the suites
## that check what the court was told can count it.
var lane: VBoxContainer = null
## The same column, under the name the first board published.
var box: VBoxContainer:
	get:
		return lane

## Top the HUD layout assigned the lane; a plate's push is undone back to it.
var _resting_top: float = 0.0
var _covered: bool = false
var _queue: PackedStringArray = PackedStringArray()
## One flag per queued line: true when the open plate narrated it too, so the
## cap drops that line before the court's own news.
var _queue_narrated: Array[bool] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Toasts are the moment's acknowledgement (REQ-P5-05) and stay legible over
	# the soft Gazette plate that covers this lane at a turn's open.
	z_index = 33
	lane = VBoxContainer.new()
	lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.add_theme_constant_override("separation", 6)
	add_child(lane)


## Chrome geometry follows the viewport: the atlas lane is a centred column
## under the cartouche; a phone's starts right of the left rail (sound, estates
## and lens seals) instead of running across them (REQ-P1-05).
func fit(compact: bool, bar_bottom: float, left_rail: float) -> void:
	if compact:
		lane.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		lane.offset_left = left_rail
		lane.offset_right = -16.0
		_resting_top = bar_bottom + 6.0
	else:
		lane.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		lane.offset_left = -230.0
		lane.offset_right = 230.0
		_resting_top = bar_bottom + 16.0
	clear_plate()


## A plate covers the masthead (the Gazette): stack the news under its foot.
func push_below(top: float) -> void:
	_set_top(maxf(top, _resting_top))


## The plate stepped aside: the lane returns to the top its layout assigned.
func clear_plate() -> void:
	_set_top(_resting_top)


## Top the layout gave the lane, before any plate pushed it.
func resting_top() -> float:
	return _resting_top


func lane_top() -> float:
	return lane.offset_top


## A battle plate is up: hold the news until the last plate of the turn closes,
## or it would print unreadable behind the plate and expire unseen.
func set_covered(covered: bool) -> void:
	_covered = covered
	if _covered:
		return
	var pending: PackedStringArray = _queue
	_queue = PackedStringArray()
	_queue_narrated.clear()
	for held: String in pending:
		_raise(held)


## Lines the court has not been told yet, oldest first.
func waiting() -> PackedStringArray:
	return _queue.duplicate()


## The first board's name for waiting().
func held() -> PackedStringArray:
	return waiting()


## A despatch toast. `icon_name` raises the plate with a medallion (an
## auto-resolved siege's silenced battery) and holds it longer, so the loss is
## read and not mistaken for the turn's chatter (REQ-P5-05).
func toast(text: String, icon_name: String = "") -> void:
	_hold_or_raise(text, icon_name, false)


## A despatch the open plate has already told (a Quick Battle's own outcome):
## held like any other line, but the first the cap spends when the court's own
## news needs the room (REQ-P5-06).
func toast_plate_line(text: String, icon_name: String = "") -> void:
	_hold_or_raise(text, icon_name, true)


func _hold_or_raise(text: String, icon_name: String, narrated: bool) -> void:
	if _covered:
		if _queue.size() >= TOAST_QUEUE_CAP:
			_make_room()
		_queue.append(text)
		_queue_narrated.append(narrated)
		return
	_raise(text, icon_name)


## One slot for the newest line: the plate's own narration goes first, and only
## a queue of nothing but the court's news drops its oldest line.
func _make_room() -> void:
	for index in _queue_narrated.size():
		if _queue_narrated[index]:
			_queue.remove_at(index)
			_queue_narrated.remove_at(index)
			return
	_queue.remove_at(0)
	_queue_narrated.remove_at(0)


func _set_top(top: float) -> void:
	lane.offset_top = top
	lane.offset_bottom = top


func _raise(text: String, icon_name: String = "") -> void:
	var panel := PanelContainer.new()
	var accent: Color = Palette.GOLD if icon_name.is_empty() else Palette.CRIMSON
	panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(Color(0.10, 0.08, 0.06, 0.95), accent, 1, 3, Vector4(18, 8, 18, 8))
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15 if icon_name.is_empty() else 16)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	if icon_name.is_empty():
		panel.add_child(label)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var medallion := TextureRect.new()
		medallion.texture = ChromeIcons.texture(icon_name)
		medallion.custom_minimum_size = Vector2(26.0, 26.0)
		medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(medallion)
		row.add_child(label)
		panel.add_child(row)
	panel.modulate.a = 0.0
	lane.add_child(panel)

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.8 if icon_name.is_empty() else 4.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
