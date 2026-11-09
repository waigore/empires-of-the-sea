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
const STACK_BAR_HEIGHT: float = 92.0
## Shell pictograms shrink with the compact type so the cartouche still fits.
const BAR_ICON_WIDE: int = 22
const BAR_ICON_COMPACT: int = 20
const BAR_ICON_GAP_WIDE: int = 6
const BAR_ICON_GAP_COMPACT: int = 5
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


## The cartouche stacks its stat chips onto a second row when the row cannot fit
## the viewport, measured rather than guessed: every ledger added to the bar
## changes the budget. Compact type keeps the button row inside a 640-wide phone.
func _bar(hud: GameHud, view: Vector2) -> void:
	var room: float = view.x - 40.0
	var font: int = GameHud.BAR_FONT_COMPACT if compact else GameHud.BAR_FONT
	hud.top_row.add_theme_constant_override("separation", 8 if compact else 12)
	if hud.bar_font != font:
		hud.bar_font = font
		var icon_size: int = BAR_ICON_COMPACT if compact else BAR_ICON_WIDE
		var icon_gap: int = BAR_ICON_GAP_COMPACT if compact else BAR_ICON_GAP_WIDE
		for node: Node in hud.top_row.get_children():
			if node is Button:
				var button := node as Button
				button.add_theme_font_size_override("font_size", font)
				if button.icon != null:
					button.add_theme_constant_override("icon_max_width", icon_size)
					button.add_theme_constant_override("h_separation", icon_gap)
		# Theme changes mark the minimum size dirty for the next idle frame;
		# re-run once so the stack decision is measured against the real widths.
		hud.call_deferred("_relayout")
	_fit_captions(hud, compact)
	var stack: bool = _row_width(hud) > room
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


## Secondary ledger doors lose their caption on a phone (their medallion keeps
## the meaning and the tooltip the name); the wide cartouche restores it.
func _fit_captions(hud: GameHud, compact: bool) -> void:
	for node: Node in hud.top_row.get_children():
		var button := node as Button
		if button == null or not button.has_meta("compact_icon_only"):
			continue
		var caption: String = "" if compact else String(button.get_meta("caption", ""))
		if button.text == caption:
			continue
		button.text = caption
		button.icon_alignment = (
			HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
		)
		button.custom_minimum_size.x = (
			0.0 if compact else float(button.get_meta("min_width", 0.0))
		)
		hud.call_deferred("_relayout")


## Width the cartouche row needs with every chip on it, whatever their current
## parent: measuring the row itself would un-stack on the next pass, because a
## stacked row fits by definition and the layout would oscillate.
func _row_width(hud: GameHud) -> float:
	var separation: float = hud.top_row.get_theme_constant("separation")
	var total: float = 0.0
	var count: int = 0
	for node: Node in hud.top_row.get_children():
		var control := node as Control
		if control == null or not control.visible:
			continue
		if hud.chips.has(control):
			continue
		total += control.get_combined_minimum_size().x
		count += 1
	for chip: Control in hud.chips:
		total += chip.get_combined_minimum_size().x
		count += 1
	return total + separation * maxf(count - 1, 0)


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
		box.offset_top = hud.top_bar.offset_bottom + 6.0
		box.offset_bottom = box.offset_top
		return
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -230.0
	box.offset_right = 230.0
	box.offset_top = 84.0
	box.offset_bottom = 84.0


## The estates card on a phone: the panel keeps the sizing rules, the head the
## summary/filter widgets it resizes (REQ-P3-02).
static func fit_estates(panel: ImprovementPanel) -> void:
	panel.set_compact(is_compact(panel.get_viewport_rect().size))
