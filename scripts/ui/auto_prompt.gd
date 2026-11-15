class_name AutoPrompt
extends Control
## The Auto seat's confirmation plate (wiki: auto-mode § Arming and disarming):
## a dim over the chart and one centred plate that says what the seat change will
## do, with the one confirming verb and CANCEL. It owns no state — AutoBar asks
## and answers (REQ-P3-01).

## What the plate is asking for: the two seat changes Auto has.
const ARM: String = "arm"
const DISARM: String = "disarm"

signal confirmed(kind: String)
signal cancelled

const TOUCH_HEIGHT: float = 44.0

var _title: Label = null
var _body: Label = null
var _confirm: Button = null
var _pending: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# Above the despatch lane (z 33) and the battle plates (z 35), below the
	# campaign-end plate (z 40): a confirmation answers the court, not the age.
	z_index = 38
	_build()


## Raises the plate for one seat change.
func ask(kind: String) -> void:
	_pending = kind
	var arming: bool = kind == ARM
	_title.text = "AUTO"
	_body.text = (
		"The AI takes your seat after this turn and plays your court until you "
		+ "ask for it back. You may pan the chart and read your ledgers, but no "
		+ "order you press will land."
		if arming
		else
		"The AI gives your seat back when this turn ends. You take the court "
		+ "again on the following turn."
	)
	_confirm.text = "ENABLE" if arming else "DISABLE"
	visible = true


func is_open() -> bool:
	return visible


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.02, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# The house centred column (safe on a phone, scrolls when short); the plate
	# sits inside it rather than being anchored at the middle by hand.
	var column: VBoxContainer = MenuFrame.column(self, 380.0)
	var frame := MenuFrame.panel()
	column.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)

	_title = MenuFrame.title("AUTO", 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_body = MenuFrame.caption("")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_body)

	_confirm = MenuFrame.action_button("ENABLE", TOUCH_HEIGHT)
	_confirm.pressed.connect(_on_confirm)
	box.add_child(_confirm)

	var cancel := MenuFrame.action_button("CANCEL", TOUCH_HEIGHT)
	cancel.pressed.connect(_on_cancel)
	box.add_child(cancel)


func _on_confirm() -> void:
	visible = false
	confirmed.emit(_pending)


func _on_cancel() -> void:
	visible = false
	_pending = ""
	cancelled.emit()
