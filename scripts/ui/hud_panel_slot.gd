class_name HudPanelSlot
extends RefCounted
## One HUD sheet: the wrap it docks or fades in and the panel it holds. Builders
## hand a panel to a slot; HudPanels opens and closes them, so no builder repeats
## the wrap geometry and no show method repeats the hide-the-others list
## (REQ-P3-01, REQ-P3-02).

const LEDGER_WIDTH: float = 520.0
const COURT_WIDTH: float = 620.0

var wrap: Control = null
var panel: Control = null
## Selection dossiers slide in from the edge; an edge ledger fades over the map.
var slides: bool = true
var open: bool = false


static func build(
	host: Control, p_panel: Control, width: float, slides_in: bool
) -> HudPanelSlot:
	var slot := HudPanelSlot.new()
	slot.panel = p_panel
	slot.slides = slides_in
	slot.wrap = Control.new()
	slot.wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	if slides_in:
		slot.wrap.offset_left = -GameHud.PANEL_MARGIN
		slot.wrap.offset_right = width - GameHud.PANEL_MARGIN
		slot.wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		slot.wrap.offset_left = -width
		slot.wrap.offset_right = -GameHud.PANEL_MARGIN
		slot.wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.wrap.offset_top = PanelDock.TOP
	slot.wrap.offset_bottom = PanelDock.BOTTOM
	slot.wrap.visible = false
	host.add_child(slot.wrap)
	p_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.wrap.add_child(p_panel)
	return slot


## A reveal on a sheet already on screen is a no-op: a repaint must not fade the
## dialog back in or slide it out from under the player (REQ-P1-05).
func reveal(host: Node, dock: PanelDock) -> void:
	if open:
		return
	open = true
	_sync_despatch_cover(host)
	if slides and dock != null:
		dock.slide_in(host, wrap)
		return
	wrap.visible = true
	var tween := host.create_tween()
	tween.tween_property(wrap, "modulate:a", 1.0, 0.22).from(0.0)


func conceal(host: Node, dock: PanelDock) -> void:
	if not open:
		return
	open = false
	_sync_despatch_cover(host)
	if slides and dock != null:
		dock.slide_out(host, wrap, func() -> void: wrap.visible = false)
		return
	wrap.visible = false


## A phone sheet holds the court's news while it is up (HudDespatchCover owns
## the rule); a desktop sheet leaves the lane alone. Hosts without a HUD simply
## skip it.
func _sync_despatch_cover(host: Node) -> void:
	if host != null:
		HudDespatchCover.refresh(host as GameHud)


## A ledger taking the whole edge closes a sliding dossier outright: its
## slide-out tween would bleed text through the ledger's fade-in.
func conceal_now() -> void:
	open = false
	wrap.visible = false
