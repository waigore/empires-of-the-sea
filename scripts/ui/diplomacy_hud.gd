class_name DiplomacyHud
extends RefCounted
## Builds the court ledger shell for GameHud. Kept out of HudChrome so the
## shared chrome file stays under the P3 size bar (REQ-P3-01).


static func build(hud: GameHud) -> void:
	hud._diplomacy_wrap = Control.new()
	hud._diplomacy_wrap.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	hud._diplomacy_wrap.offset_left = -620.0
	hud._diplomacy_wrap.offset_right = -GameHud.PANEL_MARGIN
	hud._diplomacy_wrap.offset_top = 84.0
	hud._diplomacy_wrap.offset_bottom = -104.0
	hud._diplomacy_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	hud._diplomacy_wrap.visible = false
	hud.add_child(hud._diplomacy_wrap)

	hud._diplomacy_panel = DiplomacyPanel.new()
	hud._diplomacy_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._diplomacy_panel.close_pressed.connect(func() -> void: hud.panels.hide_diplomacy())
	hud._diplomacy_panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			hud.diplomacy_order.emit(kind, target, arg)
	)
	hud._diplomacy_wrap.add_child(hud._diplomacy_panel)
