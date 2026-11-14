class_name HudLayout
extends RefCounted
## Two chrome geometries (REQ-P1-05). WIDE is the desktop atlas bar; COMPACT is
## the phone/tablet-portrait arrangement: a shorter cartouche, a smaller minimap,
## a tighter zoom pair and a shorter end-turn seal, all in points so every touch
## target keeps its physical size.
##
## Dossiers and the ledger are re-anchored by `_dossiers` below.

const COMPACT_WIDTH: float = 1000.0
const COMPACT_HEIGHT: float = 560.0
const STACK_BAR_HEIGHT: float = 98.0
## The left rail under the cartouche is empty now: the estates door and the
## Gazette seal moved onto the bar, so nothing but the chart sits there.
const LEFT_RAIL: float = 0.0

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
	_lens_key(hud)
	_end_turn(hud)
	_toasts(hud)
	_dossiers(hud.panels, compact, view)


## Re-anchors every dossier for the viewport: a phone gets a full-height side
## sheet (the end-turn seal waits behind it, as with any modal), the atlas
## layout keeps its gap above the seal; the ledger takes the whole edge.
func _dossiers(panels: HudPanels, is_compact: bool, view: Vector2) -> void:
	var width: float = GameHud.PANEL_WIDTH
	if is_compact:
		width = clampf(view.x * 0.4, 280.0, GameHud.PANEL_WIDTH)
	panels.dock.configure(
		width,
		64.0 if is_compact else PanelDock.TOP,
		-10.0 if is_compact else PanelDock.BOTTOM
	)
	for slot: HudPanelSlot in panels.selections():
		panels.dock.relayout(slot.wrap, slot.open)
	# The ledgers take the whole edge on a phone, capped so the map stays visible.
	for spec: Array in [
		[panels.economy, HudPanelSlot.LEDGER_WIDTH],
		[panels.research, HudPanelSlot.LEDGER_WIDTH],
		[panels.diplomacy, HudPanelSlot.COURT_WIDTH],
	]:
		var slot: HudPanelSlot = spec[0]
		slot.wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		slot.wrap.offset_left = -minf(view.x - 20.0, spec[1]) if is_compact else -spec[1]
		slot.wrap.offset_right = -10.0 if is_compact else -GameHud.PANEL_MARGIN
		slot.wrap.offset_top = 64.0 if is_compact else PanelDock.TOP
		slot.wrap.offset_bottom = -10.0 if is_compact else PanelDock.BOTTOM


## The cartouche stacks its stat chips onto a second row when the row cannot fit
## the viewport, measured rather than guessed: every seal added to the bar
## changes the budget. Seals carry their own compact type, so no font pass is
## needed and the stack decision stays stable between relayouts.
func _bar(hud: GameHud, view: Vector2) -> void:
	var room: float = view.x - 40.0
	hud.top_row.add_theme_constant_override("separation", 6 if compact else 7)
	TopBar.apply_compact(hud, compact)
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


func _lens_key(hud: GameHud) -> void:
	var legend: LensLegend = hud.lens_legend
	if legend == null:
		return
	if compact:
		legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		legend.offset_left = -LensLegend.WIDTH - 10.0
		legend.offset_right = -10.0
		legend.offset_top = maxf(66.0, hud.top_bar.offset_bottom + 8.0)
		legend.offset_bottom = legend.offset_top + LensLegend.HEIGHT
		return
	legend.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	legend.offset_left = 18.0
	legend.offset_top = 186.0
	legend.offset_right = legend.offset_left + LensLegend.WIDTH
	legend.offset_bottom = legend.offset_top + LensLegend.HEIGHT


func _end_turn(hud: GameHud) -> void:
	EndTurnDoor.apply_compact(hud, compact)


## Toasts sit under the cartouche. The rail below it is empty now, so the lane
## runs the full width on a phone too. The lane owns the geometry.
func _toasts(hud: GameHud) -> void:
	if hud.despatches == null:
		return
	hud.despatches.fit(compact, hud.top_bar.offset_bottom, LEFT_RAIL)


## The estates card on a phone: the panel keeps the sizing rules, the head the
## summary/filter widgets it resizes (REQ-P3-02).
static func fit_estates(panel: ImprovementPanel) -> void:
	panel.set_compact(is_compact(panel.get_viewport_rect().size))
