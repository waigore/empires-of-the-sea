class_name LedgerMarket
extends VBoxContainer
## MARKET tab of the ledger: the crown's own trade — cargo-hold banner, trade
## terms, staged orders, the last clearing and one Buy/Sell row per commodity.
## A full hold or an unknown fleet locks imports; every press is an intent and
## the controller decides (wiki: ships-and-naval; REQ-P2-03).
##
## The Minor Nations & Tribes book is its own plate (LedgerOffers). The last
## clearing is LedgerMarketReceipt; staged bids are LedgerMarketOrders; terms
## wording is LedgerMarketText — this page only mounts them (REQ-P3-01).

signal trade_requested(commodity: String, quantity: int, is_buy: bool)
signal offer_requested(offer_id: String, quantity: int)
signal cancel_requested(order_id: String)

const CATEGORIES: Array = [
	CommodityCatalog.Category.FOOD,
	CommodityCatalog.Category.RAW,
	CommodityCatalog.Category.MANUFACTURED,
]

var _economy: PlayerEconomy = null
var _market: WorldMarket = null
## Home-fleet holds and this turn's laden imports, from the controller.
var _cargo: Dictionary = {}
## The offers plate: the tribes' book and the chips that narrow it.
var _offers_plate: LedgerOffers = null
## A phone viewport wants thumb-sized chips; remembered for the next rebuild.
var _compact: bool = false
## The crown reading the book: its own staged orders, deals, terms and subsidy.
## A player who sails as England must read England's trade, never Spain's.
var _viewer: int = FactionCatalog.PLAYER_FACTION
## The batch reading every row shares for one repaint: the purse the auction may
## spend, the holds free after the staged bids, the tons production claimed.
var _order_ctx: Dictionary = {}
## Batch presses keyed "bid:<commodity>" / "offer:<commodity>", for tests and
## tooling (REQ-P3-02).
var _batches: Dictionary = {}
## The trade the court's own market pass would book this phase, in gold above the
## orders it answers (wiki: world-market § Trade orders; DR-20261121-09).
var _counsel: Label = null


## `offers` is this turn's Minor/Tribe book, rows as in `MinorMarket.emit`;
## `clearing` is the last world-market report, so the receipt names its ducats.
## `counsel` is the crown's own trade plan (`MapPlayMarketPick`), already worded;
## a page filled without one carries no gold line.
func fill(
	economy: PlayerEconomy,
	market: WorldMarket,
	cargo: Dictionary,
	offers: Array = [],
	clearing: Dictionary = {},
	viewer: int = FactionCatalog.PLAYER_FACTION,
	counsel: String = ""
) -> void:
	_economy = economy
	_market = market
	_cargo = cargo
	_viewer = viewer
	UiRowBuilder.clear(self)
	_batches.clear()
	_counsel = null
	_order_ctx = MarketBatch.context(_economy, _cargo, MarketBatch.reservations(_economy))
	_add_cargo_banner()
	var budget: Label = LedgerBudget.banner(_economy)
	if budget != null:
		add_child(budget)
	_add_terms_banner()
	_add_counsel(counsel)
	LedgerMarketOrders.mount(
		self, _market, _viewer,
		func(order_id: String) -> void: cancel_requested.emit(order_id)
	)
	LedgerMarketReceipt.mount(self, _market, clearing, _viewer)
	_add_offers(offers)
	var header := UiRowBuilder.row(0.0)
	header.add_child(UiRowBuilder.caption("COMMODITY", 10, Palette.TEXT_DIM, 132.0))
	header.add_child(UiRowBuilder.caption("HAVE", 10, Palette.TEXT_DIM, 44.0))
	header.add_child(UiRowBuilder.caption("PRICE", 10, Palette.TEXT_DIM, 44.0))
	add_child(header)
	for category: Variant in CATEGORIES:
		for id: String in CommodityCatalog.ids_in(category):
			add_child(_market_row(id, economy.quantity(id), claimed_by_production(economy, id)))
	UiRowBuilder.spacer(self)


## Units the court's own assigned production runs will eat before the auction
## clears: the tons an offer can never sell (wiki: world-market § Trade orders —
## the offer cap is the post-production stockpile minus industry reservations).
static func claimed_by_production(economy: PlayerEconomy, commodity: String) -> int:
	return maxi(int(MarketBatch.reservations(economy).get(commodity, 0)), 0)


func _add_cargo_banner() -> void:
	var banner := UiRowBuilder.label(LedgerMarketText.cargo_line(_cargo), 12, LedgerMarketText.cargo_color(_cargo))
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size = Vector2(240, 0)
	add_child(banner)
	_add_crossing()


## The crossing the holds will make this turn, under the holds they spend: the
## Extraction phase ships the richest tonnage first and leaves the rest on the
## far shore, and the despatch only says so after the fact (wiki: ships-and-naval
## § Cargo holds and capacity; DR-20261116-05). Printed only when tonnage waits,
## so a court with no overseas estate reads no extra chrome (REQ-P1-07), and the
## rule sits on the page rather than in a hover a phone never shows (REQ-P5-07).
func _add_crossing() -> void:
	var read: Dictionary = _cargo.get("crossing", {}) as Dictionary
	var line: String = CargoRead.line(read)
	if line.is_empty():
		return
	var crossing := UiRowBuilder.label(line, 12, Palette.GOLD_PALE)
	crossing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crossing.custom_minimum_size = Vector2(240, 0)
	add_child(crossing)
	var note: String = CargoRead.note(read)
	if note.is_empty():
		return
	var rule := UiRowBuilder.label(note, 11, Palette.TEXT_DIM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size = Vector2(240, 0)
	add_child(rule)


## The tribes' book stands above the world price rows on its own plate: the
## chips, the reading they select and the rows they narrow never touch this
## page (REQ-P3-01). A bid is still an intent — the plate emits it and the
## controller decides (REQ-P2-03).
func _add_offers(offers: Array) -> void:
	_offers_plate = null
	UiRowBuilder.spacer(self, 6.0)
	_offers_plate = LedgerOffers.new()
	_offers_plate.offer_requested.connect(
		func(offer_id: String, quantity: int) -> void:
			offer_requested.emit(offer_id, quantity)
	)
	add_child(_offers_plate)
	_offers_plate.fill(offers, _cargo, _compact, _market, _viewer, _order_ctx)
	UiRowBuilder.spacer(self, 4.0)


## Rows the offers plate is drawing right now, in display order (tests and
## tooling use this instead of reaching into the offer box; REQ-P3-02).
func visible_offers() -> Array[Dictionary]:
	return _offers_plate.visible_offers() if _offers_plate != null else []


## The seller/good/sort chips, for tests and the mobile layout audit.
func offer_filters() -> Dictionary:
	return _offers_plate.offer_filters() if _offers_plate != null else {}


## The Bid buttons the offers plate is drawing, in row order (REQ-P3-02).
func offer_buttons() -> Array[Button]:
	if _offers_plate == null:
		return []
	return _offers_plate.offer_buttons()


## Thumb-sized chips on a phone viewport (REQ-P5-07).
func set_compact(compact: bool) -> void:
	_compact = compact
	if _offers_plate != null:
		_offers_plate.set_compact(compact)


## Drops the reading back to the whole book: the page is rebuilt in place, so a
## chip a reader (or a case) pressed stays pressed into the next book.
func reset_offer_filters() -> void:
	if _offers_plate != null:
		_offers_plate.reset_filters()


## One plain sentence for the court's trade diplomacy, so an adjusted price is
## never a mystery (wiki: world-market § FTP; REQ-P2-03).
func _add_terms_banner() -> void:
	var text: String = LedgerMarketText.terms_line(_market, _viewer)
	if text.is_empty():
		return
	var banner := UiRowBuilder.label(text, 12, Palette.GOLD_PALE)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size = Vector2(240, 0)
	add_child(banner)


## The trade the court's own market pass would book this phase, in gold above
## the orders it answers — the plan the pass stages at the turn's close, so a
## crown reads what her staff would do before she presses a row (wiki:
## world-market § Trade orders; DR-20261121-09). A quiet plan still speaks: the
## line names the gate that leaves the book empty (REQ-P5-06).
func _add_counsel(counsel: String) -> void:
	if counsel.is_empty():
		return
	_counsel = UiRowBuilder.wrapped_line(counsel, 12, Palette.GOLD)
	add_child(_counsel)


## The gold counsel line's text, for tests and tooling (REQ-P3-02). Empty when
## the page was filled without a pick.
func counsel_text() -> String:
	return "" if _counsel == null else _counsel.text


func _market_row(id: String, held: int, claimed: int = 0) -> Control:
	var built: Dictionary = MarketRow.build(
		id, held, claimed, _cargo, _market, _viewer, _order_ctx, _compact,
		func(commodity: String, quantity: int, is_buy: bool) -> void:
			trade_requested.emit(commodity, quantity, is_buy)
	)
	for side: String in (built["batches"] as Dictionary).keys():
		_batches["%s:%s" % [side, id]] = built["batches"][side]
	return built["row"] as Control


## Batch presses keyed "bid:<commodity>" / "offer:<commodity>" for this page's
## rows, plus the offers plate's own presses keyed by offer id; tests and
## tooling read this instead of walking the page's children (REQ-P3-02).
func batch_buttons() -> Dictionary:
	if _offers_plate == null:
		return _batches
	var out: Dictionary = _batches.duplicate()
	out.merge(_offers_plate.batch_buttons(), true)
	return out
