extends GdToolsTest
## MARKET tab offer book: seller/good filters and the row order (REQ-P2-03,
## REQ-P5-03). Pure presentation over the published book — no map screen.


## Venice (7) sells the richest grain book, Aztec (9) one lot of timber, Maya
## (11) a smaller grain lot, so name order and id order differ on purpose.
func _book() -> Array:
	return [
		{
			"id": "9:timber",
			"faction": 9,
			"commodity": "timber",
			"quantity": 3,
			"unit_price": 30,
		},
		{
			"id": "7:grain",
			"faction": 7,
			"commodity": "grain",
			"quantity": 5,
			"unit_price": 12,
		},
		{
			"id": "7:timber",
			"faction": 7,
			"commodity": "timber",
			"quantity": 1,
			"unit_price": 28,
		},
		{
			"id": "11:grain",
			"faction": 11,
			"commodity": "grain",
			"quantity": 2,
			"unit_price": 12,
		},
	]


func _ids(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(row["id"]))
	return out


func test_the_seller_filter_narrows_the_book_to_one_court() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), 7, MarketOffersHead.ALL_GOODS, MarketOffersHead.SORT_SELLER
	)
	assert_eq(_ids(rows), ["7:grain", "7:timber"])


func test_the_good_filter_narrows_the_book_to_one_commodity() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, "grain", MarketOffersHead.SORT_SELLER
	)
	assert_eq(rows.size(), 2)
	for row: Dictionary in rows:
		assert_eq(String(row["commodity"]), "grain")


func test_both_filters_narrow_together_and_can_empty_the_book() -> void:
	var narrowed: Array[Dictionary] = MarketOffersHead.apply(
		_book(), 9, "timber", MarketOffersHead.SORT_SELLER
	)
	assert_eq(_ids(narrowed), ["9:timber"])
	assert_eq(
		MarketOffersHead.apply(_book(), 9, "grain", MarketOffersHead.SORT_SELLER).size(), 0
	)


## Court A–Z by name (not by id), and the richer book first inside a court.
func test_the_default_order_is_court_name_then_the_richest_book() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	assert_eq(_ids(rows), ["9:timber", "11:grain", "7:grain", "7:timber"])


func test_sorting_by_good_groups_the_commodities() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_GOOD
	)
	assert_eq(_ids(rows), ["11:grain", "7:grain", "7:timber", "9:timber"])


func test_cheapest_first_pays_less_per_ton() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_PRICE
	)
	var prices: Array[int] = []
	for row: Dictionary in rows:
		prices.append(int(row["unit_price"]))
	assert_eq(prices, [12, 12, 28, 30], "the cheapest ask leads: %s" % [_ids(rows)])


func test_most_stock_first_fills_a_bid_sooner() -> void:
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_STOCK
	)
	assert_eq(_ids(rows), ["7:grain", "9:timber", "11:grain", "7:timber"])


func test_junk_rows_are_skipped_and_the_published_book_is_never_reordered() -> void:
	var book: Array = _book()
	var published: Array = book.duplicate(true)
	book.append("not an offer")
	var rows: Array[Dictionary] = MarketOffersHead.apply(
		book, MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_GOOD
	)
	assert_eq(rows.size(), 4)
	assert_eq(book.slice(0, 4), published, "a filter never edits the auction's own rows")


func test_the_head_offers_one_chip_per_court_and_good_on_the_table() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	var chips: Dictionary = head.filter_buttons()
	assert_eq((chips["seller:-1"] as Button).text, "All courts 11", "all tons on the table")
	assert_eq((chips["seller:9"] as Button).text, "Aztec 3")
	assert_eq((chips["seller:7"] as Button).text, "Venice 6")
	assert_false(chips.has("seller:5"), "a court with nothing for sale has no chip")
	assert_eq((chips["good:grain"] as Button).text, "Grain 7")
	assert_eq((chips["good:timber"] as Button).text, "Timber 4")
	assert_false(chips.has("good:meat"), "a good nobody sells has no chip")
	for key: String in MarketOffersHead.SORT_KEYS:
		assert_true(chips.has("sort:%s" % key), "the order chip %s exists" % key)
	assert_true((chips["seller:-1"] as Button).button_pressed, "All is the opening filter")
	assert_true((chips["sort:seller"] as Button).button_pressed)
	head.free()


func test_a_chip_press_is_the_whole_filter_intent() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	var seen: Array = []
	head.filters_changed.connect(
		func(seller: int, good: String, sort_key: String) -> void:
			seen.append([seller, good, sort_key])
	)
	(head.filter_buttons()["seller:11"] as Button).pressed.emit()
	assert_eq(head.seller, 11)
	assert_eq(seen, [[11, MarketOffersHead.ALL_GOODS, MarketOffersHead.SORT_SELLER]])
	var chips: Dictionary = head.filter_buttons()
	assert_true((chips["seller:11"] as Button).button_pressed, "the chosen chip lights")
	assert_false((chips["seller:-1"] as Button).button_pressed, "All steps aside")

	(head.filter_buttons()["good:timber"] as Button).pressed.emit()
	assert_eq(head.commodity, "timber")
	assert_eq(seen.size(), 2)
	assert_eq(seen[1], [11, "timber", MarketOffersHead.SORT_SELLER])

	(head.filter_buttons()["sort:quantity"] as Button).pressed.emit()
	assert_eq(head.sort_key, MarketOffersHead.SORT_STOCK)
	assert_eq(seen.size(), 3)
	assert_eq(seen[2], [11, "timber", MarketOffersHead.SORT_STOCK])
	head.free()


## A court that sold out this turn takes its chip with it; the filter falls back
## to All and tells the page, so the strip never hides the whole book silently.
func test_a_selection_the_new_book_lost_falls_back_to_all() -> void:
	var head := MarketOffersHead.new()
	head.render(_book(), 11, "grain", MarketOffersHead.SORT_PRICE)
	assert_eq(head.seller, 11)

	var seen: Array = []
	head.filters_changed.connect(
		func(seller: int, good: String, sort_key: String) -> void:
			seen.append([seller, good, sort_key])
	)
	var next_book: Array = [_book()[0]]
	head.render(next_book, 11, "grain", MarketOffersHead.SORT_PRICE)
	assert_eq(head.seller, MarketOffersHead.ALL_SELLERS)
	assert_eq(head.commodity, MarketOffersHead.ALL_GOODS)
	assert_eq(head.sort_key, MarketOffersHead.SORT_PRICE, "a live order survives the turn")
	assert_eq(seen, [[MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_PRICE]])
	head.free()


func test_an_unknown_order_key_falls_back_to_the_court_order() -> void:
	var head := MarketOffersHead.new()
	head.render(_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS, "sideways")
	assert_eq(head.sort_key, MarketOffersHead.SORT_SELLER)
	head.free()


## Chips are thumb targets on a phone viewport (REQ-P5-07).
func test_chips_grow_for_a_thumb_on_a_phone() -> void:
	var head := MarketOffersHead.new()
	head.render(
		_book(), MarketOffersHead.ALL_SELLERS, MarketOffersHead.ALL_GOODS,
		MarketOffersHead.SORT_SELLER
	)
	head.set_compact(true)
	for key: Variant in head.filter_buttons().keys():
		var chip: Button = head.filter_buttons()[key] as Button
		assert_eq(chip.custom_minimum_size.y, MarketOffersHead.CHIP_HEIGHT_TOUCH, String(key))
	head.set_compact(false)
	for key: Variant in head.filter_buttons().keys():
		var chip: Button = head.filter_buttons()[key] as Button
		assert_eq(chip.custom_minimum_size.y, MarketOffersHead.CHIP_HEIGHT, String(key))
	head.free()
