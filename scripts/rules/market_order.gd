class_name MarketOrder
extends RefCounted
## One world-market order (wiki: world-market § Trade orders). A Great Power
## submits a bid or an offer at the published price; Minor Nations and Tribes
## publish auto-offers from their estates. Orders carry a priority tier (1 =
## highest), the source tile when an offer comes from a deed, and the resolved
## fill so the Deal Book can name it (REQ-P3-03).

const SIDE_BID: String = "bid"
const SIDE_OFFER: String = "offer"
## The standing world counterparty: it is never a faction and never settles a
## purse, only lets an otherwise unfilled order clear at the published price.
const WORLD: int = -1
const NO_ORIGIN: int = -1

var id: String = ""
var faction: int = WORLD
var commodity: String = ""
var side: String = SIDE_BID
var quantity: int = 0
var priority: int = 1
## Auto-offers come from a Minor Nation or Tribe, not a Great Power order.
var auto: bool = false
var origin_region: int = NO_ORIGIN
var origin_index: int = NO_ORIGIN
var filled: int = 0


static func create(
	p_faction: int,
	p_commodity: String,
	p_side: String,
	p_quantity: int,
	p_priority: int = 1,
	p_origin_region: int = NO_ORIGIN,
	p_origin_index: int = NO_ORIGIN,
	p_auto: bool = false
) -> MarketOrder:
	var order := MarketOrder.new()
	order.faction = p_faction
	order.commodity = p_commodity
	order.side = p_side
	order.quantity = maxi(p_quantity, 0)
	order.priority = maxi(p_priority, 1)
	order.origin_region = p_origin_region
	order.origin_index = p_origin_index
	order.auto = p_auto
	order.id = _make_id(order)
	return order


static func _make_id(order: MarketOrder) -> String:
	if order.auto:
		return "auto:%d:%s:%d:%d" % [
			order.faction, order.commodity, order.origin_region, order.origin_index
		]
	return "%d:%s:%s:%d" % [order.faction, order.side, order.commodity, order.priority]


func remaining() -> int:
	return maxi(quantity - filled, 0)


func is_bid() -> bool:
	return side == SIDE_BID


func is_world() -> bool:
	return faction == WORLD


## A copy for matching: fills on the original are the record, while the matcher
## walks its own working quantities.
func clone() -> MarketOrder:
	var copy := MarketOrder.new()
	copy.id = id
	copy.faction = faction
	copy.commodity = commodity
	copy.side = side
	copy.quantity = quantity
	copy.priority = priority
	copy.auto = auto
	copy.origin_region = origin_region
	copy.origin_index = origin_index
	copy.filled = filled
	return copy


func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction": faction,
		"commodity": commodity,
		"side": side,
		"quantity": quantity,
		"priority": priority,
		"auto": auto,
		"origin_region": origin_region,
		"origin_index": origin_index,
		"filled": filled,
	}


static func from_dict(data: Dictionary) -> MarketOrder:
	var order := MarketOrder.new()
	order.id = String(data.get("id", ""))
	order.faction = int(data.get("faction", WORLD))
	order.commodity = String(data.get("commodity", ""))
	order.side = String(data.get("side", SIDE_BID))
	order.quantity = maxi(int(data.get("quantity", 0)), 0)
	order.priority = maxi(int(data.get("priority", 1)), 1)
	order.auto = bool(data.get("auto", false))
	order.origin_region = int(data.get("origin_region", NO_ORIGIN))
	order.origin_index = int(data.get("origin_index", NO_ORIGIN))
	order.filled = maxi(int(data.get("filled", 0)), 0)
	if order.id.is_empty():
		order.id = _make_id(order)
	return order
