class_name PlaytestCaptureOverlay
extends Control
## The capture mode's chrome (issue #1393): a compact plaque that toggles the
## mode, the shot/record seals while it is on, and the comment sheet every
## finished capture opens. Presentation only — PlaytestCapture owns the files
## and the session metadata (REQ-P3-01).

signal toggle_pressed
signal screenshot_pressed
signal record_pressed
signal comment_submitted(text: String)
signal comment_skipped

const BAR_WIDTH: float = 360.0
const BAR_TOP: float = 72.0
const PROMPT_WIDTH: float = 560.0
const PROMPT_HEIGHT: float = 300.0

var toggle_button: Button = null
var shot_button: Button = null
var record_button: Button = null
var save_button: Button = null
var skip_button: Button = null
var status_label: Label = null
var comment_edit: TextEdit = null

var _bar: PanelContainer = null
var _prompt: PanelContainer = null
var _prompt_title: Label = null
var _mode_on: bool = false
var _recording: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_mode(false)


func _build() -> void:
	_bar = PanelContainer.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.92), Palette.GOLD_DIM, 1, 3, Vector4(10, 6, 10, 6)
		)
	)
	_bar.anchor_left = 1.0
	_bar.anchor_right = 1.0
	_bar.offset_left = -BAR_WIDTH - 16.0
	_bar.offset_right = -16.0
	_bar.offset_top = BAR_TOP
	_bar.offset_bottom = BAR_TOP + 44.0
	add_child(_bar)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	toggle_button = _button("Capture: off")
	toggle_button.pressed.connect(func() -> void: toggle_pressed.emit())
	row.add_child(toggle_button)
	shot_button = _button("Shot")
	shot_button.pressed.connect(func() -> void: screenshot_pressed.emit())
	row.add_child(shot_button)
	record_button = _button("Record")
	record_button.pressed.connect(func() -> void: record_pressed.emit())
	row.add_child(record_button)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	status_label.text = ""
	row.add_child(status_label)
	_build_prompt()


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.name = "CommentPrompt"
	_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_prompt.add_theme_stylebox_override(
		"panel",
		UiTheme.box(
			Color(0.10, 0.08, 0.06, 0.97), Palette.GOLD, 1, 4, Vector4(16, 12, 16, 12)
		)
	)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.offset_left = -PROMPT_WIDTH * 0.5
	_prompt.offset_right = PROMPT_WIDTH * 0.5
	_prompt.offset_top = -PROMPT_HEIGHT * 0.5
	_prompt.offset_bottom = PROMPT_HEIGHT * 0.5
	add_child(_prompt)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_prompt.add_child(col)
	_prompt_title = Label.new()
	_prompt_title.add_theme_font_size_override("font_size", 18)
	_prompt_title.add_theme_color_override("font_color", Palette.GOLD_PALE)
	col.add_child(_prompt_title)
	comment_edit = TextEdit.new()
	comment_edit.custom_minimum_size = Vector2(0, 150)
	comment_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	comment_edit.placeholder_text = "What did you see?"
	col.add_child(comment_edit)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	col.add_child(actions)
	skip_button = _button("Skip")
	skip_button.pressed.connect(func() -> void: comment_skipped.emit())
	actions.add_child(skip_button)
	save_button = _button("Save comment")
	save_button.pressed.connect(_submit)
	actions.add_child(save_button)
	_prompt.visible = false


func _button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 32)
	return button


func _submit() -> void:
	var text: String = comment_edit.text
	comment_edit.text = ""
	comment_submitted.emit(text)


## Mode off keeps only the toggle plaque; the shot/record seals and the status
## line appear while the mode is on, so the chart stays clean when it is off.
func set_mode(on: bool) -> void:
	_mode_on = on
	toggle_button.text = "Capture: on" if on else "Capture: off"
	shot_button.visible = on
	record_button.visible = on
	status_label.visible = on
	if not on:
		close_prompt()


func set_recording(on: bool) -> void:
	_recording = on
	record_button.text = "Stop" if on else "Record"


func set_status(text: String) -> void:
	status_label.text = text


func prompt_comment(kind: String) -> void:
	_prompt_title.text = "Comment on this %s" % (
		"video" if kind == "video" else "screenshot"
	)
	comment_edit.text = ""
	_prompt.visible = true
	comment_edit.grab_focus()


func close_prompt() -> void:
	_prompt.visible = false
	comment_edit.text = ""


func is_prompting() -> bool:
	return _prompt.visible


func is_mode_on() -> bool:
	return _mode_on


func is_recording() -> bool:
	return _recording


func status_text() -> String:
	return status_label.text
