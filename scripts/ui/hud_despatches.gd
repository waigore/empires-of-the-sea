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
## Phone lane: one plate at a time, in a single tight line (a 411-point-tall
## screen has no room for a stack, and a stack would cover the sheet beneath it).
var _compact: bool = false
var _compact_queue: Array[Dictionary] = []
## Plates currently fading in the lane; the compact lane holds one.
var _live: int = 0


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
	var was_compact: bool = _compact
	_compact = compact
	# A lane that grew into atlas width tells its queued lines at once.
	if was_compact and not compact and not _compact_queue.is_empty():
		for held: Dictionary in _compact_queue:
			_hold_in_queue(String(held["text"]))
		_compact_queue.clear()
		if not _covered:
			set_covered(false)
	lane.add_theme_constant_override("separation", 4 if compact else 6)
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
		# Only the phone lane holds plates already up: a desktop lane sits under
		# nothing, and its stacked plates keep their old life.
		if _compact:
			_hold_live()
		return
	var pending: PackedStringArray = _queue
	_queue = PackedStringArray()
	_queue_narrated.clear()
	for held: String in pending:
		_raise(held)


## A sheet now covers the lane: the plates already up would sit under (or over)
## it, so they join the queue and print in order once the court is visible again.
func _hold_live() -> void:
	for child: Node in lane.get_children():
		var panel := child as PanelContainer
		if panel == null:
			continue
		var text: String = String(panel.get_meta("toast_text", ""))
		if not text.is_empty():
			_hold_in_queue(text)
		# The plate's tween is still running; a cancel mark keeps its callback
		# from counting down a plate that is no longer in the lane.
		panel.set_meta("toast_cancelled", true)
		panel.queue_free()
	_live = 0
	for held: Dictionary in _compact_queue:
		_hold_in_queue(String(held["text"]))
	_compact_queue.clear()


func _hold_in_queue(text: String) -> void:
	if _queue.size() >= TOAST_QUEUE_CAP:
		_make_room()
	_queue.append(text)
	_queue_narrated.append(false)


## Lines the court has not been told yet, oldest first.
func waiting() -> PackedStringArray:
	var waiting_now: PackedStringArray = _queue.duplicate()
	for held: Dictionary in _compact_queue:
		waiting_now.append(String(held["text"]))
	return waiting_now


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
	# A phone lane tells one line at a time: the rest wait their turn, so the
	# newest news never stacks over the sheet the player is reading.
	if _compact and _live > 0:
		_compact_queue.append({"text": text, "icon": icon_name})
		return
	var panel := PanelContainer.new()
	var accent: Color = Palette.GOLD if icon_name.is_empty() else Palette.CRIMSON
	panel.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.95),
			accent,
			1,
			3,
			Vector4(12, 3, 12, 3) if _compact else Vector4(18, 8, 18, 8)
		)
	)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("toast_text", text)
	panel.set_meta("toast_icon", icon_name)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = _compact
	var font_size: int = 15 if icon_name.is_empty() else 16
	if _compact:
		font_size = 13 if icon_name.is_empty() else 14
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	if icon_name.is_empty():
		panel.add_child(label)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		var medallion := TextureRect.new()
		medallion.texture = ChromeIcons.texture(icon_name)
		var medallion_size: float = 20.0 if _compact else 26.0
		medallion.custom_minimum_size = Vector2(medallion_size, medallion_size)
		medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		medallion.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(medallion)
		row.add_child(label)
		panel.add_child(row)
	panel.modulate.a = 0.0
	lane.add_child(panel)
	_live += 1

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.8 if icon_name.is_empty() else 4.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: _plate_done(panel))


## A plate finished: the compact lane prints the next held line, unless a sheet
## or battle plate still covers the court.
func _plate_done(panel: PanelContainer) -> void:
	if not is_instance_valid(panel) or panel.has_meta("toast_cancelled"):
		return
	if panel.is_queued_for_deletion():
		return
	panel.queue_free()
	_live = maxi(_live - 1, 0)
	if _compact and not _covered and _live == 0:
		_next_compact.call_deferred()


func _next_compact() -> void:
	if not _compact or _covered or _live > 0 or _compact_queue.is_empty():
		return
	var next: Dictionary = _compact_queue.pop_front()
	_raise(String(next["text"]), String(next["icon"]))
