class_name LedgerOffers
extends VBoxContainer
## The MINOR NATIONS & TRIBES book on the market tab: the seller/good/sort strip,
## the reading it selects and the rows it narrows. The crown's own market — cargo
## banner, trade terms, staged orders, last clearing and the world price rows —
## is LedgerMarket's; this plate answers for the direct offers alone, so the
## chip selection and the rows it hides keep one owner (REQ-P3-01, REQ-P3-02).
##
## Direct offers sit above the world price rows: who sells, what is left, and
## what the court asks. The chips are presentation only — they narrow the book
## the auction already published and never stage or edit an order (REQ-P2-03).
## An empty book still says so, so the section never looks broken
## (REQ-P1-07, REQ-P5-03).

signal offer_requested(offer_id: String, quantity: int)

const ROW_HEIGHT: float = 38.0
const OFFER_HEADER: String = "MINOR NATIONS & TRIBES"

## This turn's Minor/Tribe book, kept so a chip press redraws rows only.
var _offers: Array = []
## Home-fleet holds and this turn's laden imports, from the controller.
var _cargo: Dictionary = {}
## The seller and good chips (and the row order) narrow the published book.
var _seller_filter: int = MarketOffersHead.ALL_SELLERS
var _good_filter: String = MarketOffersHead.ALL_GOODS
var _offer_sort: String = MarketOffersHead.SORT_SELLER
var _offers_head: MarketOffersHead = null
var _offers_box: VBoxContainer = null
## A phone viewport wants thumb-sized chips; remembered for the next rebuild.
var _compact: bool = false


func _init() -> void:
	# The plate stands inside the market page's column, so its own lines keep
	# that column's gap instead of adding a second one.
	add_theme_constant_override("separation", 4)


## `offers` is this turn's Minor/Tribe book, rows as in `MinorMarket.emit`;
## `cargo` is the home fleet's holds, so a full hold locks the Bid button.
func fill(offers: Array, cargo: Dictionary, compact: bool = false) -> void:
	_offers = offers
	_cargo = cargo
	_compact = compact
	_offers_head = null
	_offers_box = null
	UiRowBuilder.clear(self)
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
		return
	_offers_head = MarketOffersHead.new()
	_offers_head.filters_changed.connect(_on_offers_filtered)
	_offers_head.set_compact(_compact)
	add_child(_offers_head)
	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override("separation", 4)
	add_child(_offers_box)
	_offers_head.render(offers, _seller_filter, _good_filter, _offer_sort)
	_render_offers()


## Rebuilds only the offer rows, so a chip press never re-runs the rest of the
## page and the pressed chip and the list always move together (REQ-P5-05).
func _render_offers() -> void:
	if _offers_box == null:
		return
	UiRowBuilder.clear(_offers_box)
	var rows: Array[Dictionary] = visible_offers()
	if rows.is_empty():
		var none := UiRowBuilder.label("No offers match this filter.", 12, Palette.TEXT_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(240, 0)
		_offers_box.add_child(none)
		return
	var header := UiRowBuilder.row(0.0)
	header.add_child(UiRowBuilder.caption("SELLER", 10, Palette.TEXT_DIM, 96.0))
	header.add_child(UiRowBuilder.caption("GOOD", 10, Palette.TEXT_DIM, 84.0))
	header.add_child(UiRowBuilder.caption("LEFT", 10, Palette.TEXT_DIM, 40.0))
	header.add_child(UiRowBuilder.caption("PRICE", 10, Palette.TEXT_DIM, 46.0))
	_offers_box.add_child(header)
	for row: Dictionary in rows:
		_offers_box.add_child(_offer_row(row))


## The head's chips are an intent, not a rule: the plate only remembers which
## slice of the published book to draw.
func _on_offers_filtered(seller: int, good: String, sort_key: String) -> void:
	_seller_filter = seller
	_good_filter = good
	_offer_sort = sort_key
	_render_offers()


## Rows the strip is drawing right now, in display order (tests and tooling use
## this instead of reaching into the offer box; REQ-P3-02).
func visible_offers() -> Array[Dictionary]:
	return MarketOffersHead.apply(_offers, _seller_filter, _good_filter, _offer_sort)


## The seller/good/sort chips, for tests and the mobile layout audit.
func offer_filters() -> Dictionary:
	return _offers_head.filter_buttons() if _offers_head != null else {}


## The Bid buttons the rows are drawing, in display order, for tests and the
## mobile layout audit (REQ-P3-02).
func offer_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _offers_box == null:
		return out
	for node: Node in _offers_box.find_children("*", "Button", true, false):
		out.append(node as Button)
	return out


## Thumb-sized chips on a phone viewport (REQ-P5-07).
func set_compact(compact: bool) -> void:
	_compact = compact
	if _offers_head != null:
		_offers_head.set_compact(compact)


## Drops the reading back to the whole book. The page keeps its plate across a
## repaint, so a chip a case pressed would otherwise hide the next case's rows.
func reset_filters() -> void:
	if _offers_head == null:
		return
	# The head re-presses the chips and says so through `filters_changed`, so the
	# reading here never disagrees with what the strip shows.
	_offers_head.render(
		_offers, MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)


func _offer_row(offer: Dictionary) -> Control:
	var row := UiRowBuilder.row(ROW_HEIGHT)
	var seller: int = int(offer.get("faction", -1))
	var commodity: String = String(offer.get("commodity", ""))
	var left: int = int(offer.get("quantity", 0))
	var ask: int = int(offer.get("unit_price", 0))

	row.add_child(
		UiRowBuilder.caption(FactionCatalog.name_of(seller), 13, FactionCatalog.color_of(seller), 96.0)
	)
	row.add_child(CommodityIcons.cell(commodity, 84.0, 13))
	var left_label := UiRowBuilder.label("%d" % left, 13, Palette.GOLD_PALE)
	left_label.custom_minimum_size = Vector2(40, 0)
	left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left_label)

	var ask_label := UiRowBuilder.label("%d" % ask, 13, Palette.GOLD_PALE)
	ask_label.custom_minimum_size = Vector2(46, 0)
	ask_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(ask_label)

	var buy := UiRowBuilder.button("Bid", ROW_HEIGHT, 54.0)
	# The ask is what the clearing charges this pair — the published price with
	# the crown's terms and any subsidy step — so the tooltip names it rather
	# than the untaxed price (wiki: world-market § Subsidy price adjustment).
	buy.tooltip_text = "Bid 1 %s at the ask of %d — it clears when the turn closes" % [
		CommodityCatalog.label(commodity), ask
	]
	# Imports need a free hold in the home fleet (DR-20261109-03).
	if int(_cargo.get("free", -1)) == 0:
		buy.disabled = true
		buy.tooltip_text = "No cargo holds free this turn"
	var row_id: String = String(offer.get("id", ""))
	buy.pressed.connect(func() -> void: offer_requested.emit(row_id, 1))
	row.add_child(buy)
	return row
