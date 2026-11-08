class_name PanelDock
extends RefCounted
## Left/right dock side for selection dossiers. Persists like AudioMix.

enum Side { RIGHT, LEFT }

const SETTINGS_PATH := "user://ui.cfg"
const WIDTH: float = GameHud.PANEL_WIDTH
const MARGIN: float = GameHud.PANEL_MARGIN
const TOP: float = 84.0
const BOTTOM: float = -104.0

var side: int = Side.RIGHT


func set_side(value: int) -> int:
	side = Side.LEFT if value == Side.LEFT else Side.RIGHT
	return side


func toggle() -> int:
	side = Side.LEFT if side == Side.RIGHT else Side.RIGHT
	return side


func is_left() -> bool:
	return side == Side.LEFT


func save(path: String = SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	config.set_value("ui", "panel_dock", "left" if is_left() else "right")
	return config.save(path) == OK


func load_from(path: String = SETTINGS_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	var raw: String = str(config.get_value("ui", "panel_dock", "right")).to_lower()
	side = Side.LEFT if raw == "left" else Side.RIGHT
	return true


func prepare_wrap(wrap: Control) -> void:
	wrap.set_anchors_and_offsets_preset(
		Control.PRESET_LEFT_WIDE if is_left() else Control.PRESET_RIGHT_WIDE
	)
	wrap.offset_top = TOP
	wrap.offset_bottom = BOTTOM
	place_hidden(wrap)


func place_hidden(wrap: Control) -> void:
	if is_left():
		wrap.offset_left = MARGIN - WIDTH
		wrap.offset_right = MARGIN
	else:
		wrap.offset_left = -MARGIN
		wrap.offset_right = WIDTH - MARGIN


func place_shown(wrap: Control) -> void:
	if is_left():
		wrap.offset_left = MARGIN
		wrap.offset_right = MARGIN + WIDTH
	else:
		wrap.offset_left = -(WIDTH + MARGIN)
		wrap.offset_right = -MARGIN


func slide_in(host: Node, wrap: Control) -> void:
	prepare_wrap(wrap)
	wrap.visible = true
	wrap.modulate.a = 0.0
	var tween := host.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_left():
		tween.tween_property(wrap, "offset_left", MARGIN, 0.34)
		tween.tween_property(wrap, "offset_right", MARGIN + WIDTH, 0.34)
	else:
		tween.tween_property(wrap, "offset_left", -(WIDTH + MARGIN), 0.34)
		tween.tween_property(wrap, "offset_right", -MARGIN, 0.34)
	tween.tween_property(wrap, "modulate:a", 1.0, 0.22)


func slide_out(host: Node, wrap: Control, on_done: Callable) -> void:
	var tween := host.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if is_left():
		tween.tween_property(wrap, "offset_left", MARGIN - WIDTH, 0.26)
		tween.tween_property(wrap, "offset_right", MARGIN, 0.26)
	else:
		tween.tween_property(wrap, "offset_left", -MARGIN, 0.26)
		tween.tween_property(wrap, "offset_right", WIDTH - MARGIN, 0.26)
	tween.tween_property(wrap, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(on_done)
