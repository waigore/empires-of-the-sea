class_name ArmyHud
extends RefCounted
## Builds the army dossier shell for GameHud. Kept out of HudChrome so the
## shared chrome file stays under the P3 size bar (REQ-P3-01).


static func build(hud: GameHud) -> void:
	hud._army_wrap = Control.new()
	hud._army_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hud._army_wrap.offset_left = -GameHud.PANEL_MARGIN
	hud._army_wrap.offset_right = GameHud.PANEL_WIDTH - GameHud.PANEL_MARGIN
	hud._army_wrap.offset_top = 84.0
	hud._army_wrap.offset_bottom = -104.0
	hud._army_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._army_wrap.visible = false
	hud.add_child(hud._army_wrap)

	hud._army_panel = ArmyPanel.new()
	hud._army_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._army_panel.action_pressed.connect(func(action: String) -> void:
		hud.army_action.emit(action)
	)
	hud._army_panel.close_pressed.connect(func() -> void: hud.army_closed.emit())
	hud._army_panel.dock_side_pressed.connect(func() -> void: hud.panels.toggle_dock_side())
	hud._army_wrap.add_child(hud._army_panel)
