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


## Sea-zone display name for the zone standing `index`th in its region's sorted
## local-id order (wiki: naming § Sea-zone display names): the region preset in
## declared order, cycling onto it again with a numeric ordinal when a region has
## more zones than the preset has names — `(2)`, `(3)`, … — so every zone keeps a
## non-empty, stable label and no shuffle ever decides a name.
static func sea_name(index: int, region_id: int) -> String:
	var names: Array[String] = (
		NEW_WORLD_SEA_NAMES
		if region_id == FactionCatalog.NEW_WORLD
		else OLD_WORLD_SEA_NAMES
	)
	if names.is_empty():
		return "Mar %d" % (index + 1)
	var cycle: int = index / names.size()
	var name: String = names[index % names.size()]
	if cycle <= 0:
		return name
	return "%s (%d)" % [name, cycle + 1]
