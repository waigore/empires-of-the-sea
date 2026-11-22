class_name HudSheet
extends RefCounted
## One HUD sheet's door law: how a sheet is shown, hidden and re-read while it
## stands (REQ-P3-01, REQ-P1-05).
##
## Every show, hide and open-check on a dossier or a ledger used to be written
## once per sheet in [HudPanels], and the court ledger carried a copy of its own
## in [DiplomacyHud]. The sheets now read this one law, so a new sheet never
## repeats the reveal, the "repaint in place" rule or the toggle's pressed face.


## Shows `slot` with `content` painted on it. A sheet already on screen is
## repainted where it stands instead of revealed again: re-revealing it would
## fade the sheet back in and lose the player's place (REQ-P1-05). `toggle`, when
## a bar door opened it, takes the pressed face so the door reads open
## (REQ-P5-05).
static func show(
	dock: PanelDock, host: Control, slot: HudPanelSlot, content: Callable,
	toggle: CheckBox = null
) -> void:
	if toggle != null:
		toggle.button_pressed = true
	content.call()
	if not slot.open:
		slot.reveal(host, dock)


## Sets `slot` aside; `toggle` lets go of its pressed face so the door reads
## closed (REQ-P5-05). The slot itself ignores a second hide, so a close press
## that arrives twice slides the sheet out once.
static func hide(
	dock: PanelDock, host: Control, slot: HudPanelSlot, toggle: CheckBox = null
) -> void:
	if toggle != null:
		toggle.button_pressed = false
	slot.conceal(host, dock)