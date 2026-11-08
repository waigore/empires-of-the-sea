class_name HudLayout
extends RefCounted
## Two chrome geometries (REQ-P1-05). WIDE is the desktop atlas bar; COMPACT is
## the phone/tablet-portrait arrangement: a shorter cartouche, a smaller minimap,
## a tighter zoom pair and a shorter end-turn seal, all in points so every touch
## target keeps its physical size.
##
## Dossiers and the ledger are re-anchored by HudPanels.apply_compact.

const COMPACT_WIDTH: float = 1000.0
const COMPACT_HEIGHT: float = 560.0
## Below this width the stat chips drop to a second bar row instead of clipping.
const STACK_WIDTH: float = 840.0
const STACK_BAR_HEIGHT: float = 92.0
## Right edge of the cartouche's left rail (sound seal and estates seal sit here).
const LEFT_RAIL: float = 258.0

var compact: bool = false


static func is_compact(view: Vector2) -> bool:
	return view.x < COMPACT_WIDTH or view.y < COMPACT_HEIGHT


func apply(hud: GameHud) -> void:
	var view: Vector2 = hud.size
	if view.y < 1.0 or hud.top_bar == null:
		return
	compact = is_compact(view)
	_bar(hud, view)
	_minimap(hud)
	_zoom(hud)
	_end_turn(hud)
	_toasts(hud)
	hud.panels.apply_compact(compact, view)


func _bar(hud: GameHud, view: Vector2) -> void:
	var stack: bool = compact and view.x < STACK_WIDTH
	for chip: Control in hud.chips:
		var target: Control = hud.chip_row if stack else hud.top_row
		if chip.get_parent() != target:
			chip.reparent(target, false)
	hud.chip_row.visible = stack
	var height: float = GameHud.BAR_HEIGHT
	if stack:
		height = STACK_BAR_HEIGHT
	elif compact:
		height = GameHud.BAR_HEIGHT_COMPACT
	hud.top_bar.offset_bottom = height


func _minimap(hud: GameHud) -> void:
	var frame: Control = hud.minimap_frame
	if frame == null:
		return
	frame.offset_left = 10.0 if compact else 18.0
	frame.offset_top = -152.0 if compact else -196.0
	frame.offset_right = 178.0 if compact else 268.0
	frame.offset_bottom = -10.0 if compact else -18.0
	if hud._minimap != null:
		hud._minimap.custom_minimum_size = (
			Vector2(150, 120) if compact else Vector2(232, 160)
		)


func _zoom(hud: GameHud) -> void:
	var box: Control = hud.zoom_box
	if box == null:
		return
	box.offset_left = -62.0 if compact else -78.0
	box.offset_top = -186.0 if compact else -212.0
	box.offset_right = -10.0 if compact else -20.0
	box.offset_bottom = -92.0 if compact else -110.0
	var size := Vector2(52, 44) if compact else Vector2(58, 46)
	for child: Node in box.get_children():
		if child is Button:
			(child as Button).custom_minimum_size = size


func _end_turn(hud: GameHud) -> void:
	var wrap: Control = hud.end_turn_wrap
	if wrap == null:
		return
	wrap.offset_left = -176.0 if compact else -232.0
	wrap.offset_top = -84.0 if compact else -96.0
	wrap.offset_right = -10.0 if compact else -20.0
	wrap.offset_bottom = -10.0 if compact else -20.0


## Toasts sit under the cartouche. On a phone the left rail already holds the
## sound seal and the estates seal, so the column starts to their right instead
## of running full width and covering them.
func _toasts(hud: GameHud) -> void:
	var box: Control = hud._toast_box
	if box == null:
		return
	if compact:
		box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		box.offset_left = LEFT_RAIL
		box.offset_right = -16.0
		box.offset_top = 64.0
		box.offset_bottom = 64.0
		return
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -230.0
	box.offset_right = 230.0
	box.offset_top = 84.0
	box.offset_bottom = 84.0
