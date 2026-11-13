class_name CommodityCatalog
extends RefCounted
## Canonical commodity catalog (wiki: commodity-catalog). Pure data: the
## stockpile, production, market and UI all read these ids, categories and
## default prices, so no screen can invent its own commodity set (REQ-P2-03).

enum Category { FOOD, RAW, MANUFACTURED, LUXURY, RICHES, ADVANCED }

const NO_CATEGORY: int = -1

## Food first: every ration is drawn from these two ids (wiki: workers-and-population).
const FOOD: Array[String] = ["grain", "meat"]
const RAW: Array[String] = [
	"wool",
	"horses",
	"timber",
	"iron",
	"copper",
	"tin",
	"coal",
	"sugarCane",
	"tobacco",
	"cotton",
	"furs",
]
const MANUFACTURED: Array[String] = [
	"lumber",
	"castIron",
	"fabric",
	"refinedSugar",
	"cigars",
	"furHats",
	"steel",
	"paper",
	"bronze",
]
## Reserved category: no current commodity is a luxury; trained-worker luxuries are
## manufactured goods (wiki: commodity-catalog § Categories).
const LUXURY: Array[String] = []
## Five New World riches (Imperialism II): not traded; clear to treasury
## (wiki: commodity-catalog § Riches and treasury; DR-20261113-13).
const RICHES: Array[String] = ["gold", "silver", "gems", "diamonds", "spices"]
## Reserved category: no current commodity is advanced (DR-20261113-13).
const ADVANCED: Array[String] = []

## Raw-resource default market prices (wiki: resource-terrain-region-rules § Table).
const RAW_PRICES: Dictionary = {
	"grain": 50,
	"meat": 45,
	"wool": 40,
	"horses": 60,
	"timber": 30,
	"iron": 80,
	"copper": 70,
	"tin": 75,
	"coal": 90,
	"sugarCane": 35,
	"tobacco": 40,
	"cotton": 45,
	"furs": 55,
}

## Break-even prices derived from each manufactured commodity's canonical recipe
## (wiki: commodity-catalog § Manufactured base prices).
const MANUFACTURED_PRICES: Dictionary = {
	"lumber": 60,
	"castIron": 160,
	"fabric": 80,
	"refinedSugar": 70,
	"cigars": 80,
	"furHats": 110,
	"steel": 170,
	"paper": 60,
	"bronze": 145,
}

## Riches convert to treasury in their own phase; spices is fixed at 50.
const RICHES_PRICES: Dictionary = {
	"gold": 166,
	"silver": 100,
	"gems": 250,
	"diamonds": 500,
	"spices": 50,
}

const CATEGORY_LABELS: Dictionary = {
	Category.FOOD: "Food",
	Category.RAW: "Raw materials",
	Category.MANUFACTURED: "Manufactured",
	Category.LUXURY: "Luxury",
	Category.RICHES: "Riches",
	Category.ADVANCED: "Advanced",
}


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.append_array(FOOD)
	ids.append_array(RAW)
	ids.append_array(MANUFACTURED)
	ids.append_array(LUXURY)
	ids.append_array(RICHES)
	ids.append_array(ADVANCED)
	return ids


static func ids_in(category: int) -> Array[String]:
	var ids: Array[String] = []
	for id: String in all_ids():
		if category_of(id) == category:
			ids.append(id)
	return ids


## Commodities cleared into treasury during the Riches phase (wiki:
## stockpiles-and-production § Production flow). The riches set only —
## spices included (Imperialism II; DR-20261113-13).
static func treasury_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.append_array(RICHES)
	return ids


static func category_of(id: String) -> int:
	if FOOD.has(id):
		return Category.FOOD
	if RAW.has(id):
		return Category.RAW
	if MANUFACTURED.has(id):
		return Category.MANUFACTURED
	if LUXURY.has(id):
		return Category.LUXURY
	if RICHES.has(id):
		return Category.RICHES
	if ADVANCED.has(id):
		return Category.ADVANCED
	return NO_CATEGORY


static func category_label(category: int) -> String:
	return String(CATEGORY_LABELS.get(category, "Unknown"))


static func known(id: String) -> bool:
	return category_of(id) != NO_CATEGORY


static func is_food(id: String) -> bool:
	return category_of(id) == Category.FOOD


static func is_raw(id: String) -> bool:
	return category_of(id) == Category.RAW


static func is_riches(id: String) -> bool:
	return category_of(id) == Category.RICHES


## Riches (including spices) clear through the treasury phase; every other known
## good clears on the world market (wiki: world-market § Tradeable commodities;
## Imperialism II; DR-20261113-13).
static func is_tradeable(id: String) -> bool:
	return known(id) and not is_riches(id)


## Integer catalog price: raw rows, manufactured break-even rows and riches base.
static func base_price(id: String) -> int:
	if RAW_PRICES.has(id):
		return int(RAW_PRICES[id])
	if MANUFACTURED_PRICES.has(id):
		return int(MANUFACTURED_PRICES[id])
	if RICHES_PRICES.has(id):
		return int(RICHES_PRICES[id])
	return 0


## Display name derived from the stable id: castIron -> "Cast Iron".
static func label(id: String) -> String:
	var out: String = ""
	for index in id.length():
		var glyph: String = id[index]
		if index > 0 and glyph == glyph.to_upper() and glyph != glyph.to_lower():
			out += " "
		out += glyph
	return out.substr(0, 1).to_upper() + out.substr(1)
