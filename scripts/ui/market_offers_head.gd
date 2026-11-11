class_name MarketOffersHead
extends VBoxContainer
## Filter and sort strip above the MINOR NATIONS AND TRIBES book: one chip per
## seller and per good on the table this turn, plus the row order. Presentation
## only — it hides and re-orders rows the auction already published and never
## edits the order book, so no filter can change a fill (REQ-P2-03, RUB-P2-03).
## The page owns the selection; this head renders it and emits the intent
## (REQ-P3-02). Filtering itself is the pure [method apply], so it is testable
## without a scene.

signal filters_changed(seller: int, commodity: String, sort_key: String)

const ALL_SELLERS: int = -1
const ALL_GOODS: String = ""
const SORT_SELLER: String = "seller"
const SORT_GOOD: String = "commodity"
const SORT_PRICE: String = "price"
const SORT_STOCK: String = "quantity"
const SORT_KEYS: Array[String] = [SORT_SELLER, SORT_GOOD, SORT_PRICE, SORT_STOCK]
const SORT_LABELS: Dictionary = {
	SORT_SELLER: "Seller A–Z",
	SORT_GOOD: "Good A–Z",
	SORT_PRICE: "Cheapest first",
	SORT_STOCK: "Most stock first",
}
const SORT_TIPS: Dictionary = {
	SORT_SELLER: "Group the book by court, richest books first.",
	SORT_GOOD: "Group the book by commodity, cheapest seller first.",
	SORT_PRICE: "The cheapest asking price per ton comes first.",
	SORT_STOCK: "The deepest stockpile comes first — one bid fills sooner.",
}
const CAPTION_WIDTH: float = 52.0
const CHIP_HEIGHT: float = 30.0
const CHIP_HEIGHT_TOUCH: float = 40.0

var seller: int = ALL_SELLERS
var commodity: String = ALL_GOODS
var sort_key: String = SORT_SELLER

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
	var present_sellers: Array[int] = sellers_in(offers)
	var present_goods: Array[String] = goods_in(offers)
	var previous: Array = [seller, commodity, sort_key]
	seller = selected_seller if present_sellers.has(selected_seller) else ALL_SELLERS
	commodity = selected_good if present_goods.has(selected_good) else ALL_GOODS
	sort_key = order_key if SORT_KEYS.has(order_key) else SORT_SELLER
	_build_seller_chips(offers, present_sellers)
	_build_good_chips(offers, present_goods)
	_build_sort_chips()
	var shown: int = apply(offers, seller, commodity, sort_key).size()
	_status.text = _status_text(shown, offers.size())
	if [seller, commodity, sort_key] != previous:
		filters_changed.emit(seller, commodity, sort_key)


func _build_seller_chips(offers: Array, present: Array[int]) -> void:
	_clear_flow(_seller_flow, _seller_chips)
	var tally: Dictionary = _tally(offers, "faction")
	var total: int = _tons(tally)
	_seller_chips[ALL_SELLERS] = _chip(
		_seller_flow, _all_text("All courts", total), "Every court's book this turn.",
		_press_seller.bind(ALL_SELLERS)
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
		_seller_chips[id] = _chip(
			_seller_flow, "%s %d" % [FactionCatalog.name_of(id), _tons_of(entry)],
			"%d tons across %d offers." % [_tons_of(entry), int(entry.get("rows", 0))],
			_press_seller.bind(id)
		)
	_set_pressed(_seller_chips, seller)


func _build_good_chips(offers: Array, present: Array[String]) -> void:
	_clear_flow(_good_flow, _good_chips)
	var tally: Dictionary = _tally(offers, "commodity")
	_good_chips[ALL_GOODS] = _chip(
		_good_flow, _all_text("All goods", _tons(tally)), "Every commodity on the table.",
		_press_good.bind(ALL_GOODS)
	)
	for id: String in present:
		var entry: Dictionary = tally.get(id, {})
		_good_chips[id] = _chip(
			_good_flow, "%s %d" % [CommodityCatalog.label(id), _tons_of(entry)],
			"%d tons across %d sellers." % [_tons_of(entry), int(entry.get("rows", 0))],
			_press_good.bind(id)
		)
	_set_pressed(_good_chips, commodity)


func _build_sort_chips() -> void:
	_clear_flow(_sort_flow, _sort_chips)
	for key: String in SORT_KEYS:
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
	seller = id if _seller_chips.has(id) else ALL_SELLERS
	_set_pressed(_seller_chips, seller)
	filters_changed.emit(seller, commodity, sort_key)


func _press_good(id: String) -> void:
	commodity = id if _good_chips.has(id) else ALL_GOODS
	_set_pressed(_good_chips, commodity)
	filters_changed.emit(seller, commodity, sort_key)


func _press_sort(key: String) -> void:
	sort_key = key if SORT_KEYS.has(key) else SORT_SELLER
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


## The rows on screen: the published book, narrowed to one seller and/or one
## good, in the requested order. Rows are the auction's own dictionaries and are
## returned untouched, so a filter can never rewrite a bid or a price.
static func apply(
	offers: Array,
	selected_seller: int = ALL_SELLERS,
	selected_good: String = ALL_GOODS,
	order_key: String = SORT_SELLER
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw: Variant in offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		if selected_seller != ALL_SELLERS and int(row.get("faction", ALL_SELLERS)) != selected_seller:
			continue
		if not selected_good.is_empty() and String(row.get("commodity", "")) != selected_good:
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return MarketOffersHead._sorts_before(a, b, order_key)
	)
	return rows


## Total order so the book never reshuffles between identical renders: every
## branch ends on the row id.
static func _sorts_before(a: Dictionary, b: Dictionary, order_key: String) -> bool:
	match order_key:
		SORT_GOOD:
			var a_label: String = CommodityCatalog.label(String(a.get("commodity", ""))).to_lower()
			var b_label: String = CommodityCatalog.label(String(b.get("commodity", ""))).to_lower()
			if a_label != b_label:
				return a_label < b_label
			var a_price: int = int(a.get("unit_price", 0))
			var b_price: int = int(b.get("unit_price", 0))
			if a_price != b_price:
				return a_price < b_price
		SORT_PRICE:
			var a_ask: int = int(a.get("unit_price", 0))
			var b_ask: int = int(b.get("unit_price", 0))
			if a_ask != b_ask:
				return a_ask < b_ask
			var a_stock: int = int(a.get("quantity", 0))
			var b_stock: int = int(b.get("quantity", 0))
			if a_stock != b_stock:
				return a_stock > b_stock
		SORT_STOCK:
			var a_left: int = int(a.get("quantity", 0))
			var b_left: int = int(b.get("quantity", 0))
			if a_left != b_left:
				return a_left > b_left
			var a_cost: int = int(a.get("unit_price", 0))
			var b_cost: int = int(b.get("unit_price", 0))
			if a_cost != b_cost:
				return a_cost < b_cost
		_:
			return _by_seller(a, b)
	return _by_seller(a, b)


## Court A–Z, richest book first within a court (the published book's intent).
static func _by_seller(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = FactionCatalog.name_of(int(a.get("faction", ALL_SELLERS))).to_lower()
	var b_name: String = FactionCatalog.name_of(int(b.get("faction", ALL_SELLERS))).to_lower()
	if a_name != b_name:
		return a_name < b_name
	var a_stock: int = int(a.get("quantity", 0))
	var b_stock: int = int(b.get("quantity", 0))
	if a_stock != b_stock:
		return a_stock > b_stock
	var a_good: String = CommodityCatalog.label(String(a.get("commodity", ""))).to_lower()
	var b_good: String = CommodityCatalog.label(String(b.get("commodity", ""))).to_lower()
	if a_good != b_good:
		return a_good < b_good
	return String(a.get("id", "")) < String(b.get("id", ""))


## Courts with something on the table, ascending id: the seller chips.
static func sellers_in(offers: Array) -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var id: int = int((raw as Dictionary).get("faction", ALL_SELLERS))
		if not out.has(id):
			out.append(id)
	out.sort()
	return out


## Goods on the table in catalogue order (food, raw, manufactured), so the chip
## strip reads like the price rows above it.
static func goods_in(offers: Array) -> Array[String]:
	var present: Dictionary = {}
	for raw: Variant in offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var id: String = String((raw as Dictionary).get("commodity", ""))
		if not id.is_empty():
			present[id] = true
	var out: Array[String] = []
	for id: String in CommodityCatalog.all_ids():
		if present.has(id):
			out.append(id)
			present.erase(id)
	var leftovers: Array[String] = []
	for id: Variant in present.keys():
		leftovers.append(String(id))
	leftovers.sort()
	out.append_array(leftovers)
	return out


static func _tally(offers: Array, key: String) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in offers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var id: Variant = row.get(key, null)
		if id == null:
			continue
		if not out.has(id):
			out[id] = {"tons": 0, "rows": 0}
		var entry: Dictionary = out[id]
		entry["tons"] = _tons_of(entry) + int(row.get("quantity", 0))
		entry["rows"] = int(entry.get("rows", 0)) + 1
	return out


static func _tons(entry_book: Dictionary) -> int:
	var total: int = 0
	for entry: Variant in entry_book.values():
		total += _tons_of(entry as Dictionary)
	return total


static func _tons_of(entry: Dictionary) -> int:
	return maxi(int(entry.get("tons", 0)), 0)
