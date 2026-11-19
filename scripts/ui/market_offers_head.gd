class_name MarketOffersHead
extends VBoxContainer
## Filter and sort strip above the MINOR NATIONS AND TRIBES book: one chip per
## seller and per good on the table this turn, plus the row order. Presentation
## only — it hides and re-orders rows the auction already published and never
## edits the order book, so no filter can change a fill (REQ-P2-03, RUB-P2-03).
## The page owns the selection; this head renders it and emits the intent
## (REQ-P3-02). The reading itself — which rows, in what order, and the tallies
## the chips print — is MarketBookFilter's pure rules (REQ-P3-03).

signal filters_changed(seller: int, commodity: String, sort_key: String)

const SORT_LABELS: Dictionary = {
	MarketBookFilter.SORT_SELLER: "Seller A–Z",
	MarketBookFilter.SORT_GOOD: "Good A–Z",
	MarketBookFilter.SORT_PRICE: "Cheapest first",
	MarketBookFilter.SORT_STOCK: "Most stock first",
}
const SORT_TIPS: Dictionary = {
	MarketBookFilter.SORT_SELLER: "Group the book by court, richest books first.",
	MarketBookFilter.SORT_GOOD: "Group the book by commodity, cheapest seller first.",
	MarketBookFilter.SORT_PRICE: "The cheapest asking price per ton comes first.",
	MarketBookFilter.SORT_STOCK: "The deepest stockpile comes first — one bid fills sooner.",
}
const CAPTION_WIDTH: float = 52.0
const CHIP_HEIGHT: float = 30.0
const CHIP_HEIGHT_TOUCH: float = 40.0

var seller: int = MarketBookFilter.ALL_SELLERS
var commodity: String = MarketBookFilter.ALL_GOODS
var sort_key: String = MarketBookFilter.SORT_SELLER

var _seller_flow: HBoxContainer = null
var _good_flow: HBoxContainer = null
var _sort_flow: HBoxContainer = null
var _seller_chips: Dictionary = {}
var _good_chips: Dictionary = {}
var _sort_chips: Dictionary = {}
var _status: Label = null


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_seller_flow = _chip_row("SELLER")
	_good_flow = _chip_row("GOOD")
	_sort_flow = _chip_row("SORT")
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(240, 0)
	add_child(_status)


## One caption plus a horizontally scrolling chip strip, so a long book never
## widens the ledger (REQ-P1-05). Returns the flow the chips are built into.
func _chip_row(caption_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var caption := Label.new()
	caption.text = caption_text
	caption.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_color", Palette.TEXT_DIM)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 4)
	scroll.add_child(flow)
	return flow


## Draws the strip from this turn's book. A selection the new book no longer
## carries falls back to All and says so through `filters_changed`, so the
## ledger's own state never disagrees with what is on screen.
func render(
	offers: Array, selected_seller: int, selected_good: String, order_key: String
) -> void:
	var present_sellers: Array[int] = MarketBookFilter.sellers_in(offers)
	var present_goods: Array[String] = MarketBookFilter.goods_in(offers)
	var previous: Array = [seller, commodity, sort_key]
	seller = (
		selected_seller if present_sellers.has(selected_seller)
		else MarketBookFilter.ALL_SELLERS
	)
	commodity = (
		selected_good if present_goods.has(selected_good) else MarketBookFilter.ALL_GOODS
	)
	sort_key = (
		order_key if MarketBookFilter.SORT_KEYS.has(order_key)
		else MarketBookFilter.SORT_SELLER
	)
	_build_seller_chips(offers, present_sellers)
	_build_good_chips(offers, present_goods)
	_build_sort_chips()
	var shown: int = MarketBookFilter.apply(offers, seller, commodity, sort_key).size()
	_status.text = _status_text(shown, offers.size())
	if [seller, commodity, sort_key] != previous:
		filters_changed.emit(seller, commodity, sort_key)


func _build_seller_chips(offers: Array, present: Array[int]) -> void:
	_clear_flow(_seller_flow, _seller_chips)
	var tally: Dictionary = MarketBookFilter.tally(offers, "faction")
	var total: int = MarketBookFilter.tons(tally)
	_seller_chips[MarketBookFilter.ALL_SELLERS] = _chip(
		_seller_flow, _all_text("All courts", total), "Every court's book this turn.",
		_press_seller.bind(MarketBookFilter.ALL_SELLERS)
	)
	var ordered: Array[int] = present.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var left: String = FactionCatalog.name_of(a).to_lower()
		var right: String = FactionCatalog.name_of(b).to_lower()
		if left != right:
			return left < right
		return a < b
	)
	for id: int in ordered:
		var entry: Dictionary = tally.get(id, {})
		var tons: int = MarketBookFilter.tons_of(entry)
		var count: int = int(entry.get("rows", 0))
		_seller_chips[id] = _chip(
			_seller_flow, "%s %d" % [FactionCatalog.name_of(id), tons],
			"%d tons across %d offers." % [tons, count],
			_press_seller.bind(id)
		)
	_set_pressed(_seller_chips, seller)


func _build_good_chips(offers: Array, present: Array[String]) -> void:
	_clear_flow(_good_flow, _good_chips)
	var tally: Dictionary = MarketBookFilter.tally(offers, "commodity")
	_good_chips[MarketBookFilter.ALL_GOODS] = _chip(
		_good_flow, _all_text("All goods", MarketBookFilter.tons(tally)),
		"Every commodity on the table.", _press_good.bind(MarketBookFilter.ALL_GOODS)
	)
	for id: String in present:
		var entry: Dictionary = tally.get(id, {})
		var tons: int = MarketBookFilter.tons_of(entry)
		var count: int = int(entry.get("rows", 0))
		_good_chips[id] = _chip(
			_good_flow, "%s %d" % [CommodityCatalog.label(id), tons],
			"%d tons across %d sellers." % [tons, count],
			_press_good.bind(id)
		)
	_set_pressed(_good_chips, commodity)


func _build_sort_chips() -> void:
	_clear_flow(_sort_flow, _sort_chips)
	for key: String in MarketBookFilter.SORT_KEYS:
		_sort_chips[key] = _chip(
			_sort_flow, String(SORT_LABELS.get(key, key)), String(SORT_TIPS.get(key, "")),
			_press_sort.bind(key)
		)
	_set_pressed(_sort_chips, sort_key)


func _chip(flow: HBoxContainer, text: String, tip: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(handler)
	flow.add_child(button)
	return button


func _all_text(label: String, tons: int) -> String:
	return label if tons <= 0 else "%s %d" % [label, tons]


func _press_seller(id: int) -> void:
	seller = id if _seller_chips.has(id) else MarketBookFilter.ALL_SELLERS
	_set_pressed(_seller_chips, seller)
	filters_changed.emit(seller, commodity, sort_key)


func _press_good(id: String) -> void:
	commodity = id if _good_chips.has(id) else MarketBookFilter.ALL_GOODS
	_set_pressed(_good_chips, commodity)
	filters_changed.emit(seller, commodity, sort_key)


func _press_sort(key: String) -> void:
	sort_key = key if MarketBookFilter.SORT_KEYS.has(key) else MarketBookFilter.SORT_SELLER
	_set_pressed(_sort_chips, sort_key)
	filters_changed.emit(seller, commodity, sort_key)


## Chip lookup for tests and the mobile layout audit (REQ-P5-07).
func filter_buttons() -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in _seller_chips.keys():
		out["seller:%d" % int(key)] = _seller_chips[key]
	for key: Variant in _good_chips.keys():
		out["good:%s" % String(key)] = _good_chips[key]
	for key: Variant in _sort_chips.keys():
		out["sort:%s" % String(key)] = _sort_chips[key]
	return out


func set_compact(compact: bool) -> void:
	var height: float = CHIP_HEIGHT_TOUCH if compact else CHIP_HEIGHT
	for chips: Dictionary in [_seller_chips, _good_chips, _sort_chips]:
		for chip: Button in chips.values():
			chip.custom_minimum_size.y = height


func _clear_flow(flow: HBoxContainer, chips: Dictionary) -> void:
	chips.clear()
	if flow == null:
		return
	for child: Node in flow.get_children():
		flow.remove_child(child)
		child.queue_free()


func _set_pressed(chips: Dictionary, key: Variant) -> void:
	for chip_key: Variant in chips.keys():
		(chips[chip_key] as Button).set_pressed_no_signal(chip_key == key)


func _status_text(shown: int, total: int) -> String:
	if total <= 0:
		return ""
	var count: String = (
		"%d of %d offers" % [shown, total] if shown != total else "%d offers" % total
	)
	return "%s  ·  %s" % [count, String(SORT_LABELS.get(sort_key, ""))]

