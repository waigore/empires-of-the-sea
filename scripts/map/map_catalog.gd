class_name MapCatalog
extends RefCounted
## Name tables, resource rows, and the generator's deterministic name picks.
## Faction display names stay on MapGenerator; these tables are generation-only.


const PROVINCE_ROOTS: Array[String] = [
	"Cádiz", "Marcos", "Cruz", "Rica", "Cartagena", "Veracruz", "Habana", "Domingo",
	"Trujillo", "Panamá", "Juan", "Cumaná", "Maracaibo", "Coro", "Margarita", "Trinidad",
	"Santiago", "Isabel", "Fernando", "Agustín", "Miguel", "Cristóbal", "Antonio", "Lucía",
	"Elena", "Rosa", "Pedro", "Andrés", "Felipe", "Blas", "Jerónimo", "Catalina",
]

const PROVINCE_PREFIXES: Array[String] = ["San", "Santa", "Puerto", "Villa", "Nueva", "Real"]

const SEA_NAMES: Array[String] = [
	"Mar del Norte", "Golfo de las Perlas", "Mar Caribe", "Bahía de Cádiz",
	"Estrecho de Gibraltar", "Mar de las Antillas", "Golfo de México", "Océano Atlántico",
	"Mar Mediterráneo", "Canal de las Bahamas", "Mar de los Sargazos", "Golfo de Guinea",
	"Mar Tirreno", "Bahía de Vizcaya", "Canal de la Mancha", "Mar Báltico",
	"Golfo de León", "Mar de Alborán", "Mar de Azov", "Golfo de Cádiz",
]


## Region scopes match wiki resource-terrain-region-rules (ow / nw / both).
static func resource_table() -> Array[Dictionary]:
	var forest: Array = [MapModel.Terrain.HARDWOOD_FOREST, MapModel.Terrain.SCRUB_FOREST]
	## Hardwood alone hosts the New World fur catch (wiki: § Forest terrain split).
	var hardwood: Array = [MapModel.Terrain.HARDWOOD_FOREST]
	var hills: Array = [MapModel.Terrain.HILLS]
	var peaks: Array = [MapModel.Terrain.MOUNTAINS]
	var plains: Array = [MapModel.Terrain.PLAINS]
	var swamp: Array = [MapModel.Terrain.SWAMP]
	var desert: Array = [MapModel.Terrain.DESERT]
	var table: Array[Dictionary] = [
		{"name": "Timber", "icon": "tree", "commodity": "timber", "terrain": forest, "scope": "both"},
		{"name": "Iron", "icon": "ore", "commodity": "iron", "terrain": hills + peaks, "scope": "both"},
		{"name": "Coal", "icon": "ore", "commodity": "coal", "terrain": hills + peaks, "scope": "both"},
		{"name": "Gold", "icon": "coin", "commodity": "gold", "terrain": peaks, "scope": "nw"},
		{"name": "Grain", "icon": "wheat", "commodity": "grain", "terrain": plains, "scope": "ow"},
		{"name": "Wool", "icon": "wheat", "commodity": "wool", "terrain": hills, "scope": "ow"},
		{"name": "Horses", "icon": "wheat", "commodity": "horses", "terrain": plains, "scope": "ow"},
		{"name": "Meat", "icon": "wheat", "commodity": "meat", "terrain": plains, "scope": "ow"},
		{"name": "Tin", "icon": "ore", "commodity": "tin", "terrain": swamp, "scope": "both"},
		{"name": "Copper", "icon": "ore", "commodity": "copper", "terrain": hills + peaks, "scope": "both"},
		{"name": "Silver", "icon": "coin", "commodity": "silver", "terrain": hills, "scope": "nw"},
		{"name": "Gems", "icon": "coin", "commodity": "gems", "terrain": peaks, "scope": "nw"},
		{"name": "Diamonds", "icon": "coin", "commodity": "diamonds", "terrain": desert, "scope": "nw"},
		## The New World crops (wiki: resource-terrain-region-rules § Table). They
		## are appended so every saved resource index keeps its meaning: the five
		## discovery techs, the sugar/tobacco/fur luxuries and cotton cloth are
		## reachable only once these can stand on a New World tile.
		{"name": "Sugar Cane", "icon": "wheat", "commodity": "sugarCane", "terrain": plains, "scope": "nw"},
		{"name": "Tobacco", "icon": "wheat", "commodity": "tobacco", "terrain": plains, "scope": "nw"},
		{"name": "Cotton", "icon": "wheat", "commodity": "cotton", "terrain": plains, "scope": "nw"},
		{"name": "Furs", "icon": "tree", "commodity": "furs", "terrain": hardwood, "scope": "nw"},
		{"name": "Spices", "icon": "wheat", "commodity": "spices", "terrain": plains, "scope": "nw"},
	]
	return table


static func resource_info(index: int) -> Dictionary:
	var table: Array[Dictionary] = resource_table()
	if index < 0 or index >= table.size():
		return {}
	return table[index]


## Same RNG draws as the old MapGenerator name pass: root, then an optional prefix.
static func unique_province_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for _attempt in 40:
		var root: String = PROVINCE_ROOTS[rng.randi_range(0, PROVINCE_ROOTS.size() - 1)]
		var roll: float = rng.randf()
		var name: String = root
		if roll < 0.45:
			var prefix: String = PROVINCE_PREFIXES[rng.randi_range(0, PROVINCE_PREFIXES.size() - 1)]
			name = "%s %s" % [prefix, root]
		elif roll < 0.6:
			name = "Nueva %s" % root
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Tierra %d" % (used.size() + 1)
	used[fallback] = true
	return fallback


static func unique_sea_name(used: Dictionary) -> String:
	for name: String in SEA_NAMES:
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Mar %d" % (used.size() + 1)
	used[fallback] = true
	return fallback
