class_name MapNaming
extends RefCounted
## Period place-name pools per faction and region (wiki: naming, tile-map-and-generation).
## Kept apart from generation so the generator stays focused and under the P3
## size bar. Province names follow ownership: a Spanish province draws from the
## Spanish pool, so names always read as the country they belong to.

const OLD_WORLD_ROOTS: Array[String] = [
	"Cádiz", "Sevilla", "Toledo", "Burgos", "Valladolid", "Zaragoza", "Barcelona",
	"Valencia", "Granada", "Salamanca", "Bilbao", "Cartagena", "Málaga", "Córdoba",
	"Lisboa", "Oporto", "Coímbra", "Évora", "Braga",
	"London", "Brístol", "Plymouth", "Dover", "York", "Norwich", "Oxford",
	"París", "Rouen", "Nantes", "Burdeos", "Marsella", "Lyon", "Brest", "Tolón",
	"Ámsterdam", "Amberes", "Róterdam", "Utrecht", "Brujas", "Bruselas", "Gante",
	"Estocolmo", "Gotemburgo", "Malmö", "Upsala", "Abo", "Copenhague", "Bergen",
	"Génova", "Venecia", "Nápoles", "Florencia", "Milán", "Palermo", "Roma",
	"Lübeck", "Hamburgo", "Danzig", "Riga", "Cracovia", "Viena", "Praga", "Budapest",
	"Dublín", "Edimburgo", "Glasgow", "Cork", "Ginebra", "Zúrich", "Salzburgo",
	"Trento", "Trieste",
]

const OLD_WORLD_PREFIXES: Array[String] = []

const NEW_WORLD_ROOTS: Array[String] = [
	"Tenochtitlan", "Texcoco", "Tlacopan", "Cholula", "Tikal", "Uxmal", "Tulum",
	"Cusco", "Quito", "Tumbes", "Chimú", "Bacatá", "Tairona", "Boriquén", "Xaragua",
	"Maguana", "Cibao", "Arauco", "Purén", "Itzá", "Copán", "Chen", "Cempoala",
]

const NEW_WORLD_PREFIXES: Array[String] = ["Valle", "Sierra", "Costa", "Monte", "Río"]

## Historical city/province pools per faction id (Spanish exonyms throughout,
## except a nation's own capital: the naming config gives England "London").
## The first entry is the nation's capital city; `capital_name` uses it so the
## capital province reads right, and the rest fill the nation's other provinces.
const FACTION_ROOTS: Dictionary = {
	0: [  # Spain
		"Madrid", "Sevilla", "Toledo", "Burgos", "Valladolid", "Zaragoza",
		"Barcelona", "Valencia", "Granada", "Salamanca", "Bilbao", "Cartagena",
		"Málaga", "Córdoba", "Cádiz", "Segovia", "Cuenca", "Murcia", "Pamplona",
		"Badajoz",
	],
	1: [  # England
		"London", "Brístol", "Plymouth", "Dover", "York", "Norwich", "Oxford",
		"Cambridge", "Canterbury", "Chester", "Newcastle", "Liverpool", "Bath",
		"Portsmouth", "Nottingham", "Exeter", "Hull", "Leeds",
	],
	2: [  # France
		"París", "Rouen", "Nantes", "Burdeos", "Marsella", "Lyon", "Brest",
		"Tolón", "Orleans", "Reims", "Dijon", "Caen", "Niza", "Estrasburgo",
		"Tours", "Limoges", "Amiens", "Montpellier",
	],
	3: [  # Portugal
		"Lisboa", "Oporto", "Coímbra", "Évora", "Braga", "Faro", "Setúbal",
		"Aveiro", "Leiria", "Beja", "Viseu", "Guimarães",
	],
	4: [  # United Provinces
		"Ámsterdam", "Róterdam", "Utrecht", "La Haya", "Haarlem", "Leiden",
		"Delft", "Groninga", "Maastricht", "Middelburgo", "Dordrecht", "Zwolle",
	],
	5: [  # Sweden
		"Estocolmo", "Gotemburgo", "Malmö", "Upsala", "Åbo", "Kalmar",
		"Linköping", "Falun", "Karlstad", "Umeå", "Visby", "Lund",
	],
	6: [  # Genoa
		"Génova", "Savona", "La Spezia", "Chiavari", "Albenga", "Ventimiglia",
		"Imperia", "Rapallo", "Sarzana",
	],
	7: [  # Venice
		"Venecia", "Verona", "Padua", "Vicenza", "Brescia", "Bérgamo", "Treviso",
		"Chioggia", "Rovigo", "Udine",
	],
	8: [  # Denmark
		"Copenhague", "Aarhus", "Odense", "Aalborg", "Ribe", "Viborg", "Roskilde",
		"Helsingør", "Randers",
	],
	19: [  # Austria
		"Viena", "Linz", "Graz", "Innsbruck", "Clagenfurt", "Salzburgo", "Estiria",
		"Tirol", "Carintia",
	],
	20: [  # Poland
		"Cracovia", "Poznan", "Varsovia", "Vilna", "Riga", "Danzig", "Lublin",
		"Leópolis", "Brest",
	],
	21: [  # Scotland
		"Edimburgo", "San Andrés", "Glasgow", "Aberdeen", "Inverness", "Stirling",
		"Dumfries", "Perth", "Dundee",
	],
	9: [  # Aztec
		"Tenochtitlan", "Texcoco", "Tlacopan", "Cholula", "Cempoala", "Chalco",
		"Xochimilco", "Tlatelolco", "Cuernavaca", "Huejotzingo", "Tlalmanalco",
	],
	10: [  # Tlaxcala
		"Tlaxcala", "Tizatlán", "Ocotelolco", "Quiahuiztlán", "Tepeticpac",
		"Huexotzinco", "Atlihuetzia", "Tlaltelulco", "Tepetitlán", "Ixtacuixtla",
		"Nativitas",
	],
	11: [  # Maya
		"Tikal", "Uxmal", "Tulum", "Copán", "Chichén Itzá", "Mayapán",
		"Palenque", "Bonampak", "Yaxchilán", "Izamal",
	],
	12: [  # Inca
		"Cusco", "Quito", "Tumbes", "Chimú", "Cajamarca", "Vilcabamba", "Chincha",
		"Huánuco", "Arequipa", "Nazca", "Ollantaytambo", "Pisac",
	],
	13: [  # Muisca
		"Bacatá", "Tairona", "Tunja", "Sogamoso", "Duitama", "Guatavita", "Chía",
		"Zipaquirá", "Guachetá", "Ubaté", "Chocontá",
	],
	14: [  # Taíno
		"Boriquén", "Xaragua", "Maguana", "Cibao", "Higüey", "Marién",
		"Cubanacán", "Bayamo", "Jaragua", "Guahaba", "Yaguana",
	],
	15: [  # Mapuche
		"Arauco", "Purén", "Tucapel", "Imperial", "Valdivia", "Osorno",
		"Villarrica", "Angol", "Boroa", "Pilmaiquén", "Rere",
	],
	16: [  # Guaraní
		"Itatín", "Tape", "Carijó", "Guairá", "Paraná", "Uruguay", "Iberá",
		"Yapeyú", "Curuguaty", "Caazapá", "Mba'everá",
	],
	17: [  # Pueblo
		"Acoma", "Zuni", "Taos", "Pecos", "Mesa Verde", "Chaco", "Hopi", "Isleta",
		"Sandía", "Cochiti", "Tesuque",
	],
	18: [  # Carib
		"Cumaná", "Macuro", "Paria", "Tobago", "Dominica", "Santa Lucía",
		"Guadalupe", "Guaiquerí", "Barquisimeto", "Araya", "Tacarigua",
	],
}

const OLD_WORLD_SEA_NAMES: Array[String] = [
	"Mar del Norte", "Mar Mediterráneo", "Océano Atlántico", "Mar Báltico",
	"Canal de la Mancha", "Golfo de Vizcaya", "Mar Tirreno", "Mar Adriático",
	"Mar Egeo", "Mar Negro", "Golfo de León", "Mar de Alborán", "Golfo de Cádiz",
	"Mar de Liguria", "Mar de Cerdeña", "Golfo de Finlandia", "Kattegat",
	"Skagerrak", "Mar de Irlanda", "Canal de Sicilia",
]

const NEW_WORLD_SEA_NAMES: Array[String] = [
	"Mar del Sur", "Golfo de Panamá", "Golfo de California", "Mar del Plata",
	"Estrecho de Magallanes", "Mar Pacífico", "Mar de los Caribes", "Golfo de Darién",
	"Bahía de Todos os Santos", "Paso del Oeste", "Mar de las Perlas", "Golfo de Honduras",
	"Mar de Cortés", "Rada de la Esperanza", "Bahía de San Salvador", "Mar de Chiloé",
]


## Name pool belonging to one faction (empty for unknown or unclaimed ids).
static func faction_pool(faction_id: int) -> Array[String]:
	var pool: Array[String] = []
	if FACTION_ROOTS.has(faction_id):
		pool.assign(FACTION_ROOTS[faction_id])
	return pool


## The nation's capital-city name: the first entry in its historical pool.
static func capital_name(faction_id: int) -> String:
	var pool: Array[String] = faction_pool(faction_id)
	return pool[0] if not pool.is_empty() else ""


## Unique land-province name for a faction; deterministic for a given RNG state.
## Names come straight from the owner's pool. Unclaimed land (no faction) falls
## back to the generic regional pool, which may decorate roots with a prefix.
static func province_name(
	used: Dictionary,
	region_id: int,
	rng: RandomNumberGenerator,
	faction_id: int = -1
) -> String:
	var new_world: bool = region_id == FactionCatalog.NEW_WORLD
	var roots: Array[String] = faction_pool(faction_id)
	var decorative: bool = roots.is_empty()
	if decorative:
		roots = NEW_WORLD_ROOTS if new_world else OLD_WORLD_ROOTS
	var prefixes: Array[String] = (
		NEW_WORLD_PREFIXES if new_world else OLD_WORLD_PREFIXES
	)
	var compound: String = "Alto" if new_world else "Nueva"
	for _attempt in 40:
		var root: String = roots[rng.randi_range(0, roots.size() - 1)]
		var roll: float = rng.randf()
		var name: String = root
		if decorative and not prefixes.is_empty() and roll < 0.45:
			name = "%s %s" % [prefixes[rng.randi_range(0, prefixes.size() - 1)], root]
		elif decorative and not prefixes.is_empty() and roll < 0.6:
			name = "%s %s" % [compound, root]
		if not used.has(name):
			used[name] = true
			return name
	# Overflow (a faction owning more provinces than its pool): compound the pool.
	for _attempt in 40:
		var root: String = roots[rng.randi_range(0, roots.size() - 1)]
		var name: String = "%s %s" % [compound, root]
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Tierra %d" % (used.size() + 1)
	used[fallback] = true
	return fallback


## Where each preset's water lies on the period chart, in chart-normalised
## coordinates (x: 0 west → 1 east, y: 0 north → 1 south). A sea zone wears the
## name of the water it lies nearest, so the northern water reads as the North
## Sea and the southern as the Mediterranean rather than by list order
## (wiki: naming § Sea-zone display names, DR-20261113-07).
const OLD_WORLD_SEA_ANCHORS: Dictionary = {
	"Mar del Norte": Vector2(0.42, 0.10),
	"Skagerrak": Vector2(0.46, 0.05),
	"Kattegat": Vector2(0.46, 0.09),
	"Mar Báltico": Vector2(0.62, 0.07),
	"Golfo de Finlandia": Vector2(0.74, 0.05),
	"Canal de la Mancha": Vector2(0.34, 0.28),
	"Mar de Irlanda": Vector2(0.28, 0.22),
	"Océano Atlántico": Vector2(0.06, 0.38),
	"Golfo de Vizcaya": Vector2(0.22, 0.42),
	"Golfo de Cádiz": Vector2(0.20, 0.60),
	"Mar de Alborán": Vector2(0.36, 0.68),
	"Mar Mediterráneo": Vector2(0.48, 0.62),
	"Golfo de León": Vector2(0.32, 0.56),
	"Mar de Liguria": Vector2(0.54, 0.58),
	"Mar Tirreno": Vector2(0.56, 0.68),
	"Mar de Cerdeña": Vector2(0.48, 0.76),
	"Canal de Sicilia": Vector2(0.58, 0.78),
	"Mar Adriático": Vector2(0.64, 0.58),
	"Mar Egeo": Vector2(0.80, 0.70),
	"Mar Negro": Vector2(0.88, 0.54),
}

## The New World chart: the Pacific runs down the west, the Atlantic up the east.
const NEW_WORLD_SEA_ANCHORS: Dictionary = {
	"Mar Pacífico": Vector2(0.14, 0.42),
	"Golfo de California": Vector2(0.10, 0.22),
	"Mar de Cortés": Vector2(0.14, 0.28),
	"Mar del Sur": Vector2(0.20, 0.56),
	"Golfo de Panamá": Vector2(0.40, 0.50),
	"Mar de las Perlas": Vector2(0.40, 0.44),
	"Golfo de Darién": Vector2(0.48, 0.40),
	"Mar de los Caribes": Vector2(0.58, 0.22),
	"Golfo de Honduras": Vector2(0.44, 0.26),
	"Paso del Oeste": Vector2(0.66, 0.14),
	"Bahía de San Salvador": Vector2(0.74, 0.30),
	"Bahía de Todos os Santos": Vector2(0.80, 0.44),
	"Rada de la Esperanza": Vector2(0.62, 0.56),
	"Mar del Plata": Vector2(0.76, 0.70),
	"Mar de Chiloé": Vector2(0.44, 0.82),
	"Estrecho de Magallanes": Vector2(0.66, 0.92),
}


## The region's sea-name presets in declared order (the tie-break order).
static func sea_presets(region_id: int) -> Array[String]:
	var names: Array[String] = []
	names.assign(
		NEW_WORLD_SEA_NAMES
		if region_id == FactionCatalog.NEW_WORLD
		else OLD_WORLD_SEA_NAMES
	)
	return names


## Where one preset's water lies, or the chart's middle when the preset carries
## no anchor (a ruleset that adds a name still gets a usable seat).
static func sea_anchor(region_id: int, name: String) -> Vector2:
	var anchors: Dictionary = (
		NEW_WORLD_SEA_ANCHORS
		if region_id == FactionCatalog.NEW_WORLD
		else OLD_WORLD_SEA_ANCHORS
	)
	return anchors.get(name, Vector2(0.5, 0.5))


## The nearest water among the presets `used` has not spent yet (ties go to the
## preset declared first, so the same chart always names a zone the same way).
static func nearest_water(region_id: int, at: Vector2, used: Dictionary) -> String:
	var best: String = ""
	var best_distance: float = INF
	for name: String in sea_presets(region_id):
		if used.has(name):
			continue
		var distance: float = at.distance_squared_to(sea_anchor(region_id, name))
		if distance < best_distance:
			best_distance = distance
			best = name
	return best


## Name for one sea zone, chosen by where it lies (no RNG: presets are fixed
## lists). `at` is the zone's centre in chart-normalised coordinates. Once every
## preset in the region is spent, the presets take numeric ordinals `(2)`, `(3)`
## … in declared order, so labels stay non-empty and unique.
static func sea_name(used: Dictionary, region_id: int, at: Vector2) -> String:
	var nearest: String = nearest_water(region_id, at, used)
	if nearest != "":
		used[nearest] = true
		return nearest
	var presets: Array[String] = sea_presets(region_id)
	# Every preset is spent: spend them again in declared order with the next
	# free ordinal, then (a chart no size reaches) fall back to a plain ordinal.
	for ordinal in range(2, presets.size() + 2):
		for name: String in presets:
			var candidate: String = "%s (%d)" % [name, ordinal]
			if not used.has(candidate):
				used[candidate] = true
				return candidate
	var fallback: String = "Mar %d" % (used.size() + 1)
	used[fallback] = true
	return fallback
