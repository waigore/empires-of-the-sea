class_name MarketBook
extends RefCounted
## The live world-market order book (wiki: world-market § Trade orders, § Order
## persistence). Staged orders belong to the turn being played; carry-forward
## orders are unfilled residuals the next turn may still clear. Pure data so the
## market, the matcher, the ledger and saves share one book (REQ-P3-03).

var submitted: Array[MarketOrder] = []
## Unfilled Great-Power orders carried from the previous turn.
var carry: Array[MarketOrder] = []
## Last clearing pass, for the Deal Book and turn trace.
var last_deals: Array[Dictionary] = []
var last_notes: Array[Dictionary] = []
var _seq: int = 0


## Adds one order and gives it a unique id. The caller validates first.
func submit(order: MarketOrder) -> void:
	if order == null:
		return
	_seq += 1
	order.id = "%s#%d" % [order.id, _seq]
	submitted.append(order)


## Removes one faction's staged order. Carry-forward orders are not cancelable.
func cancel(faction: int, order_id: String) -> bool:
	for index in submitted.size():
		var order: MarketOrder = submitted[index]
		if order.faction == faction and order.id == order_id:
			submitted.remove_at(index)
			return true
	return false


func find_order(faction: int, order_id: String) -> MarketOrder:
	for order: MarketOrder in submitted:
		if order.faction == faction and order.id == order_id:
			return order
	for order: MarketOrder in carry:
		if order.faction == faction and order.id == order_id:
			return order
	return null


func orders_for(faction: int, side: String = "") -> Array[MarketOrder]:
	var rows: Array[MarketOrder] = []
	for order: MarketOrder in all_open():
		if order.faction != faction:
			continue
		if not side.is_empty() and order.side != side:
			continue
		rows.append(order)
	return rows


## Every live Great-Power order, carry first so a newer order never starves it.
func all_open() -> Array[MarketOrder]:
	var rows: Array[MarketOrder] = []
	rows.append_array(carry)
	rows.append_array(submitted)
	return rows


func pending_buy_units(faction: int) -> int:
	var total: int = 0
	for order: MarketOrder in orders_for(faction, MarketOrder.SIDE_BID):
		total += order.remaining()
	return total


func pending_sell_units(faction: int, commodity: String = "") -> int:
	var total: int = 0
	for order: MarketOrder in orders_for(faction, MarketOrder.SIDE_OFFER):
		if not commodity.is_empty() and order.commodity != commodity:
			continue
		total += order.remaining()
	return total


## Commodities this faction already bids on, for the bid-type cap.
func bid_commodities(faction: int) -> Array[String]:
	var ids: Array[String] = []
	for order: MarketOrder in orders_for(faction, MarketOrder.SIDE_BID):
		if not ids.has(order.commodity):
			ids.append(order.commodity)
	ids.sort()
	return ids


## True when the faction already staged the other side of this commodity; the
## whole pair is rejected by the rules (mutual exclusion per commodity).
func has_opposite(faction: int, commodity: String, side: String) -> bool:
	var other: String = (
		MarketOrder.SIDE_OFFER if side == MarketOrder.SIDE_BID else MarketOrder.SIDE_BID
	)
	for order: MarketOrder in orders_for(faction, other):
		if order.commodity == commodity and order.remaining() > 0:
			return true
	return false


func staged_count() -> int:
	return submitted.size()


## Empties the turn's staged orders after a clearing pass; residuals have
## already been moved into `carry`.
func close_turn() -> void:
	submitted.clear()


func set_carry(orders: Array[MarketOrder]) -> void:
	carry.clear()
	for order: MarketOrder in orders:
		carry.append(order)


func copy() -> MarketBook:
	var clone := MarketBook.new()
	for order: MarketOrder in carry:
		clone.carry.append(order.clone())
	for order: MarketOrder in submitted:
		clone.submitted.append(order.clone())
	clone.last_deals = last_deals.duplicate(true)
	clone.last_notes = last_notes.duplicate(true)
	clone._seq = _seq
	return clone


func to_dict() -> Dictionary:
	return {
		"submitted": _orders_to_data(submitted),
		"carry": _orders_to_data(carry),
		"last_deals": last_deals.duplicate(true),
		"last_notes": last_notes.duplicate(true),
		"seq": _seq,
	}


static func from_dict(data: Dictionary) -> MarketBook:
	var book := MarketBook.new()
	for entry: Variant in data.get("submitted", []):
		if typeof(entry) == TYPE_DICTIONARY:
			book.submitted.append(MarketOrder.from_dict(entry))
	for entry: Variant in data.get("carry", []):
		if typeof(entry) == TYPE_DICTIONARY:
			book.carry.append(MarketOrder.from_dict(entry))
	book.last_deals = _dict_array(data.get("last_deals", []))
	book.last_notes = _dict_array(data.get("last_notes", []))
	book._seq = int(data.get("seq", 0))
	return book


static func _orders_to_data(orders: Array[MarketOrder]) -> Array:
	var rows: Array = []
	for order: MarketOrder in orders:
		rows.append(order.to_dict())
	return rows


static func _dict_array(raw: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw:
			if typeof(entry) == TYPE_DICTIONARY:
				rows.append((entry as Dictionary).duplicate(true))
	return rows
