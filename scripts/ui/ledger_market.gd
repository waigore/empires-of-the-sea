class_name LedgerMarket
extends VBoxContainer
## MARKET tab of the ledger: the cargo-hold banner and one Buy/Sell row per
## commodity. A full hold or an unknown fleet locks imports; every press is an
## intent and the controller decides (wiki: ships-and-naval; REQ-P2-03).

signal trade_requested(commodity: String, quantity: int, is_buy: bool)
signal offer_requested(offer_id: String, quantity: int)
signal cancel_requested(order_id: String)

const ROW_HEIGHT: float = 38.0
const CATEGORIES: Array = [
	CommodityCatalog.Category.FOOD,
	CommodityCatalog.Category.RAW,
	CommodityCatalog.Category.MANUFACTURED,
]
const OFFER_HEADER: String = "MINOR NATIONS & TRIBES"

var _economy: PlayerEconomy = null
var _market: WorldMarket = null
## Home-fleet holds and this turn's laden imports, from the controller.
var _cargo: Dictionary = {}


## `offers` is this turn's Minor/Tribe book, rows as in `MinorMarket.emit`.
func fill(
	economy: PlayerEconomy, market: WorldMarket, cargo: Dictionary, offers: Array = []
) -> void:
	_economy = economy
	_market = market
	_cargo = cargo
	UiRowBuilder.clear(self)
	_add_cargo_banner()
	_add_terms_banner()
	_add_staged()
	_add_deals()
	_add_offers(offers)
	var header := UiRowBuilder.row(0.0)
	header.add_child(UiRowBuilder.caption("COMMODITY", 10, Palette.TEXT_DIM, 132.0))
	header.add_child(UiRowBuilder.caption("HAVE", 10, Palette.TEXT_DIM, 44.0))
	header.add_child(UiRowBuilder.caption("PRICE", 10, Palette.TEXT_DIM, 44.0))
	add_child(header)
	for category: Variant in CATEGORIES:
		for id: String in CommodityCatalog.ids_in(category):
			add_child(_market_row(id, economy.quantity(id)))
	UiRowBuilder.spacer(self)


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
		FactionCatalog.PLAYER_FACTION
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
	row.add_child(
		UiRowBuilder.caption(CommodityCatalog.label(order.commodity), 13, Palette.TEXT, 96.0)
	)
	var quantity := UiRowBuilder.label("%d" % order.remaining(), 13, Palette.GOLD_PALE)
	quantity.custom_minimum_size = Vector2(38, 0)
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(quantity)
	var price: int = (
		_market.buy_price(order.commodity) if order.is_bid()
		else _market.sell_price(order.commodity)
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
## (wiki: world-market § Trade orders; REQ-P5-05).
func _add_deals() -> void:
	if _market == null or _market.book.last_deals.is_empty():
		return
	var mine: Array[Dictionary] = []
	for raw: Variant in _market.book.last_deals:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = raw
		var buyer: int = int(deal.get("buyer", -2))
		var seller: int = int(deal.get("seller", -2))
		if buyer == FactionCatalog.PLAYER_FACTION or seller == FactionCatalog.PLAYER_FACTION:
			mine.append(deal)
	if mine.is_empty():
		return
	UiRowBuilder.spacer(self, 4.0)
	add_child(UiRowBuilder.label("LAST CLEARING", 11, Palette.GOLD_DIM))
	for deal: Dictionary in mine.slice(0, 4):
		add_child(UiRowBuilder.label(_deal_line(deal), 12, Palette.TEXT_DIM))
	if mine.size() > 4:
		add_child(UiRowBuilder.label(
			"+%d more deals" % (mine.size() - 4), 11, Palette.TEXT_DIM
		))


func _deal_line(deal: Dictionary) -> String:
	var quantity: int = int(deal.get("quantity", 0))
	var commodity: String = CommodityCatalog.label(String(deal.get("commodity", "")))
	var price: int = int(deal.get("price", 0))
	var buyer: int = int(deal.get("buyer", -2))
	var seller: int = int(deal.get("seller", -2))
	var other: String = "the world market" if seller < 0 else FactionCatalog.name_of(seller)
	if buyer == FactionCatalog.PLAYER_FACTION:
		other = "the world market" if seller < 0 else FactionCatalog.name_of(seller)
		return "Bought %d %s from %s at %d" % [quantity, commodity, other, price]
	other = "the world market" if buyer < 0 else FactionCatalog.name_of(buyer)
	return "Sold %d %s to %s at %d" % [quantity, commodity, other, price]


## Direct offers sit above the world price rows: who sells, what is left, and
## what the court asks. An empty book still says so, so the section never looks
## broken (REQ-P1-07, REQ-P5-03).
func _add_offers(offers: Array) -> void:
	UiRowBuilder.spacer(self, 6.0)
	var title := UiRowBuilder.label(OFFER_HEADER, 11, Palette.GOLD_DIM)
	title.tooltip_text = "Direct purchases from the Minor Nations and Tribes, below the world price."
	add_child(title)
	var hint := UiRowBuilder.label(
		"The courts' harvest enters the turn-end auction at the published price.", 11,
		Palette.TEXT_DIM
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 0)
	add_child(hint)
	if offers.is_empty():
		var none := UiRowBuilder.label(
			"No court has goods for sale this turn.", 12, Palette.TEXT_DIM
		)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(240, 0)
		add_child(none)
		UiRowBuilder.spacer(self, 4.0)
		return
	var header := UiRowBuilder.row(0.0)
	header.add_child(UiRowBuilder.caption("SELLER", 10, Palette.TEXT_DIM, 96.0))
	header.add_child(UiRowBuilder.caption("GOOD", 10, Palette.TEXT_DIM, 84.0))
	header.add_child(UiRowBuilder.caption("LEFT", 10, Palette.TEXT_DIM, 40.0))
	header.add_child(UiRowBuilder.caption("PRICE", 10, Palette.TEXT_DIM, 46.0))
	add_child(header)
	for raw: Variant in offers:
		if typeof(raw) == TYPE_DICTIONARY:
			add_child(_offer_row(raw as Dictionary))
	UiRowBuilder.spacer(self, 4.0)


func _offer_row(offer: Dictionary) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	var seller: int = int(offer.get("faction", -1))
	var commodity: String = String(offer.get("commodity", ""))
	var left: int = int(offer.get("quantity", 0))
	var ask: int = int(offer.get("unit_price", 0))
	var world_price: int = _market.price(commodity) if _market != null else ask

	row.add_child(
		UiRowBuilder.caption(FactionCatalog.name_of(seller), 13, FactionCatalog.color_of(seller), 96.0)
	)
	row.add_child(UiRowBuilder.caption(CommodityCatalog.label(commodity), 13, Palette.TEXT, 84.0))

	var left_label := UiRowBuilder.label("%d" % left, 13, Palette.GOLD_PALE)
	left_label.custom_minimum_size = Vector2(40, 0)
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left_label)

	var ask_label := UiRowBuilder.label("%d" % ask, 13, Palette.GOLD_PALE)
	ask_label.custom_minimum_size = Vector2(46, 0)
	ask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(ask_label)

	var buy := UiRowBuilder.button("Bid", ROW_HEIGHT, 54.0)
	buy.tooltip_text = "Bid 1 %s at the published price of %d — it clears when the turn closes" % [
		CommodityCatalog.label(commodity), world_price
	]
	# Imports need a free hold in the home fleet (DR-20261109-03).
	if int(_cargo.get("free", -1)) == 0:
		buy.disabled = true
		buy.tooltip_text = "No cargo holds free this turn"
	var row_id: String = String(offer.get("id", ""))
	buy.pressed.connect(func() -> void: offer_requested.emit(row_id, 1))
	row.add_child(buy)
	return row


## One plain sentence for the court's trade diplomacy, so an adjusted price is
## never a mystery (wiki: world-market § FTP; REQ-P2-03).
func _add_terms_banner() -> void:
	if _market == null:
		return
	var terms: Dictionary = _market.terms_for(FactionCatalog.PLAYER_FACTION)
	if terms.is_empty():
		return
	var buy: Dictionary = terms.get("buy", {})
	var sell: Dictionary = terms.get("sell", {})
	var buy_rate: float = float(buy.get("*", 1.0))
	var sell_rate: float = float(sell.get("*", 1.0))
	var text: String = "Trade terms: imports at %d%% and exports at %d%% of the world price." % [
		roundi(buy_rate * 100.0), roundi(sell_rate * 100.0)
	]
	if _has_commodity_rates(buy) or _has_commodity_rates(sell):
		text += " Subsidised courts set their own commodity rates."
	var banner := UiRowBuilder.label(text, 12, Palette.GOLD_PALE)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size = Vector2(240, 0)
	add_child(banner)


func _has_commodity_rates(book: Dictionary) -> bool:
	for key: Variant in book.keys():
		if String(key) != "*":
			return true
	return false


func _market_row(id: String, held: int) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(UiRowBuilder.caption(CommodityCatalog.label(id), 14, Palette.TEXT, 132.0))

	var qty := UiRowBuilder.label("%d" % held, 14, Palette.GOLD_PALE)
	qty.custom_minimum_size = Vector2(44, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var buy_unit: int = _market.buy_price(id)
	var sell_unit: int = _market.sell_price(id)
	var price := UiRowBuilder.label("%d" % buy_unit, 13, Palette.TEXT_DIM)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	var sell := UiRowBuilder.button("Offer", ROW_HEIGHT, 70.0)
	sell.disabled = held <= 0
	sell.tooltip_text = "Offer 1 %s at %d ducats — it clears when the turn closes" % [
		CommodityCatalog.label(id), sell_unit
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
	return row
