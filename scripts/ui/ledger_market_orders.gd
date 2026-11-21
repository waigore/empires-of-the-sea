class_name LedgerMarketOrders
extends RefCounted
## The MARKET tab's staged bids and offers: what the court will take to the
## turn-end auction. One builder mounts the block so the page never owns the
## reading (wiki: world-market § Order persistence; REQ-P3-01). A carry-forward
## row is shown but cannot be withdrawn.

const ROW_HEIGHT: float = 38.0


## Mounts the orders block under `parent`. `on_cancel` takes the order id when
## the court withdraws a still-open row.
static func mount(
	parent: Control,
	market: WorldMarket,
	viewer: int,
	on_cancel: Callable
) -> void:
	if parent == null or market == null:
		return
	var orders: Array[MarketOrder] = market.book.orders_for(viewer)
	UiRowBuilder.spacer(parent, 6.0)
	var title := UiRowBuilder.label("YOUR ORDERS", 11, Palette.GOLD_DIM)
	title.tooltip_text = "Bids and offers clear together when the turn closes."
	parent.add_child(title)
	if orders.is_empty():
		var none := UiRowBuilder.label(
			"No orders staged — Buy and Sell enter next turn's auction.", 11,
			Palette.TEXT_DIM
		)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(240, 0)
		parent.add_child(none)
		return
	for order: MarketOrder in orders:
		parent.add_child(row(order, market, viewer, on_cancel))


## One staged order as a row: side, good, remaining tons, notional at the
## viewer's terms, and Cancel when the book still holds the submission. Tests
## and tooling build this instead of reaching into the page (REQ-P3-02).
static func row(
	order: MarketOrder,
	market: WorldMarket,
	viewer: int,
	on_cancel: Callable = Callable()
) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	var side: String = "BID" if order.is_bid() else "OFFER"
	row.add_child(UiRowBuilder.caption(side, 10, Palette.GOLD_PALE, 46.0))
	row.add_child(CommodityIcons.cell(order.commodity, 96.0, 13))
	var quantity := UiRowBuilder.label("%d" % order.remaining(), 13, Palette.GOLD_PALE)
	quantity.custom_minimum_size = Vector2(38, 0)
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(quantity)
	var price: int = (
		market.buy_price(order.commodity, viewer) if order.is_bid()
		else market.sell_price(order.commodity, viewer)
	)
	var notional := UiRowBuilder.label("%d" % (price * order.remaining()), 12, Palette.TEXT_DIM)
	notional.custom_minimum_size = Vector2(52, 0)
	notional.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(notional)
	if market.book.submitted.has(order) and on_cancel.is_valid():
		var cancel := UiRowBuilder.button("Cancel", ROW_HEIGHT, 62.0)
		cancel.pressed.connect(func() -> void: on_cancel.call(order.id))
		row.add_child(cancel)
	return row
