class_name HudOverlays
extends RefCounted
## The HUD's cover layers — campaign-end, Quick Battle, the Gazette sheet —
## built together so their stacking order is one list (REQ-P1-04, REQ-P5-06).
##
## Their cartouche seals stay with the rail in HudChrome: a seal is chrome, the
## plate it opens is an overlay.


static func build(hud: GameHud) -> void:
	_victory(hud)
	_quick_battle(hud)
	_gazette(hud)


## Campaign-end plate: built first of the family so it covers every dossier
## (wiki: victory).
static func _victory(hud: GameHud) -> void:
	hud.victory_overlay = VictoryOverlay.new()
	hud.victory_overlay.z_index = 40
	hud.victory_overlay.dismissed.connect(func() -> void: hud.victory_dismissed.emit())
	hud.add_child(hud.victory_overlay)


## Quick Battle plate: above the dossiers, below the campaign-end plate.
static func _quick_battle(hud: GameHud) -> void:
	hud.quick_battle_overlay = QuickBattleOverlay.new()
	hud.quick_battle_overlay.z_index = 35
	hud.quick_battle_overlay.finished.connect(func() -> void: hud._on_quick_battle_finished())
	hud.add_child(hud.quick_battle_overlay)


## The crown's news sheet: over the dossiers, under the Quick Battle and
## campaign-end plates, and soft — it never takes the whole screen.
static func _gazette(hud: GameHud) -> void:
	hud.gazette_plate = GazettePlate.new()
	hud.gazette_plate.z_index = 30
	hud.add_child(hud.gazette_plate)
