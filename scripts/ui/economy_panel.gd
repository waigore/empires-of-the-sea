class_name EconomyPanel
extends LedgerFrame
## Ledger: production assignment, world market and worker roster in three tabs.
## Presentation only — every button emits an intent and the controller asks the
## rules layer what happened (REQ-P2-03). Each tab body is its own module
## (LedgerProduction, LedgerMarket, LedgerWorkers); this panel only builds the
## body and relays their signals. The sheet, masthead and phone profile are
## LedgerFrame's (REQ-P3-01).

signal trade_requested(commodity: String, quantity: int, is_buy: bool)
signal offer_requested(offer_id: String, quantity: int)
signal cancel_requested(order_id: String)
signal production_changed(recipe_id: String, units: int)
signal production_batch_requested(plan: Dictionary)
signal recruit_requested(tier: int, count: int)
signal disband_requested(tier: int)

const TAB_PRODUCTION: String = "PRODUCTION"
const TAB_MARKET: String = "MARKET"
const TAB_WORKERS: String = "WORKERS"
## Compact tab strip is 27 px high; a phone tab gets thumb padding instead.
const TAB_MIN_HEIGHT: float = 300.0

var _summary: Label = null
var _preview: Label = null
var _tabs: TabContainer = null
var _production: LedgerProduction = null
var _market_page: LedgerMarket = null
var _workers: LedgerWorkers = null


func _init() -> void:
	title_text = "THE LEDGER"


func _build_body(column: VBoxContainer) -> void:
	_summary = UiRowBuilder.label("", 14, Palette.TEXT)
	column.add_child(_summary)
	_preview = _preview_label()
	column.add_child(_preview)

	_tabs = _make_tabs(TAB_MIN_HEIGHT)
	_production = _add_tab(_tabs, TAB_PRODUCTION, LedgerProduction.new()) as LedgerProduction
	_market_page = _add_tab(_tabs, TAB_MARKET, LedgerMarket.new()) as LedgerMarket
	_workers = _add_tab(_tabs, TAB_WORKERS, LedgerWorkers.new()) as LedgerWorkers
	_connect_pages()


func _preview_label() -> Label:
	var preview := UiRowBuilder.label("", 12, Palette.TEXT_DIM)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrapped Label reports a min height measured at width 1, which would
	# push the Close/newer rows off a short screen. A sane wrap width bounds it.
	preview.custom_minimum_size = Vector2(240, 0)
	return preview


func _connect_pages() -> void:
	_production.production_changed.connect(
		func(recipe_id: String, units: int) -> void: production_changed.emit(recipe_id, units)
	)
	_production.production_batch_requested.connect(
		func(plan: Dictionary) -> void: production_batch_requested.emit(plan)
	)
	_market_page.trade_requested.connect(
		func(commodity: String, quantity: int, is_buy: bool) -> void:
			trade_requested.emit(commodity, quantity, is_buy)
	)
	_market_page.offer_requested.connect(
		func(offer_id: String, quantity: int) -> void:
			offer_requested.emit(offer_id, quantity)
	)
	_market_page.cancel_requested.connect(
		func(order_id: String) -> void: cancel_requested.emit(order_id)
	)
	_workers.recruit_requested.connect(
		func(tier: int, count: int) -> void: recruit_requested.emit(tier, count)
	)
	_workers.disband_requested.connect(func(tier: int) -> void: disband_requested.emit(tier))


func select_tab(index: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


## The tab body is the part that gives way on a short (phone) viewport, so the
## header and Close stay on screen instead of being pushed off the bottom. The
## masthead and projection also tighten so the body keeps most of the sheet
## (REQ-P1-07).
func _apply_profile(compact: bool) -> void:
	_workers.set_compact(compact)
	_market_page.set_compact(compact)
	_tabs.custom_minimum_size = Vector2(0.0, 0.0 if compact else TAB_MIN_HEIGHT)
	if _summary != null:
		_summary.add_theme_font_size_override("font_size", 12 if compact else 14)
	if _preview != null:
		# One clipped line instead of an autowrapped paragraph.
		_preview.add_theme_font_size_override("font_size", 11 if compact else 12)
		_preview.autowrap_mode = (
			TextServer.AUTOWRAP_OFF if compact else TextServer.AUTOWRAP_WORD_SMART
		)
		_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_preview.clip_text = compact
	if compact:
		_tabs.add_theme_stylebox_override("tab_selected", _tab_box(true))
		_tabs.add_theme_stylebox_override("tab_unselected", _tab_box(false))
		_tabs.add_theme_stylebox_override("tab_hovered", _tab_box(false))
		return
	for key: String in ["tab_selected", "tab_unselected", "tab_hovered"]:
		_tabs.remove_theme_stylebox_override(key)


func _tab_box(selected: bool) -> StyleBoxFlat:
	var fill := Color(0.16, 0.13, 0.09, 0.98) if selected else Color(0.09, 0.07, 0.05, 0.9)
	return UiTheme.box(fill, Palette.GOLD_DIM, 1, 3, Vector4(16, 11, 16, 11))


## Rebuilds every row from live state plus the end-of-turn projection report.
## `pick` is the court's own production pick (`MapPlayProductionPick`): the runs
## the crown's own economy pass would book, printed on the PRODUCTION tab
## (REQ-P5-03, REQ-P5-06; DR-20261121-07).
func refresh(
	economy: PlayerEconomy,
	market: WorldMarket,
	report: Dictionary,
	cargo: Dictionary = {},
	offers: Array = [],
	viewer: int = FactionCatalog.PLAYER_FACTION,
	pick: Dictionary = {}
) -> void:
	if _tabs == null:
		return
	_summary.text = LedgerReportText.summary(economy, report)
	_preview.text = LedgerMarketText.preview(report)
	# The stockpile tab reads its holdings and its steppers' ceiling from the
	# same projection the header promises (REQ-P2-03).
	_production.fill(economy, report, pick)
	_market_page.fill(
		economy, market, cargo, offers, report.get("clearing", {}) as Dictionary,
		viewer
	)
	_workers.fill(economy, report)


## Body container for one tab ("PRODUCTION", "MARKET", "WORKERS"); tests and
## tooling use this instead of reaching into page privates (REQ-P3-02).
func page_body(title: String) -> Node:
	if _tabs == null:
		return null
	var scroll: Node = _tabs.get_node_or_null(NodePath(title))
	return scroll.get_child(0) if scroll != null else null


## Tab strip minimum height (0 on a compact viewport), for layout tests.
func tabs_min_height() -> float:
	return _tabs.custom_minimum_size.y if _tabs != null else 0.0
