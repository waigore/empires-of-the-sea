class_name DiplomacyHud
extends RefCounted
## Builds and opens the court ledger for GameHud. Kept out of HudChrome and
## HudPanels so those shared files stay under the P3 size bar (REQ-P3-01).


static func build(hud: GameHud) -> void:
	hud._diplomacy_panel = DiplomacyPanel.new()
	hud._diplomacy_panel.close_pressed.connect(func() -> void: hide(hud.panels))
	hud._diplomacy_panel.order_pressed.connect(
		func(kind: String, target: int, arg: String) -> void:
			hud.diplomacy_order.emit(kind, target, arg)
	)
	# The full dossier is read like the roster: a sheet of its own over the HUD,
	# so the court panel can stay the summary (REQ-P5-01, REQ-P1-07). The panel
	# opens it with the state it already holds, so no session binding is needed.
	_build_dossier_screen(hud)
	hud._diplomacy_panel.dossier_screen = hud.dossier_screen
	hud.panels.diplomacy = HudPanelSlot.build(
		hud, hud._diplomacy_panel, HudPanelSlot.COURT_WIDTH, false
	)
	hud._diplomacy_wrap = hud.panels.diplomacy.wrap


## One sheet, built with the court, over its own canvas layer.
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
	panels.close_sheets(panels.diplomacy)
	panels.diplomacy_panel.refresh(state, world, player, treasury, tech, court_reports)
	panels.diplomacy.reveal(panels.host, panels.dock)


static func refresh(
	panels: HudPanels,
	state: DiplomacyState,
	world: WorldMap,
	player: int,
	treasury: int,
	tech: Dictionary = {},
	court_reports: Dictionary = {}
) -> void:
	if panels.is_diplomacy_open():
		panels.diplomacy_panel.refresh(state, world, player, treasury, tech, court_reports)


static func hide(panels: HudPanels) -> void:
	panels.diplomacy.conceal(panels.host, panels.dock)


static func is_open(panels: HudPanels) -> bool:
	return panels.is_diplomacy_open()
