class_name ArmyHud
extends RefCounted
## Builds the army dossier shell for GameHud. Kept out of the chrome assembly so
## the shared files stay under the P3 size bar (REQ-P3-01).


static func build(hud: GameHud) -> void:
	hud._army_panel = ArmyPanel.new()
	hud._army_panel.action_pressed.connect(func(action: String) -> void:
		hud.army_action.emit(action)
	)
	hud._army_panel.close_pressed.connect(func() -> void: hud.army_closed.emit())
	hud._army_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud.panels.army = HudPanelSlot.build(hud, hud._army_panel, GameHud.PANEL_WIDTH, true)
	hud._army_wrap = hud.panels.army.wrap
