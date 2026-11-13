class_name GameHud
extends Control
## Screen furniture: cartouche bar, minimap, zoom controls, end-turn seal, plates
## and lenses. Side dossiers live on HudPanels, the status plaques on
## HudStatChips, the transient news on HudDespatches, and the widgets themselves
## are HudChrome's build (REQ-P3-01).

signal end_turn_pressed
signal zoom_in_pressed
signal zoom_out_pressed
signal minimap_jump(world_position: Vector2)
signal panel_action(action: String)
signal panel_closed
signal fleet_action(action: String)
signal fleet_closed
signal civilian_action(action: String)
signal civilian_cancel
signal civilian_closed
signal army_action(action: String)
signal army_closed
signal economy_pressed
signal research_pressed
signal diplomacy_pressed
signal diplomacy_order(kind: String, target: int, arg: String)
## The civilian chip opens the whole-empire roster (REQ-P5-01).
signal civilian_roster_pressed
## The cartouche's muster seal opens the whole-empire force ledger
## (REQ-P5-01, REQ-P5-03; DR-20261113-12).
signal muster_roll_pressed
signal region_toggle_pressed
signal focus_capital_pressed
## A map-lens toggle changed state (button or keyboard): survey, diplomacy, the
## crown road or the defence reading.
signal lens_pressed(active: bool)
signal diplomacy_lens_pressed(active: bool)
signal crown_lens_pressed(active: bool)
signal defence_lens_pressed(active: bool)
## Status plaques double as shortcuts to the crown's forces in this region.
signal fleet_status_pressed
signal army_status_pressed
## The player closed the campaign plate to keep viewing the map.
signal victory_dismissed
## The cartouche seal opens the Gazette's archive (wiki: the-gazette).
signal gazette_pressed

const PANEL_WIDTH: float = 360.0
const PANEL_MARGIN: float = 16.0
const BAR_HEIGHT: float = 60.0
const BAR_HEIGHT_COMPACT: float = 56.0

var panels: HudPanels = null
## Treasury, income and force counts; the plaques own their own copy (REQ-P1-02).
var stats: HudStatChips = null
## The court's despatch lane: toast plates, their queue and the lane's geometry
## (REQ-P5-05, REQ-P5-06). HudChrome mounts it.
var despatches: HudDespatches = null
## The despatch column, read-only: HudDespatches owns it. The playtest drives
## count plates here, so the lane keeps one handle while the board moves.
var _toast_box: VBoxContainer:
	get:
		return despatches.lane if despatches != null else null
## News held behind a battle plate, read-only, oldest first (REQ-P5-06).
var _toast_queue: PackedStringArray:
	get:
		return despatches.waiting() if despatches != null else PackedStringArray()
## Survey key, shown only while the lens is on.
var lens_legend: LensLegend = null
## Touch platforms: no hover, so hover tooltips stay silent.
var touch_ui: bool = false

var top_bar: Control = null
var top_row: HBoxContainer = null
## Stat chips fall onto a second bar row when the cartouche row cannot fit.
var chip_row: HBoxContainer = null
var chips: Array[Control] = []
var minimap_frame: Control = null
var zoom_box: Control = null
var end_turn_wrap: Control = null
## Campaign-end plate (wiki: victory); null until the chrome builds it.
var victory_overlay: VictoryOverlay = null
## Quick Battle plate (wiki: quick-battle); null until the chrome builds it.
var quick_battle_overlay: QuickBattleOverlay = null
## The sea's despatch plate (wiki: ships-and-naval § Naval Combat Resolution);
## null until the chrome builds it.
var naval_plate: NavalPlate = null
## The crown's news sheet and its archive (wiki: the-gazette); a soft plate.
var gazette_plate: GazettePlate = null
## Whole-empire civilian ledger, built by HudChrome over the map (REQ-P5-01).
var civilian_roster: CivilianRosterPanel = null
## Whole-empire force ledger: every army and squadron (DR-20261113-12).
var muster_roll: ForceLedgerPanel = null
## The court's full dossier, opened from its summary block (DR-20261110-25).
var dossier_screen: CourtDossierScreen = null
## Turns stay shut once the rules decide the campaign (wiki: victory).
var campaign_over: bool = false

var _turn_label: Label = null
## The land and sea battle plates, their queues and the held news (BattlePlates).
var plates: BattlePlates = null
## Battles the rules resolved for the human, replayed one plate at a time.
var _quick_queue: Array[Dictionary]:
	get:
		return plates.land_queue if plates != null else [] as Array[Dictionary]
## Naval engagements the human fought, waiting their turn on the despatch plate.
var _naval_queue: Array[Dictionary]:
	get:
		return plates.sea_queue if plates != null else [] as Array[Dictionary]
var _nation_label: Label = null
var _region_button: Button = null
var _region_label: Label = null
## Read-only views of HudStatChips' plaques for drives and suites that still
## reach them through the HUD (REQ-P1-02).
var _treasury_label: Label:
	get:
		return stats.treasury_label if stats != null else null
var _income_label: Label:
	get:
		return stats.income_label if stats != null else null
var _fleet_label: Label:
	get:
		return stats.fleet_label if stats != null else null
var _civilian_label: Label:
	get:
		return stats.civilian_label if stats != null else null
var _army_label: Label:
	get:
		return stats.army_label if stats != null else null
var _treasury_chip: Button:
	get:
		return stats.treasury_chip if stats != null else null
var _fleet_chip: Button:
	get:
		return stats.fleet_chip if stats != null else null
var _civilian_chip: Button:
	get:
		return stats.civilian_chip if stats != null else null
var _army_chip: Button:
	get:
		return stats.army_chip if stats != null else null
var _treasury_value: int:
	get:
		return stats._treasury_value if stats != null else 0
var _minimap: Minimap = null
var _panel_wrap: Control = null
var _panel: ProvincePanel = null
var _fleet_wrap: Control = null
var _fleet_panel: FleetPanel = null
var _civilian_wrap: Control = null
var _civilian_panel: CivilianPanel = null
var _army_wrap: Control = null
var _army_panel: ArmyPanel = null
var _tooltip: PanelContainer = null
var _tooltip_label: Label = null
var _end_turn_button: Button = null
## Left-rail toggles for the four map lenses; HudChrome owns the legend.
var _lens_button: Button = null
var _diplomacy_lens_button: Button = null
var _crown_lens_button: Button = null
var _defence_lens_button: Button = null
var _glow: Panel = null
var _economy_wrap: Control = null
var _economy_panel: EconomyPanel = null
var _research_wrap: Control = null
var _research_panel: ResearchPanel = null
var _diplomacy_wrap: Control = null
var _diplomacy_panel: DiplomacyPanel = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	touch_ui = PlatformDisplay.is_handheld()
	stats = HudStatChips.new()
	panels = HudPanels.new()
	HudChrome.build(self)
	panels.bind(self)
	resized.connect(_relayout)
	_relayout()


## Chrome follows the viewport: atlas layout or HudLayout's compact one.
func _relayout() -> void:
	if panels == null:
		return
	apply_safe_area(PlatformDisplay.safe_insets(get_window()))
	HudLayout.new().apply(self)


func apply_safe_area(insets: Vector4) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = insets.x
	offset_top = insets.y
	offset_right = -insets.z
	offset_bottom = -insets.w


func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		var mouse: Vector2 = get_global_mouse_position()
		var limit: Vector2 = get_viewport_rect().size - _tooltip.size - Vector2(8, 8)
		_tooltip.position = Vector2(
			clampf(mouse.x + 18.0, 8.0, maxf(limit.x, 8.0)),
			clampf(mouse.y + 18.0, 8.0, maxf(limit.y, 8.0))
		)


func set_turn(turn: int, year: int) -> void:
	_turn_label.text = "Turn %d  ·  %d" % [turn, year]


## A despatch toast. `icon_name` raises the plate with a medallion (an
## auto-resolved siege's silenced battery) and holds it longer, so the loss is
## read and not mistaken for the turn's chatter (REQ-P5-05). The board decides
## when a battle plate means the news has to wait (REQ-P5-06).
func toast(text: String, icon_name: String = "") -> void:
	# The observer hides the human chrome; building toast plates for a hidden
	# court would only churn nodes every turn (REQ-P4-04).
	if not visible or despatches == null:
		return
	despatches.toast(text, icon_name)


## A despatch the open battle plate has already told: the court still hears it,
## but it is the first line the held-news cap spends (REQ-P5-06).
func toast_plate_line(text: String, icon_name: String = "") -> void:
	if not visible or despatches == null:
		return
	despatches.toast_plate_line(text, icon_name)


## The rules resolved one of the human's land battles as Quick Battle. BattlePlates
## queues the plates so a multi-battle turn replays them one at a time.
func show_quick_battle(battle: Dictionary, province: String) -> void:
	if plates == null:
		return
	plates.show_land(battle, province, FactionCatalog.names())


func is_quick_battle_shown() -> bool:
	return quick_battle_overlay != null and quick_battle_overlay.is_shown()


## The rules resolved one of the human's naval battles. Tell it as the sea's
## despatch, queued behind any land plate so a two-zone turn never stacks them.
func show_naval_dispatch(battle: Dictionary, zone: String) -> void:
	if plates == null:
		return
	plates.show_sea(battle, zone, FactionCatalog.names())


## Status plaques: the values, tooltips and tweens are HudStatChips' (REQ-P1-02).
func set_treasury(value: int, animate: bool = true) -> void:
	stats.set_treasury(value, animate)


func set_income(value: int) -> void:
	stats.set_income(value)


func set_fleets(value: int) -> void:
	stats.set_fleets(value)


func set_civilians(value: int) -> void:
	stats.set_civilians(value)


func set_armies(value: int) -> void:
	stats.set_armies(value)


func flash_income(amount: int) -> void:
	stats.flash_income(amount)


## Campaign decided: raise the plate and shut the end-turn seal for good
## (wiki: victory § Victory Screen).
func show_victory(state: VictoryState, player_faction: int, holdings: int) -> void:
	set_campaign_over(true)
	if victory_overlay != null:
		victory_overlay.show_victory(state, player_faction, holdings)


## Calendar cap closed the age undecided: same sealed plate, campaign-complete
## copy instead of a victory (wiki: victory § Calendar campaign end).
func show_campaign_complete(leader: int, turn: int, player_faction: int) -> void:
	set_campaign_over(true)
	if victory_overlay != null:
		victory_overlay.show_campaign_complete(leader, turn, player_faction)


## The human Great Power fell: same sealed plate family, defeat copy
## (wiki: victory § Great Power defeat; DR-20261109-05).
func show_defeat(defeat: DefeatState, player_faction: int) -> void:
	set_campaign_over(true)
	if victory_overlay != null:
		victory_overlay.show_defeat(defeat, player_faction)


## Turns never reopen; only the plate may step aside to keep viewing the map.
func set_campaign_over(over: bool) -> void:
	campaign_over = over
	_end_turn_button.disabled = over
	_end_turn_button.text = "CAMPAIGN ENDED" if over else "END TURN"
	# Longer caption + seal: drop the pictogram so the plate keeps one line.
	_end_turn_button.icon = null if over else ChromeIcons.texture("hourglass")
	_glow.visible = not over
	if not over:
		return
	panels.hide_province()
	panels.hide_fleet()
	panels.hide_civilian()
	panels.hide_army()
	panels.hide_economy()
	panels.hide_research()
	DiplomacyHud.hide(panels)


func is_victory_shown() -> bool:
	return victory_overlay != null and victory_overlay.is_shown()


## Mirrors a lens state onto its toggle and the shared key cartouche, without
## echoing the button signal (the screen owns the state). Only one lens is ever
## on, so the key shows the kind that was just raised.
func set_lens(active: bool, kind: String = LensLegend.KIND_SURVEY) -> void:
	var seals: Array = [
		[LensLegend.KIND_SURVEY, _lens_button],
		[LensLegend.KIND_DIPLOMACY, _diplomacy_lens_button],
		[LensLegend.KIND_CROWN_ROAD, _crown_lens_button],
		[LensLegend.KIND_DEFENCE, _defence_lens_button],
	]
	var raised: bool = false
	for pair: Array in seals:
		var seal: Button = pair[1] as Button
		if seal == null:
			continue
		if String(pair[0]) == kind and seal.button_pressed != active:
			seal.set_pressed_no_signal(active)
		raised = raised or seal.button_pressed
	if lens_legend == null:
		return
	lens_legend.set_kind(kind)
	lens_legend.visible = raised


func set_minimap(
	model: MapModel, map_size: Vector2, visibility: VisibilityModel = null
) -> void:
	_minimap.build(model, map_size, visibility)


## Ownership moved without the chart changing (a conquest, a treaty swap).
func refresh_minimap() -> void:
	_minimap.refresh_ownership()


func update_view_rect(rect: Rect2) -> void:
	_minimap.set_view_rect(rect)
