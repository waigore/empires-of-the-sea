class_name LedgerMarket
extends VBoxContainer
## MARKET tab of the ledger: the cargo-hold banner and one Buy/Sell row per
## commodity. A full hold or an unknown fleet locks imports; every press is an
## intent and the controller decides (wiki: ships-and-naval; REQ-P2-03).

signal trade_requested(commodity: String, quantity: int, is_buy: bool)

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


func fill(economy: PlayerEconomy, market: WorldMarket, cargo: Dictionary) -> void:
	_economy = economy
	_market = market
	_cargo = cargo
	UiRowBuilder.clear(self)
	_add_cargo_banner()
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


func _market_row(id: String, held: int) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	row.add_child(UiRowBuilder.caption(CommodityCatalog.label(id), 14, Palette.TEXT, 132.0))

	var qty := UiRowBuilder.label("%d" % held, 14, Palette.GOLD_PALE)
	qty.custom_minimum_size = Vector2(44, 0)
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(qty)

	var unit_price: int = _market.price(id)
	var price := UiRowBuilder.label("%d" % unit_price, 13, Palette.TEXT_DIM)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)

	var sell := UiRowBuilder.button("Sell", ROW_HEIGHT, 70.0)
	sell.disabled = held <= 0
	sell.tooltip_text = "Sell 1 %s for %d ducats" % [CommodityCatalog.label(id), unit_price]
	sell.pressed.connect(func() -> void: trade_requested.emit(id, 1, false))
	row.add_child(sell)

	var buy := UiRowBuilder.button("Buy", ROW_HEIGHT, 70.0)
	buy.tooltip_text = "Buy 1 %s for %d ducats" % [CommodityCatalog.label(id), unit_price]
	# Imports need a free hold in the home fleet (DR-20261109-03).
	if int(_cargo.get("free", -1)) == 0:
		buy.disabled = true
		buy.tooltip_text = "No cargo holds free this turn"
	buy.pressed.connect(func() -> void: trade_requested.emit(id, 1, true))
	row.add_child(buy)
	return row
