class_name HudStatChipMotion
extends RefCounted
## The cartouche plaques' motion: treasury count-up and the income flash that
## lifts off the plaque. The binder owns the labels; this owns the tweens so a
## suite re-seat never leaves a freed lambda writing mid-reset (REQ-P3-01,
## docs/testing.md § Speed rules).

var _host: Control = null
var _treasury_tween: Tween = null
var _flash_tween: Tween = null
var _flash_label: Label = null


## The Control that births tweens (the HUD root). Bound once the plaques exist.
func bind(host: Control) -> void:
	_host = host


## Count the purse from `from` to `to` on `label`, or land at once when animate
## is off or no host is bound.
func count_treasury(label: Label, from: int, to: int, animate: bool) -> void:
	kill_treasury()
	if label == null:
		return
	if not animate or _host == null:
		label.text = TextFormat.thousands(to)
		return
	_treasury_tween = _host.create_tween()
	_treasury_tween.tween_method(
		func(step: float) -> void:
			if is_instance_valid(label):
				label.text = TextFormat.thousands(int(round(step))),
		float(from), float(to), 0.6
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The turn's coin movement lifts off the treasury plaque, so a gain reads as an
## event and not a silent repaint (REQ-P5-05).
func flash_income(amount: int, treasury_chip: Button) -> void:
	if _host == null or treasury_chip == null:
		return
	kill_flash()
	_flash_label = Label.new()
	_flash_label.text = "+%s" % TextFormat.thousands(amount)
	_flash_label.add_theme_font_size_override("font_size", 18)
	_flash_label.add_theme_color_override("font_color", Palette.GOLD_PALE)
	_flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(_flash_label)
	_flash_label.position = treasury_chip.get_global_rect().position + Vector2(0, 4)
	_flash_tween = _host.create_tween().set_parallel(true)
	_flash_tween.tween_property(_flash_label, "position:y", _flash_label.position.y - 46.0, 1.1)
	_flash_tween.tween_property(_flash_label, "modulate:a", 0.0, 1.1).set_delay(0.25)
	_flash_tween.chain().tween_callback(_flash_label.queue_free)


## Suite re-seat and a fresh count-up must not leave a prior plaque tween
## writing into a label mid-reset.
func clear_all() -> void:
	kill_treasury()
	kill_flash()


func kill_treasury() -> void:
	if _treasury_tween != null:
		_treasury_tween.kill()
		_treasury_tween = null


func kill_flash() -> void:
	if _flash_tween != null:
		_flash_tween.kill()
		_flash_tween = null
	if is_instance_valid(_flash_label):
		_flash_label.queue_free()
	_flash_label = null
