class_name SiegeGround
extends RefCounted
## The ground a siege Quick Battle is fought over (wiki: quick-battle § Terrain;
## siege-mechanics § Damage Reduction).
##
## Lane terrain (OPEN / HILL / WOODS / TOWN / MARSH) comes from the province's
## dominant ground, or from the town a fort rings. Assaults and volleys are
## weaker into broken ground; entrenching is surer there and weaker in a marsh.
## The lanes themselves are [SiegeLanes]' and the wall's gates [SiegeGates]'.
## Pure data and maths: no nodes (REQ-P3-01, REQ-P3-03).

## Lane terrain: how weak a blow is into that ground, and how much surer an
## entrenchment is there (wiki: quick-battle § Core actions — entrench
## especially in HILL, WOODS, TOWN; assault weaker into WOODS, TOWN, uphill HILL).
## The ids are the published ones: a swamp province fights on `marsh` ground.
const TERRAIN: Dictionary = {
	"open": {"label": "Open field", "volley": 1.0, "assault": 1.0, "entrench": 1.0},
	"hill": {"label": "Hillside", "volley": 0.9, "assault": 0.75, "entrench": 1.2},
	"woods": {"label": "Woods", "volley": 0.75, "assault": 0.6, "entrench": 1.3},
	"town": {"label": "Town streets", "volley": 0.7, "assault": 0.55, "entrench": 1.4},
	"marsh": {"label": "Marsh", "volley": 0.9, "assault": 0.7, "entrench": 0.8},
}


## The ground the battle is fought over. `override` is the playtest/simulator
## hook; a real battle passes "" and reads the province.
## A fort rings its town on open ground; broken ground keeps its own character
## (the fight is for the approaches), so HILL and WOODS sieges are possible.
static func lane_terrain(
	model: MapModel, province: int, fort: int, override: String = ""
) -> String:
	if TERRAIN.has(override):
		return override
	var dominant: int = ArmyModifiers.terrain_for(model, province)
	match dominant:
		MapModel.Terrain.HILLS, MapModel.Terrain.MOUNTAINS:
			return "hill"
		MapModel.Terrain.HARDWOOD_FOREST, MapModel.Terrain.SCRUB_FOREST:
			return "woods"
		MapModel.Terrain.SWAMP:
			return "marsh"
	if fort > 0:
		return "town"
	return "open"


static func terrain_label(terrain: String) -> String:
	return String((TERRAIN.get(terrain, TERRAIN["open"]) as Dictionary)["label"])


## How much of a volley or an assault survives the ground it is delivered into.
static func terrain_scale(action: String, terrain: String) -> float:
	if action != "volley" and action != "assault":
		return 1.0
	return float((TERRAIN.get(terrain, TERRAIN["open"]) as Dictionary)[action])


## An entrenchment is surer in cover and weaker in a marsh.
static func entrench_scale(terrain: String) -> float:
	return float((TERRAIN.get(terrain, TERRAIN["open"]) as Dictionary)["entrench"])
