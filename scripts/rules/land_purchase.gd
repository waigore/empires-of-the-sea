class_name LandPurchase
extends RefCounted
## Merchant land purchase (wiki: civilian-units § Work Order Summary,
## § Merchant). Pure rules: a tile in a Minor Nation or Tribe province with a
## resource, an embassy, no war, and a prospected mineral when required. The
## price is validated at assign and debited when the one-turn work completes.

const ACTION: String = "purchase_land"
const PRICE_MULTIPLIER: int = 15
const TURNS: int = 1


## 15 x the resource's base market price; 0 for an unknown commodity.
static func cost(model: MapModel, tile: Vector2i) -> int:
	if model == null:
		return 0
	var resource: int = model.resource_at(tile.x, tile.y)
	var commodity: String = Extraction.commodity_for_resource(resource)
	return PRICE_MULTIPLIER * CommodityCatalog.base_price(commodity)


static func cost_text(model: MapModel, tile: Vector2i) -> String:
	return DiplomacyCatalog.money(cost(model, tile))


## Validates a purchase without charging it. `context` carries the live purse
## and court: {treasury: int, diplomacy: DiplomacyState}.
static func check(
	model: MapModel,
	unit: CivilianState,
	tile: Vector2i,
	works: LandWorks,
	units: Array[CivilianState],
	context: Dictionary = {}
) -> Dictionary:
	var province: int = model.province_at(tile.x, tile.y)
	if province == MapModel.NO_ID:
		return _no("This tile belongs to no province.")
	var seller: int = model.province_owner(province)
	var seller_type: int = FactionCatalog.type_of(seller)
	if seller_type != FactionCatalog.Type.MINOR_NATION and seller_type != FactionCatalog.Type.TRIBE:
		return _no("Only Minor Nations and Tribes sell land.")
	if model.is_purchased_tile(tile):
		return _no("This tile has already been bought.")
	var resource: int = model.resource_at(tile.x, tile.y)
	if resource == MapModel.NO_ID:
		return _no("Only a tile with a resource can be purchased.")
	var diplomacy: DiplomacyState = context.get("diplomacy", null)
	if diplomacy == null:
		return _no("No court is open to sign a deed.")
	if DiplomacyRules.at_war_with(diplomacy, unit.owner, seller):
		return _no("Your crown is at war with %s." % FactionCatalog.name_of(seller))
	if not DiplomacyRules.has_embassy(diplomacy, unit.owner, seller):
		return _no("An embassy with %s is required." % FactionCatalog.name_of(seller))
	if (
		ImprovementCatalog.needs_prospecting(resource)
		and not works.is_prospected(unit.owner, model, tile)
	):
		return _no("An Explorer must prospect this tile before it can be bought.")
	var price: int = cost(model, tile)
	if price <= 0:
		return _no("This resource has no market price.")
	if int(context.get("treasury", 0)) < price:
		return _no("The treasury cannot cover the %s price." % cost_text(model, tile))
	for other: CivilianState in units:
		if other == null or other == unit or other.owner != unit.owner:
			continue
		if other.is_working() and other.work_tile() == tile:
			return _no("Another crew is already working this tile.")
	return {
		"ok": true,
		"reason": "",
		"cost": {},
		"cost_text": cost_text(model, tile),
		"treasury_cost": price,
		"duration": TURNS,
		"tile": tile,
		"province": province,
	}


## Completion: charge the purse and record the deed. Returns false when the
## purse no longer covers the price or another buyer already holds the deed, and
## when no ledger answers for the buyer at all (a deed is never signed for free).
## A signed deed develops the seller's town (DR-20261112-01).
static func complete(model: MapModel, tile: Vector2i, owner: int, economy: PlayerEconomy) -> bool:
	if economy == null:
		return false
	if model.is_purchased_tile(tile):
		return false
	var price: int = cost(model, tile)
	if not economy.spend_treasury(price):
		return false
	if model.purchase_tile(tile, owner):
		MinorTownGrowth.raise_on_deed(model, model.province_at(tile.x, tile.y))
		return true
	economy.add_treasury(price)
	return false


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": {}, "duration": 0}
