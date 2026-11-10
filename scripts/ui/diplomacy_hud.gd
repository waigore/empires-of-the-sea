class_name DiplomacyHud
extends RefCounted
## Builds and opens the court ledger for GameHud. Kept out of HudChrome and
## HudPanels so those shared files stay under the P3 size bar (REQ-P3-01).


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
	hud._diplomacy_panel.close_pressed.connect(func() -> void: hide(hud.panels))
	hud._diplomacy_panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			hud.diplomacy_order.emit(kind, target, arg)
	)
	# The full dossier is read like the roster: a sheet of its own over the HUD,
	# so the court panel can stay the summary (REQ-P5-01, REQ-P1-07).
	_build_dossier_screen(hud)
	hud._diplomacy_panel.dossier_pressed.connect(
		func(subject: int) -> void:
			if hud.dossier_screen != null:
				hud.dossier_screen.open_subject(subject)
	)
	hud._diplomacy_wrap.add_child(hud._diplomacy_panel)


## One sheet, built with the court so its data is always the bound session's.
static func _build_dossier_screen(hud: GameHud) -> void:
	var layer := CanvasLayer.new()
	layer.name = "DossierLayer"
	layer.layer = 6
	hud.add_child(layer)
	hud.dossier_screen = CourtDossierScreen.new()
	layer.add_child(hud.dossier_screen)


## The court takes the same edge as the economy and college ledgers.
static func show(
	panels: HudPanels,
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	treasury: int,
	tech: Dictionary = {},
	court_reports: Dictionary = {}
) -> void:
	panels.hide_province()
	panels.hide_fleet()
	panels.hide_civilian()
	panels.hide_army()
	panels.hide_economy()
	panels.hide_research()
	panels.diplomacy_panel.refresh(state, world, player, treasury, tech, court_reports)
	panels.diplomacy_wrap.visible = true
	panels.diplomacy_open = true
	var tween := panels.host.create_tween()
	tween.tween_property(panels.diplomacy_wrap, "modulate:a", 1.0, 0.22).from(0.0)


static func refresh(
	panels: HudPanels,
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	treasury: int,
	tech: Dictionary = {},
	court_reports: Dictionary = {}
) -> void:
	if panels.diplomacy_open:
		panels.diplomacy_panel.refresh(state, world, player, treasury, tech, court_reports)


static func hide(panels: HudPanels) -> void:
	if not panels.diplomacy_open:
		return
	panels.diplomacy_open = false
	panels.diplomacy_wrap.visible = false


static func is_open(panels: HudPanels) -> bool:
	return panels.diplomacy_open
