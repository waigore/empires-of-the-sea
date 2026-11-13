class_name HudDespatchCover
extends RefCounted
## The rule that keeps the court's news off a phone sheet (REQ-P1-05, REQ-P1-07).
##
## A 411-point screen has no strip beside a sheet: a despatch plate raised over
## one covers the controls the player just opened, and three of them (a campaign
## opens with three) hide the sheet's own header. So while a dossier, a ledger,
## the estates card or a battle plate holds the court, the lane holds its lines
## and prints them afterwards. Desktop is untouched, and a sheet host without a
## HUD simply skips the call.

## Recomputes the lane's covered state from what is on screen.
static func refresh(hud: GameHud) -> void:
	if hud == null or hud.despatches == null:
		return
	hud.despatches.set_covered(hud.is_quick_battle_shown() or sheet_open(hud))


## True when a phone sheet covers the map area the lane would print in.
static func sheet_open(hud: GameHud) -> bool:
	if hud.panels == null or not HudLayout.is_compact(hud.size):
		return false
	for slot: HudPanelSlot in hud.panels.selections():
		if slot != null and slot.open:
			return true
	for slot: HudPanelSlot in [hud.panels.economy, hud.panels.research, hud.panels.diplomacy]:
		if slot != null and slot.open:
			return true
	# Full-screen cards that do not ride the panel dock: the empire roster, the
	# court's dossier and the muster roll cover the lane just as completely.
	for card: Control in [hud.civilian_roster, hud.dossier_screen, hud.muster_roll]:
		if card != null and card.visible:
			return true
	var estates: ImprovementPanel = estates_panel(hud)
	return estates != null and estates.is_open()


## The estates card is the HUD's sibling under the map screen's CanvasLayer, so
## it is reached through the screen rather than by a child path.
static func estates_panel(hud: GameHud) -> ImprovementPanel:
	var screen := hud.owner as MapScreen
	if screen != null:
		return screen.improvements
	var host: Node = hud.get_parent()
	if host == null:
		return null
	return host.get_node_or_null("Improvements") as ImprovementPanel
