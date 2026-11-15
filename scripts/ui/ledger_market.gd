class_name LedgerMarket
extends VBoxContainer
## MARKET tab of the ledger: the crown's own trade — cargo-hold banner, trade
## terms, staged orders, the last clearing and one Buy/Sell row per commodity.
## A full hold or an unknown fleet locks imports; every press is an intent and
## the controller decides (wiki: ships-and-naval; REQ-P2-03).
##
## The Minor Nations & Tribes book is its own plate (LedgerOffers), so this page
## keeps one domain: the world price and the court's orders against it.

signal trade_requested(commodity: String, quantity: int, is_buy: bool)
signal offer_requested(offer_id: String, quantity: int)
signal cancel_requested(order_id: String)

const ROW_HEIGHT: float = 38.0
const CATEGORIES: Array = [
	CommodityCatalog.Category.FOOD,
	CommodityCatalog.Category.RAW,
	CommodityCatalog.Category.MANUFACTURED,
]

var _economy: PlayerEconomy = null
var _market: WorldMarket = null
## Home-fleet holds and this turn's laden imports, from the controller.
var _cargo: Dictionary = {}
## Last clearing report: the deals it settled and the overseas share it paid.
var _clearing: Dictionary = {}
## The offers plate: the tribes' book and the chips that narrow it.
var _offers_plate: LedgerOffers = null
## A phone viewport wants thumb-sized chips; remembered for the next rebuild.
var _compact: bool = false
## The crown reading the book: its own staged orders, deals, terms and subsidy.
## A player who sails as England must read England's trade, never Spain's.
var _viewer: int = FactionCatalog.PLAYER_FACTION


## `offers` is this turn's Minor/Tribe book, rows as in `MinorMarket.emit`;
## `clearing` is the last world-market report, so the receipt names its ducats.
func fill(
	economy: PlayerEconomy,
	market: WorldMarket,
	cargo: Dictionary,
	offers: Array = [],
	clearing: Dictionary = {},
	viewer: int = FactionCatalog.PLAYER_FACTION
) -> void:
	_economy = economy
	_market = market
	_cargo = cargo
	_clearing = clearing
	_viewer = viewer
	UiRowBuilder.clear(self)
	_add_cargo_banner()
	var budget: Label = LedgerBudget.banner(_economy)
	if budget != null:
		add_child(budget)
	_add_terms_banner()
	_add_staged()
	_add_deals()
	_add_prices()
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
	if economy == null:
		return 0
	var reserved: Dictionary = ProductionRecipes.reserved_inputs(economy.production.assignments())
	return maxi(int(reserved.get(commodity, 0)), 0)


func _add_cargo_banner() -> void:
	var banner := UiRowBuilder.label(LedgerText.cargo_line(_cargo), 12, LedgerText.cargo_color(_cargo))
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size = Vector2(240, 0)
	add_child(banner)


## Staged bids and offers: what the court will take to the turn-end auction. A
## carry-forward row is shown but cannot be withdrawn (wiki: world-market
## § Order persistence).
func _add_staged() -> void:
	if _market == null:
		return
	var orders: Array[MarketOrder] = _market.book.orders_for(
		_viewer
	)
	UiRowBuilder.spacer(self, 6.0)
	var title := UiRowBuilder.label("YOUR ORDERS", 11, Palette.GOLD_DIM)
	title.tooltip_text = "Bids and offers clear together when the turn closes."
	add_child(title)
	if orders.is_empty():
		var none := UiRowBuilder.label(
			"No orders staged — Buy and Sell enter next turn's auction.", 11,
			Palette.TEXT_DIM
		)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(240, 0)
		add_child(none)
		return
	for order: MarketOrder in orders:
		add_child(_staged_row(order))


func _staged_row(order: MarketOrder) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	var side: String = "BID" if order.is_bid() else "OFFER"
	var side_label := UiRowBuilder.caption(side, 10, Palette.GOLD_PALE, 46.0)
	row.add_child(side_label)
	row.add_child(CommodityIcons.cell(order.commodity, 96.0, 13))
	var quantity := UiRowBuilder.label("%d" % order.remaining(), 13, Palette.GOLD_PALE)
	quantity.custom_minimum_size = Vector2(38, 0)
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(quantity)
	var price: int = (
		_market.buy_price(order.commodity, _viewer) if order.is_bid()
		else _market.sell_price(order.commodity, _viewer)
	)
	var notional := UiRowBuilder.label("%d" % (price * order.remaining()), 12, Palette.TEXT_DIM)
	notional.custom_minimum_size = Vector2(52, 0)
	notional.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(notional)
	if _market.book.submitted.has(order):
		var cancel := UiRowBuilder.button("Cancel", ROW_HEIGHT, 62.0)
		cancel.pressed.connect(func() -> void: cancel_requested.emit(order.id))
		row.add_child(cancel)
	return row


## The crown's lines from the last clearing pass, so a fill is never silent
## (wiki: world-market § Trade orders; REQ-P5-05). The overseas share is the
## court's own line even when it traded nothing itself (wiki: world-market
## § First right of refusal).
func _add_deals() -> void:
	if _market == null:
		return
	var mine: Array[Dictionary] = []
	for raw: Variant in _market.book.last_deals:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		var buyer: int = int(deal.get("buyer", -2))
		var seller: int = int(deal.get("seller", -2))
		if buyer == _viewer or seller == _viewer:
			mine.append(deal)
	var share: int = LedgerText.share_credit(_clearing, _viewer)
	if mine.is_empty() and share <= 0:
		return
	UiRowBuilder.spacer(self, 4.0)
	add_child(UiRowBuilder.label("LAST CLEARING", 11, Palette.GOLD_DIM))
	for deal: Dictionary in mine.slice(0, 4):
		add_child(UiRowBuilder.label(LedgerText.deal_line(deal, _viewer), 12, Palette.TEXT_DIM))
	if mine.size() > 4:
		add_child(UiRowBuilder.label(
			"+%d more deals" % (mine.size() - 4), 11, Palette.TEXT_DIM
		))
	if share > 0:
		var shares := UiRowBuilder.label(
			"Overseas shares  +%d ducats" % share, 12, Palette.GOLD_PALE
		)
		shares.tooltip_text = (
			"The court's cut of the Minor and Tribe sales abroad — tile rights "
			+ "and embassy kickbacks (wiki: world-market § First right of refusal)."
		)
		add_child(shares)


## The clearing's price pass in one line: the goods that moved and the price they
## now stand at, so a turn's new market is read and never a silent change (wiki:
## world-market § Price discovery; REQ-P5-05). Empty when no price moved.
static func price_moves_line(report: Dictionary, limit: int = 4) -> String:
	var moved: Dictionary = report.get("prices", {}) as Dictionary
	if moved.is_empty():
		return ""
	var ids: Array[String] = []
	for raw: Variant in moved.keys():
		ids.append(String(raw))
	ids.sort()
	var parts: PackedStringArray = []
	for index in mini(ids.size(), limit):
		var id: String = ids[index]
		parts.append("%s %d" % [CommodityCatalog.label(id), int(moved[id])])
	var text: String = "Prices moved: " + "  ·  ".join(parts)
	if ids.size() > limit:
		text += "  ·  +%d more" % (ids.size() - limit)
	return text + "."


## The clearing moved prices: the goods and the price they now stand at, so the
## turn's new market is read where the clearing is narrated and never arrives as
## a silent change (wiki: world-market § Price discovery; REQ-P5-05).
func _add_prices() -> void:
	var line: String = price_moves_line(_clearing)
	if line.is_empty():
		return
	UiRowBuilder.spacer(self, 4.0)
	var moved := UiRowBuilder.label(line, 11, Palette.TEXT_DIM)
	moved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	moved.custom_minimum_size = Vector2(240, 0)
	add_child(moved)


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
	_offers_plate.fill(offers, _cargo, _compact, _market, _viewer)
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
	if _market == null:
		return
	var terms: Dictionary = _market.terms_for(_viewer)
	if terms.is_empty():
		return
	var buy: Dictionary = terms.get("buy", {})
	var sell: Dictionary = terms.get("sell", {})
	var buy_rate: float = float(buy.get("*", 1.0))
	var sell_rate: float = float(sell.get("*", 1.0))
	var text: String = "Trade terms: imports at %d%% and exports at %d%% of the world price." % [
		roundi(buy_rate * 100.0), roundi(sell_rate * 100.0)
	]
	var subsidy: int = _subsidy_rate()
	if subsidy > 0:
		text += " Subsidy %d%%: a subsidised court's goods cost us more, ours earn less." % subsidy
	var banner := UiRowBuilder.label(text, 12, Palette.GOLD_PALE)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size = Vector2(240, 0)
	add_child(banner)


## The largest subsidy this crown pays, so the banner names the step that prices
## a pair's deals (wiki: world-market § Subsidy price adjustment).
func _subsidy_rate() -> int:
	var best: int = 0
	for key: Variant in _market.subsidy_terms.keys():
		var parts: PackedStringArray = String(key).split(">")
		if parts.size() != 2 or int(parts[0]) != _viewer:
			continue
		best = maxi(best, int(_market.subsidy_terms[key]))
	return best


func _market_row(id: String, held: int, claimed: int = 0) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(CommodityIcons.cell(id, 132.0))

	var qty := UiRowBuilder.label("%d" % held, 14, Palette.GOLD_PALE)
	qty.custom_minimum_size = Vector2(44, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var buy_unit: int = _market.buy_price(id, _viewer)
	var sell_unit: int = _market.sell_price(id, _viewer)
	var price := UiRowBuilder.label("%d" % buy_unit, 13, Palette.TEXT_DIM)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	# The court can only sell what its own production runs leave behind, and the
	# cap is a readout on the page, not a hover: a phone player must see why the
	# Offer is dead (wiki: world-market § Trade orders — the sellable readout;
	# REQ-P1-05, REQ-P5-05).
	var sellable: int = maxi(held - claimed, 0)
	var sell := UiRowBuilder.button("Offer", ROW_HEIGHT, 70.0)
	sell.disabled = sellable <= 0
	if claimed > 0:
		sell.tooltip_text = "%d %s claimed by production — %d sellable at %d ducats" % [
			claimed, CommodityCatalog.label(id), sellable, sell_unit,
		]
	else:
		sell.tooltip_text = "Offer 1 %s at %d ducats — it clears when the turn closes" % [
			CommodityCatalog.label(id), sell_unit,
		]
	sell.pressed.connect(func() -> void: trade_requested.emit(id, 1, false))
	row.add_child(sell)

	var buy := UiRowBuilder.button("Bid", ROW_HEIGHT, 70.0)
	buy.tooltip_text = "Bid 1 %s at %d ducats — it clears when the turn closes" % [
		CommodityCatalog.label(id), buy_unit
	]
	# Imports need a free hold in the home fleet (DR-20261109-03).
	if int(_cargo.get("free", -1)) == 0:
		buy.disabled = true
		buy.tooltip_text = "No cargo holds free this turn"
	buy.pressed.connect(func() -> void: trade_requested.emit(id, 1, true))
	row.add_child(buy)
	if claimed <= 0:
		return row
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	block.add_child(row)
	block.add_child(UiRowBuilder.caption(
		"%d %s claimed by production — %d sellable"
		% [claimed, CommodityCatalog.label(id), sellable],
		10, Palette.TEXT_DIM, 0.0
	))
	return block
