class_name PanelDock
extends RefCounted
## Left/right dock side for selection dossiers. Persists like AudioMix.

enum Side { RIGHT, LEFT }

const SETTINGS_PATH := "user://ui.cfg"
const WIDTH: float = GameHud.PANEL_WIDTH
const MARGIN: float = GameHud.PANEL_MARGIN
const TOP: float = 84.0
const BOTTOM: float = -104.0
## Meta key holding the running slide tween for one dossier wrapper.
const SLIDE_KEY: String = "dock_slide"

var side: int = Side.RIGHT
## Compact (phone) sheets are narrower and reach further down the screen.
var width: float = WIDTH
var top: float = TOP
var bottom: float = BOTTOM


func configure(p_width: float, p_top: float, p_bottom: float) -> void:
	width = maxf(p_width, 240.0)
	top = p_top
	bottom = p_bottom


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
	wrap.offset_top = top
	wrap.offset_bottom = bottom
	place_hidden(wrap)


func place_hidden(wrap: Control) -> void:
	if is_left():
		wrap.offset_left = MARGIN - width
		wrap.offset_right = MARGIN
	else:
		wrap.offset_left = -MARGIN
		wrap.offset_right = width - MARGIN


func place_shown(wrap: Control) -> void:
	if is_left():
		wrap.offset_left = MARGIN
		wrap.offset_right = MARGIN + width
	else:
		wrap.offset_left = -(width + MARGIN)
		wrap.offset_right = -MARGIN


## Re-anchors a wrap for the current geometry without animating it.
func relayout(wrap: Control, shown: bool) -> void:
	prepare_wrap(wrap)
	if shown:
		place_shown(wrap)
		wrap.visible = true


func slide_in(host: Node, wrap: Control) -> void:
	stop_slide(wrap)
	prepare_wrap(wrap)
	wrap.visible = true
	wrap.modulate.a = 0.0
	var tween := host.create_tween().set_parallel(true)
	wrap.set_meta(SLIDE_KEY, tween)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if is_left():
		tween.tween_property(wrap, "offset_left", MARGIN, 0.34)
		tween.tween_property(wrap, "offset_right", MARGIN + width, 0.34)
	else:
		tween.tween_property(wrap, "offset_left", -(width + MARGIN), 0.34)
		tween.tween_property(wrap, "offset_right", -MARGIN, 0.34)
	tween.tween_property(wrap, "modulate:a", 1.0, 0.22)


func slide_out(host: Node, wrap: Control, on_done: Callable) -> void:
	stop_slide(wrap)
	var tween := host.create_tween().set_parallel(true)
	wrap.set_meta(SLIDE_KEY, tween)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if is_left():
		tween.tween_property(wrap, "offset_left", MARGIN - width, 0.26)
		tween.tween_property(wrap, "offset_right", MARGIN, 0.26)
	else:
		tween.tween_property(wrap, "offset_left", -MARGIN, 0.26)
		tween.tween_property(wrap, "offset_right", width - MARGIN, 0.26)
	tween.tween_property(wrap, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(on_done)


## A hide followed by a show in the same frame must not let the old slide-out
## callback park the panel hidden while its open flag says visible. Static: a
## drag also has to take a plate off its slide without owning the dock.
static func stop_slide(wrap: Control) -> void:
	if not wrap.has_meta(SLIDE_KEY):
		return
	var tween: Tween = wrap.get_meta(SLIDE_KEY) as Tween
	if tween != null and tween.is_valid():
		tween.kill()
