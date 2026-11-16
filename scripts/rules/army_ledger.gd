class_name ArmyLedger
extends RefCounted
## The crown's army, regiment by regiment: every regiment it fields in both
## charts, the standard it marches under, its class and its own condition
## (wiki: military-armies § The muster roll, § The regiments behind an army;
## DR-20261116-07). Pure read-only projection of the layer rosters — it never
## musters, detaches, dismisses or marches a regiment (REQ-P3-02, REQ-P3-03).
##
## No number here is recomputed: a regiment's line is
## `RegimentCatalog.detail_line`, its condition is `ArmyState.condition_of`, its
## colours are `RegimentDecorations`, and its standard's strength and food are
## `ArmyForce.side_strength` and `RegimentCatalog.food_upkeep`, so a row can
## never print a figure the battle or the larder would not use (REQ-P2-03).
##
## A regiment's orders are its standard's, so the standing (where it stands,
## whether it marched) is read once on the army heading, and the row prints only
## what is the regiment's own: its title, its class, its condition and its
## colours.

## The reading's own filters: the three kinds of regiment a crown fields.
const READING_ALL: String = "all"
const READING_FOOT: String = "foot"
const READING_HORSE: String = "horse"
const READING_GUNS: String = "guns"
const READINGS: Array[String] = [READING_ALL, READING_FOOT, READING_HORSE, READING_GUNS]


## Whole-army snapshot in reading order. `groups` nests each standard's rows
## under it, so the sheet prints one heading per army and one row per regiment.
static func snapshot(
	world: WorldMap,
	army_regions: MapRegionTable,
	fleet_regions: MapRegionTable,
	faction: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var groups: Array[Dictionary] = []
	var by_region: Dictionary = {}
	var armies: Dictionary = {}
	var strength: float = 0.0
	var food: int = 0
	if world == null or army_regions == null:
		return _empty(rows, groups, by_region, armies, strength, food)
	for region: int in world.region_count():
		var model: MapModel = world.region(region)
		if model == null:
			continue
		# The carrying squadron names an embarked standard's place, so the
		# chart's own roster is read once here (wiki: military-armies).
		var fleets: Array[FleetState] = LedgerRows.stored_fleets(
			fleet_regions, region, faction
		)
		for raw: Variant in LedgerRows.stored_rows(army_regions, region):
			var army := raw as ArmyState
			if army == null or army.owner != faction:
				continue
			var group: Dictionary = _standard(model, army, region, fleets)
			var group_rows: Array[Dictionary] = []
			for regiment_id: String in army.regiments:
				var row: Dictionary = _regiment_row(army, regiment_id, group)
				group_rows.append(row)
				_count(by_region, region, String(row["reading"]))
			group_rows.sort_custom(_before_regiment)
			# The flat reading follows the order the sheet prints, so a reader
			# that walks `rows` sees the same line the page does.
			rows.append_array(group_rows)
			group["rows"] = group_rows
			armies[region] = int(armies.get(region, 0)) + 1
			strength += float(group["strength"])
			food += int(group["food"])
			# A standard with no regiment yet has no row of its own; the count
			# line still names the army, so an empty muster is never silent.
			if not group_rows.is_empty():
				groups.append(group)
	groups.sort_custom(_before_group)
	return {
		"rows": rows,
		"groups": groups,
		"by_region": by_region,
		"armies": armies,
		"strength": strength,
		"food": food,
		"total": rows.size(),
	}


## Standards narrowed to one chart and one reading, each keeping only the
## regiments the reading names. A standard with no row left drops out.
static func groups(
	data: Dictionary, region_key: String, reading: String = READING_ALL
) -> Array[Dictionary]:
	return LedgerRows.groups(data, region_key, matches.bind(reading))


static func count(data: Dictionary, region_key: String, reading: String = READING_ALL) -> int:
	return LedgerRows.count(data, region_key, matches.bind(reading))


## How many regiments each reading would show inside one chart, so a chip
## carries its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return LedgerRows.counts(data, region_key, READINGS, matches)


## How many standards the crown fields inside one chart, a standard with no
## regiment included: the count line reads the army, not only the men on it.
static func army_count(data: Dictionary, region_key: String) -> int:
	var total: int = 0
	for raw: Variant in (data.get("armies", {}) as Dictionary).keys():
		if LedgerRows.region_matches(int(raw), region_key):
			total += int(data["armies"][raw])
	return total


static func matches(row: Dictionary, reading: String) -> bool:
	return LedgerRows.field_matches(row, "reading", reading)


## The reading's own word, for its chip and the sheet's count line.
static func reading_label(key: String) -> String:
	match key:
		READING_FOOT:
			return "Foot"
		READING_HORSE:
			return "Horse"
		READING_GUNS:
			return "Guns"
	return "All regiments"


# --- readings ---------------------------------------------------------------


## The count line: the view against the chart it is read in, with the army's own
## totals when the reading shows every regiment (REQ-P5-05). A narrowed reading
## prints no strength or food, because a standard's strength and its larder bill
## belong to all its regiments; the totals are summed over the standards the
## chart holds, so a one-chart view never prints the other chart's army.
static func summary(
	data: Dictionary, region_key: String, reading: String = READING_ALL
) -> String:
	var in_scope: int = count(data, region_key, READING_ALL)
	var shown: int = count(data, region_key, reading)
	var scope: String = scope_text(region_key)
	var armies: int = army_count(data, region_key)
	var standards: String = "%d standard%s" % [armies, "" if armies == 1 else "s"]
	if reading != READING_ALL and not reading.is_empty():
		return "Showing %d of %d regiments %s — %s only." % [
			shown, in_scope, scope, reading_label(reading).to_lower()
		]
	var counts: Dictionary = filter_counts(data, region_key)
	var strength: float = 0.0
	var food: int = 0
	for group: Dictionary in groups(data, region_key, READING_ALL):
		strength += float(group["strength"])
		food += int(group["food"])
	return (
		"Showing %d of %d regiments in %s %s — %d foot, %d horse, %s · "
		+ "%.1f strength · %d food a turn."
	) % [
		shown,
		in_scope,
		standards,
		scope,
		int(counts.get(READING_FOOT, 0)),
		int(counts.get(READING_HORSE, 0)),
		_plural(int(counts.get(READING_GUNS, 0)), "gun"),
		strength,
		food,
	]


static func scope_text(region_key: String) -> String:
	return LedgerRows.scope_text(region_key)


## The rule a crown pays by sits on the sheet, never in a hover: chevrons raise
## a regiment's firepower, a citation holds its place in the line, and every
## regiment eats its food each turn (wiki: military-units § Stats, combat
## § Strength, military-generals § Regiment Economy).
static func note() -> String:
	return (
		"A regiment's chevrons raise its firepower a tenth each, a citation "
		+ "holds its place in the line, and every regiment eats its food each "
		+ "turn — the same figures the battle and the larder use."
	)


# --- rows -------------------------------------------------------------------


## One standard's standing: the army it is, where it stands and whether it
## marched. Every regiment of it reads this heading before its own row.
static func _standard(
	model: MapModel, army: ArmyState, region: int, fleets: Array[FleetState]
) -> Dictionary:
	var one: Array[ArmyState] = [army]
	return {
		"region": region,
		"region_label": FactionCatalog.region_label(region),
		"army": army.id,
		"title": "Home Army" if army.home else "Field army",
		"heading": "%s  ·  %s" % [
			FactionCatalog.region_label(region).to_upper(),
			("HOME ARMY" if army.home else "FIELD ARMY"),
		],
		"place": LedgerRows.army_place(model, army, fleets),
		"standing": LedgerRows.army_standing(army),
		"regiments": army.count(),
		"strength": ArmyForce.side_strength(one),
		"food": _food(army),
	}


static func _regiment_row(
	army: ArmyState, regiment_id: String, group: Dictionary
) -> Dictionary:
	var type_id: String = army.type_of(regiment_id)
	var reading: String = _reading_of(type_id)
	var condition: Dictionary = army.condition_of(regiment_id)
	return {
		"regiment": regiment_id,
		"name": RegimentNames.of(army, regiment_id),
		"type": type_id,
		"class": RegimentCatalog.display_name(type_id),
		"category": RegimentCatalog.category_name(type_id),
		"reading": reading,
		"role_label": _role_label(reading),
		"region": int(group["region"]),
		"region_label": String(group["region_label"]),
		"army": army.id,
		"army_title": String(group["title"]),
		"place": String(group["place"]),
		"line": RegimentCatalog.detail_line(type_id),
		"state": _condition_text(army, regiment_id, condition),
		"health": int(condition["hp"]),
		"max_health": int(condition["max"]),
		"medals": int(condition["medals"]),
		"cited": RegimentDecorations.citations(army, regiment_id),
		"strength": RegimentCatalog.strength(type_id),
		"flags": [reading],
	}


## What a regiment is for, in the rules' own three kinds: the men who hold the
## line, the horse who break it, and the guns who open it.
static func _reading_of(type_id: String) -> String:
	if RegimentCatalog.is_cavalry(type_id):
		return READING_HORSE
	if RegimentCatalog.is_artillery(type_id):
		return READING_GUNS
	return READING_FOOT


static func _role_label(reading: String) -> String:
	match reading:
		READING_HORSE:
			return "HORSE"
		READING_GUNS:
			return "GUNS"
	return "FOOT"


## A regiment's own condition: the health it holds, the chevrons it has won and
## the colours it wears. Every figure is the rules' own (`condition_of`, the
## citation step), so the sheet never names a weight the battle would not pay.
static func _condition_text(
	army: ArmyState, regiment_id: String, condition: Dictionary
) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d/%d health" % [int(condition["hp"]), int(condition["max"])])
	var medals: int = int(condition["medals"])
	if medals > 0:
		parts.append(_plural(medals, "chevron"))
	var rank: String = RegimentDecorations.rank(army, regiment_id)
	if not rank.is_empty():
		var step: int = roundi(
			(RegimentDecorations.strength_multiplier(army, regiment_id) - 1.0) * 100.0
		)
		parts.append("%s +%d%%" % [rank, step])
	return " · ".join(parts)


## The food the whole standard eats a turn, summed from the catalogue's own
## upkeep (wiki: military-generals § Regiment Economy).
static func _food(army: ArmyState) -> int:
	var total: int = 0
	for regiment_id: String in army.regiments:
		total += RegimentCatalog.food_upkeep(army.type_of(regiment_id))
	return total


static func _plural(count: int, word: String) -> String:
	return "%d %s" % [count, word if count == 1 else word + "s"]


# --- assembly ---------------------------------------------------------------


static func _count(by_region: Dictionary, region: int, reading: String) -> void:
	var counts: Dictionary = by_region.get(region, {
		READING_FOOT: 0, READING_HORSE: 0, READING_GUNS: 0,
	})
	counts[reading] = int(counts.get(reading, 0)) + 1
	by_region[region] = counts


static func _empty(
	rows: Array[Dictionary],
	groups: Array[Dictionary],
	by_region: Dictionary,
	armies: Dictionary,
	strength: float,
	food: int
) -> Dictionary:
	return {
		"rows": rows,
		"groups": groups,
		"by_region": by_region,
		"armies": armies,
		"strength": strength,
		"food": food,
		"total": rows.size(),
	}


## The foot lead, then the horse, then the guns; inside a kind the heavier class
## — the catalogue's own strength — then the class name, then the instance id,
## so a standard reads the same way every turn and a guard never reads under a
## levy (wiki: military-armies § The regiments behind an army).
static func _before_regiment(a: Dictionary, b: Dictionary) -> bool:
	var left: int = _reading_rank(String(a["reading"]))
	var right: int = _reading_rank(String(b["reading"]))
	if left != right:
		return left < right
	var heavy: float = float(a["strength"])
	if not is_equal_approx(heavy, float(b["strength"])):
		return heavy > float(b["strength"])
	if String(a["class"]) != String(b["class"]):
		return String(a["class"]) < String(b["class"])
	return _unit_before(String(a["regiment"]), String(b["regiment"]))


static func _reading_rank(reading: String) -> int:
	match reading:
		READING_HORSE:
			return 1
		READING_GUNS:
			return 2
	return 0


## Regiments are minted as `unit_<n>` (wiki: military-armies), so the reading
## orders them by their number and not by their spelling: unit_9 reads before
## unit_10. An id that carries no number falls back to its text.
static func _unit_before(a: String, b: String) -> bool:
	var left: int = _unit_number(a)
	var right: int = _unit_number(b)
	if left >= 0 and right >= 0 and left != right:
		return left < right
	return a < b


## The number in a regiment instance id, or -1 when the id is not `unit_<n>`.
static func _unit_number(regiment_id: String) -> int:
	if not regiment_id.begins_with("unit_"):
		return -1
	var tail: String = regiment_id.substr(5)
	if not tail.is_valid_int():
		return -1
	return tail.to_int()


## The seat leads its chart, then the field armies by id, so the same muster
## reads the same way every turn.
static func _before_group(a: Dictionary, b: Dictionary) -> bool:
	if int(a["region"]) != int(b["region"]):
		return int(a["region"]) < int(b["region"])
	if String(a["title"]) != String(b["title"]):
		return String(a["title"]) == "Home Army"
	return int(a["army"]) < int(b["army"])
