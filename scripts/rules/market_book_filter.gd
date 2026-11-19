class_name MarketBookFilter
extends RefCounted
## The published book's reading: which rows a chip strip shows, in what order,
## and the per-court and per-good tallies its chips print (wiki: world-market
## § Trade orders). Pure rules — no Node, no scene, no RNG (REQ-P3-03).
##
## The strip that draws the chips is MarketOffersHead's; it asks here for the
## rows and the tallies, so a filter can never rewrite a bid or a price
## (REQ-P2-03, RUB-P2-03). The sentinels and sort keys are this reading's
## vocabulary, so the strip, the page and the tests name one set (REQ-P3-01).

const ALL_SELLERS: int = -1
const ALL_GOODS: String = ""
const SORT_SELLER: String = "seller"
const SORT_GOOD: String = "commodity"
const SORT_PRICE: String = "price"
const SORT_STOCK: String = "quantity"
const SORT_KEYS: Array[String] = [SORT_SELLER, SORT_GOOD, SORT_PRICE, SORT_STOCK]


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
		return _sorts_before(a, b, order_key)
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


## Tons and offer count per seller (`key` = "faction") or per good
## (`key` = "commodity"), for the chip captions and their tooltips.
static func tally(offers: Array, key: String) -> Dictionary:
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
		entry["tons"] = tons_of(entry) + int(row.get("quantity", 0))
		entry["rows"] = int(entry.get("rows", 0)) + 1
	return out


## Every ton a tally holds, for the "All courts" / "All goods" chip.
static func tons(entry_book: Dictionary) -> int:
	var total: int = 0
	for entry: Variant in entry_book.values():
		total += tons_of(entry as Dictionary)
	return total


static func tons_of(entry: Dictionary) -> int:
	return maxi(int(entry.get("tons", 0)), 0)
