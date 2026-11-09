class_name ShipStats
extends RefCounted
## Canonical per-hull combat and cargo stats (wiki: ships-and-naval § Ship
## combat and cargo stats). Stable ids, no nodes: combat, interception and
## home-fleet cargo all read this one catalog (REQ-P3-03).

const DEFAULT_TYPE: String = "carrack"

## Weighted naval strength (wiki: § Naval Strength Aggregation Formula).
const FRP_WEIGHT: float = 1.0
const RNG_WEIGHT: float = 0.4
const ARM_WEIGHT: float = 0.15
const MV_WEIGHT: float = 0.1

const STATS: Dictionary = {
	"carrack":
	{
		"role": "merchant",
		"frp": 2,
		"rng": 1,
		"arm": 1,
		"hull": 2,
		"mv": 2,
		"intercept": 1,
		"flee": 2,
		"cargo": 3,
	},
	"fluyte":
	{
		"role": "merchant",
		"frp": 1,
		"rng": 1,
		"arm": 1,
		"hull": 1,
		"mv": 2,
		"intercept": 1,
		"flee": 3,
		"cargo": 4,
	},
	"sloop":
	{
		"role": "warship",
		"frp": 2,
		"rng": 2,
		"arm": 1,
		"hull": 2,
		"mv": 3,
		"intercept": 4,
		"flee": 4,
		"cargo": 0,
	},
	"trader":
	{
		"role": "merchant",
		"frp": 1,
		"rng": 1,
		"arm": 1,
		"hull": 2,
		"mv": 2,
		"intercept": 1,
		"flee": 3,
		"cargo": 5,
	},
	"galleon":
	{
		"role": "merchant",
		"frp": 2,
		"rng": 1,
		"arm": 2,
		"hull": 4,
		"mv": 2,
		"intercept": 1,
		"flee": 2,
		"cargo": 6,
	},
	"indiaman":
	{
		"role": "merchant",
		"frp": 2,
		"rng": 2,
		"arm": 2,
		"hull": 5,
		"mv": 2,
		"intercept": 1,
		"flee": 2,
		"cargo": 8,
	},
	"frigate":
	{
		"role": "warship",
		"frp": 4,
		"rng": 3,
		"arm": 2,
		"hull": 4,
		"mv": 3,
		"intercept": 5,
		"flee": 4,
		"cargo": 0,
	},
	"raider":
	{
		"role": "warship",
		"frp": 3,
		"rng": 2,
		"arm": 2,
		"hull": 3,
		"mv": 4,
		"intercept": 6,
		"flee": 5,
		"cargo": 0,
	},
	"ship_of_the_line":
	{
		"role": "warship",
		"frp": 6,
		"rng": 4,
		"arm": 4,
		"hull": 8,
		"mv": 2,
		"intercept": 2,
		"flee": 1,
		"cargo": 0,
	},
	"clipper":
	{
		"role": "merchant",
		"frp": 1,
		"rng": 2,
		"arm": 1,
		"hull": 3,
		"mv": 4,
		"intercept": 2,
		"flee": 4,
		"cargo": 7,
	},
	"merchant_steamship":
	{
		"role": "merchant",
		"frp": 2,
		"rng": 2,
		"arm": 3,
		"hull": 5,
		"mv": 3,
		"intercept": 1,
		"flee": 3,
		"cargo": 9,
	},
	"ironclad":
	{
		"role": "warship",
		"frp": 5,
		"rng": 3,
		"arm": 8,
		"hull": 6,
		"mv": 3,
		"intercept": 2,
		"flee": 2,
		"cargo": 0,
	},
}


static func known(type_id: String) -> bool:
	return STATS.has(type_id)


## Stats for a catalog type; unknown ids fall back to the always-buildable carrack.
static func entry(type_id: String) -> Dictionary:
	return STATS.get(type_id, STATS[DEFAULT_TYPE])


static func normalize(type_id: String) -> String:
	if STATS.has(type_id):
		return type_id
	return DEFAULT_TYPE


static func is_warship(type_id: String) -> bool:
	return String(entry(type_id).get("role", "merchant")) == "warship"


## Weighted combat strength of a single hull (wiki: aggregation formula).
static func strength(type_id: String) -> float:
	var data: Dictionary = entry(type_id)
	return (
		float(data["frp"]) * FRP_WEIGHT
		+ float(data["rng"]) * RNG_WEIGHT
		+ float(data["arm"]) * ARM_WEIGHT
		+ float(data["mv"]) * MV_WEIGHT
	)


## Hull durability pool (wiki: HULL × (1 + ARM/10)).
static func durability(type_id: String) -> float:
	var data: Dictionary = entry(type_id)
	return float(data["hull"]) * (1.0 + float(data["arm"]) / 10.0)


## Firepower of one hull; the court docket's ship strength sums this
## (wiki: ships-and-naval § Ship muster and the breaker's yard).
static func firepower(type_id: String) -> int:
	return int(entry(type_id).get("frp", 0))


static func display_name(type_id: String) -> String:
	match normalize(type_id):
		"carrack":
			return "Carrack"
		"fluyte":
			return "Fluyte"
		"sloop":
			return "Sloop"
		"trader":
			return "Trader"
		"galleon":
			return "Galleon"
		"indiaman":
			return "Indiaman"
		"frigate":
			return "Frigate"
		"raider":
			return "Raider"
		"ship_of_the_line":
			return "Ship of the Line"
		"clipper":
			return "Clipper"
		"merchant_steamship":
			return "Merchant Steamship"
		"ironclad":
			return "Ironclad"
	return String(DEFAULT_TYPE)
