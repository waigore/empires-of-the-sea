class_name MapNaming
extends RefCounted
## Period place-name pools per region (wiki: naming, tile-map-and-generation).
## Kept apart from generation so the generator stays focused and under the P3
## size bar.

const OLD_WORLD_ROOTS: Array[String] = [
	"Cádiz", "Marcos", "Cruz", "Rica", "Cartagena", "Veracruz", "Habana", "Domingo",
	"Trujillo", "Panamá", "Juan", "Cumaná", "Maracaibo", "Coro", "Margarita", "Trinidad",
	"Santiago", "Isabel", "Fernando", "Agustín", "Miguel", "Cristóbal", "Antonio", "Lucía",
	"Elena", "Rosa", "Pedro", "Andrés", "Felipe", "Blas", "Jerónimo", "Catalina",
]

const OLD_WORLD_PREFIXES: Array[String] = [
	"San", "Santa", "Puerto", "Villa", "Nueva", "Real"
]

const NEW_WORLD_ROOTS: Array[String] = [
	"Tenochtitlan", "Texcoco", "Tlacopan", "Cholula", "Tikal", "Uxmal", "Tulum",
	"Cusco", "Quito", "Tumbes", "Chimú", "Bacatá", "Tairona", "Boriquén", "Xaragua",
	"Maguana", "Cibao", "Arauco", "Purén", "Itzá", "Copán", "Chen", "Cempoala",
]

const NEW_WORLD_PREFIXES: Array[String] = ["Valle", "Sierra", "Costa", "Monte", "Río"]

const OLD_WORLD_SEA_NAMES: Array[String] = [
	"Mar del Norte", "Golfo de las Perlas", "Mar Caribe", "Bahía de Cádiz",
	"Estrecho de Gibraltar", "Mar de las Antillas", "Golfo de México", "Océano Atlántico",
	"Mar Mediterráneo", "Canal de las Bahamas", "Mar de los Sargazos", "Golfo de Guinea",
	"Mar Tirreno", "Bahía de Vizcaya", "Canal de la Mancha", "Mar Báltico",
	"Golfo de León", "Mar de Alborán", "Mar de Azov", "Golfo de Cádiz",
]

const NEW_WORLD_SEA_NAMES: Array[String] = [
	"Mar del Sur", "Golfo de Panamá", "Golfo de California", "Mar del Plata",
	"Estrecho de Magallanes", "Mar Pacífico", "Mar de los Caribes", "Golfo de Darién",
	"Bahía de Todos os Santos", "Paso del Oeste", "Mar de las Perlas", "Golfo de Honduras",
	"Mar de Cortés", "Rada de la Esperanza", "Bahía de San Salvador", "Mar de Chiloé",
]


## Unique land-province name for a region; deterministic for a given RNG state.
static func province_name(
	used: Dictionary, region_id: int, rng: RandomNumberGenerator
) -> String:
	var new_world: bool = region_id == FactionCatalog.NEW_WORLD
	var roots: Array[String] = NEW_WORLD_ROOTS if new_world else OLD_WORLD_ROOTS
	var prefixes: Array[String] = (
		NEW_WORLD_PREFIXES if new_world else OLD_WORLD_PREFIXES
	)
	var compound: String = "Alto" if new_world else "Nueva"
	for _attempt in 40:
		var root: String = roots[rng.randi_range(0, roots.size() - 1)]
		var roll: float = rng.randf()
		var name: String = root
		if roll < 0.45:
			name = "%s %s" % [prefixes[rng.randi_range(0, prefixes.size() - 1)], root]
		elif roll < 0.6:
			name = "%s %s" % [compound, root]
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Tierra %d" % (used.size() + 1)
	used[fallback] = true
	return fallback


## Unique sea-zone name for a region (no RNG: the pools are fixed lists).
static func sea_name(used: Dictionary, region_id: int) -> String:
	var names: Array[String] = (
		NEW_WORLD_SEA_NAMES
		if region_id == FactionCatalog.NEW_WORLD
		else OLD_WORLD_SEA_NAMES
	)
	for name: String in names:
		if not used.has(name):
			used[name] = true
			return name
	var fallback: String = "Mar %d" % (used.size() + 1)
	used[fallback] = true
	return fallback
