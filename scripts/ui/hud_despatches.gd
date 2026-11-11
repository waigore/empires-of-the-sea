class_name HudDespatches
extends RefCounted
## The court's transient news: the toast lane above the chart and the despatches
## a battle plate holds back until it closes (REQ-P5-05, REQ-P5-06). GameHud only
## forwards; the column, the hold queue, its cap and the lane geometry live here
## so the plate that covers the court is the only thing that has to ask
## (REQ-P3-01, REQ-P3-02).

## A long turn cannot bury the court in plates: keep the newest despatches, the
## ones the turn's latest orders produced.
const QUEUE_CAP: int = 6

## The toast column HudChrome mounts; HudLayout re-anchors it per viewport.
var box: VBoxContainer = null

## News raised while a battle plate covered the court, in the order it arrived.
var _held: PackedStringArray = PackedStringArray()


## Mounts the column. Toasts are the moment's acknowledgement (REQ-P5-05) and
## stay legible over the soft Gazette plate that covers this lane at a turn's open.
func build(host: Control) -> void:
	box = VBoxContainer.new()
	box.z_index = 33
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -230.0
	box.offset_right = 230.0
	box.offset_top = 84.0
	box.offset_bottom = 84.0
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(box)


## A despatch. `plate_up` means a battle plate covers the whole court for seconds
## at a time: a line raised under it is neither readable nor still alive when it
## closes, so the news waits its turn (REQ-P5-06, REQ-P2-03).
func post(text: String, icon_name: String, plate_up: bool) -> void:
	if box == null:
		return
	if plate_up:
		if _held.size() >= QUEUE_CAP:
			_held.remove_at(0)
		_held.append(text)
		return
	_raise(text, icon_name)


## News a plate held back, oldest first; the caller may read it while it clears.
func held() -> PackedStringArray:
	return _held


## The last plate of the turn closed: the held news reaches the court in its own
## order, with no medallion — the hold carries lines, not their icons.
func release() -> void:
	var pending: PackedStringArray = _held
	_held = PackedStringArray()
	for line: String in pending:
		_raise(line, "")


## A soft plate covers this lane for a moment: park the column under its sheet
## and put it back on the cartouche's line afterwards (REQ-P5-05).
func set_lane(top: float) -> void:
	if box == null or is_equal_approx(box.offset_top, top):
		return
	box.offset_top = top
	box.offset_bottom = top


## One plate: a plain line, or a medallion and a line when the news carries a
## loss the court must not mistake for the turn's chatter (REQ-P5-05).
func _raise(text: String, icon_name: String) -> void:
	if box == null:
		return
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
		panel.add_child(_medallion_row(icon_name, label))
	panel.modulate.a = 0.0
	box.add_child(panel)

	var tween := box.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.8 if icon_name.is_empty() else 4.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


## The medallion sits in a row with its line; it holds longer than a plain toast
## so a loss is read rather than skimmed (REQ-P5-05).
func _medallion_row(icon_name: String, label: Label) -> HBoxContainer:
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
	return row
