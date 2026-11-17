class_name ColonyLedger
extends RefCounted
## The world's colonies: every Tribe a Great Power has bought into its empire,
## who bought it, where it stands and what bars its trade (wiki: diplomacy
## § GP–Tribe Rules — Join Empire, § Boycott; DR-20261117-02). Pure read-only
## projection — it reads the diplomacy record and the chart and never issues an
## order, lifts a boycott or claims a deed (REQ-P3-02, REQ-P3-03).
##
## A colony is not an absorption: the Tribe keeps its provinces, its court and
## its trade, so the reading a crown wants is the one the rules keep apart —
## whose colony it is, the herald's word with the people, the subsidy it takes
## and the courts its suzerain's boycott has shut to it. Every figure is the
## rules' own: the suzerain is `DiplomacyState.colony_of`, the step
## `DiplomacyState.subsidy`, the price terms `DiplomacyCatalog`'s, and the
## boycott record the same directed keys `DiplomacyTrade` reads, so a row can
## never show a bar the clearing does not act on (REQ-P2-03).

## The reading's own filters: who holds the colony and what bars it.
const FILTER_ALL: String = "all"
const FILTER_OURS: String = "ours"
const FILTER_SEALED: String = "sealed"
const FILTER_SUBSIDY: String = "subsidy"
const FILTERS: Array[String] = [FILTER_ALL, FILTER_OURS, FILTER_SEALED, FILTER_SUBSIDY]

const NO_ID: int = -1


## World snapshot in reading order. `regions` is one entry per chart
## ({region, model}), so a colony's place and chart are read off the land the
## Tribe holds. A court the crown has never met prints no row: an undiscovered
## people is nobody's news (`Unknown faction`), never a named colony.
static func snapshot(
	regions: Array[Dictionary], state: DiplomacyState, player: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {FILTER_OURS: 0, FILTER_SEALED: 0, FILTER_SUBSIDY: 0}
	for tribe: int in FactionCatalog.tribe_ids():
		if state == null:
			break
		var suzerain: int = state.colony_of(tribe)
		if suzerain < 0 or not _known(state, player, tribe, suzerain):
			continue
		var row: Dictionary = _row(regions, state, player, tribe, suzerain)
		rows.append(row)
		for flag: String in row["flags"]:
			counts[flag] = int(counts.get(flag, 0)) + 1
	rows.sort_custom(_before)
	return {
		"rows": rows,
		"groups": LedgerRows.group(rows),
		"counts": counts,
		"total": rows.size(),
		"ours": int(counts[FILTER_OURS]),
		"sealed": int(counts[FILTER_SEALED]),
		"subsidies": int(counts[FILTER_SUBSIDY]),
	}


## Rows narrowed to one chart and one filter, grouped under their chart.
static func groups(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> Array[Dictionary]:
	return LedgerRows.groups(data, region_key, matches.bind(filter_key))


static func count(
	data: Dictionary, region_key: String, filter_key: String = FILTER_ALL
) -> int:
	return LedgerRows.count(data, region_key, matches.bind(filter_key))


## How many colonies each filter would show inside one chart, so a chip carries
## its own tally and a zero stays legible rather than hidden.
static func filter_counts(data: Dictionary, region_key: String) -> Dictionary:
	return LedgerRows.counts(data, region_key, FILTERS, matches)


static func matches(row: Dictionary, filter_key: String) -> bool:
	return LedgerRows.flags_match(row, filter_key)


## One-word name of a filter, for its chip and the sheet's count line.
static func filter_label(key: String) -> String:
	match key:
		FILTER_OURS:
			return "Our colonies"
		FILTER_SEALED:
			return "Sealed"
		FILTER_SUBSIDY:
			return "Subsidised"
	return "All colonies"


## The count line under the masthead: what the view leaves of the whole reading.
static func summary(data: Dictionary, region_key: String, shown: int) -> String:
	return "Showing %d of %d colonies %s — %d of our own, %d sealed to a court, %d under subsidy." % [
		shown,
		int(data.get("total", 0)),
		LedgerRows.scope_text(region_key),
		int(data.get("ours", 0)),
		int(data.get("sealed", 0)),
		int(data.get("subsidies", 0)),
	]


## The rule a crown pays by, printed under the roll: what a boycott does to the
## issuer's colonies, in the numbers the clearing and the order gates use.
static func terms_line() -> String:
	return (
		"A boycott shuts every colony of the issuer to the boycotted court: no deal "
		+ "clears between them either way, its aid and its land deeds are refused, and "
		+ "its market terms worsen %d%%." % int(round(DiplomacyCatalog.BOYCOTT_TERMS * 100.0))
	)


## What a colony is, printed beside the rule: it keeps its land, its court and
## its trade, and only the Join Empire price was paid (wiki: diplomacy
## § GP–Tribe Rules — Join Empire).
static func colony_line() -> String:
	return (
		"A colony keeps its provinces, its court and its trade; only the Join "
		+ "Empire price was paid. A favoured pact's terms cover its suzerain alone."
	)


# --- rows -------------------------------------------------------------------


static func _row(
	regions: Array[Dictionary], state: DiplomacyState, player: int, tribe: int, suzerain: int
) -> Dictionary:
	var seat: Dictionary = _seat(regions, tribe)
	var sealed_to: Array[int] = _sealed_to(state, suzerain)
	var subsidy: int = state.subsidy(suzerain, tribe)
	var flags: Array[String] = []
	if suzerain == player:
		flags.append(FILTER_OURS)
	if not sealed_to.is_empty():
		flags.append(FILTER_SEALED)
	if subsidy > 0:
		flags.append(FILTER_SUBSIDY)
	var record: DiplomacyRelation = state.relation(player, tribe)
	return {
		"id": tribe,
		"region": int(seat.get("region", NO_ID)),
		"region_label": FactionCatalog.region_label(int(seat.get("region", NO_ID))),
		"name": FactionCatalog.name_of(tribe),
		"suzerain": suzerain,
		"suzerain_name": FactionCatalog.name_of(suzerain),
		"place": String(seat.get("place", "No province")),
		"province": int(seat.get("province", NO_ID)),
		"provinces": int(seat.get("provinces", 0)),
		"ours": suzerain == player,
		"standing": _standing(record, subsidy),
		"terms": _terms(state, sealed_to),
		"sealed": not sealed_to.is_empty(),
		"sealed_to": sealed_to,
		"subsidy": subsidy,
		"flags": flags,
	}


## The herald's word for the people, never the score, and the subsidy the
## suzerain pays it — the two readings the court's own page prints (REQ-P5-02).
static func _standing(record: DiplomacyRelation, subsidy: int) -> String:
	var word: String = record.meter_label() if record != null else "No envoy"
	if subsidy <= 0:
		return word
	return "%s · subsidy %d%%" % [word, subsidy]


## What bars the colony's trade: the courts its suzerain's boycott has shut to
## it, or the whole book when none has. The bar is the clearing's own key, read
## through `DiplomacyBoycott.blocked`'s record (REQ-P2-03).
static func _terms(state: DiplomacyState, sealed_to: Array[int]) -> String:
	if sealed_to.is_empty():
		return "Open to every court"
	var names: PackedStringArray = []
	for court: int in sealed_to:
		names.append(FactionCatalog.name_of(court))
	return "Sealed to %s" % ", ".join(names)


## The courts the colony's suzerain has boycotted, sorted: a boycott applies to
## every colony that court holds (wiki: diplomacy § GP–Tribe — Boycott, R6).
static func _sealed_to(state: DiplomacyState, suzerain: int) -> Array[int]:
	var targets: Array[int] = []
	for key: String in state.boycotts.keys():
		var courts: Vector2i = DiplomacyKeys.directed_courts(key)
		if courts.x != suzerain or courts.y == suzerain:
			continue
		targets.append(courts.y)
	targets.sort()
	return targets


## Where the people stand: the capital province the Tribe holds, its chart and
## how many provinces answer it. A Tribe whose land the chart does not hold falls
## back to its own published region, so the row never reads "Uncharted" for a
## colony that exists.
static func _seat(regions: Array[Dictionary], tribe: int) -> Dictionary:
	var best: Dictionary = {}
	var count: int = 0
	for entry: Dictionary in regions:
		var model := entry.get("model") as MapModel
		if model == null:
			continue
		var region: int = int(entry.get("region", model.region_id))
		for province: ProvinceState in model.provinces:
			if province == null or province.owner != tribe:
				continue
			count += 1
			if best.is_empty() or (province.capital and not bool(best.get("capital", false))):
				best = {
					"region": region,
					"place": String(province.name),
					"province": province.id,
					"capital": province.capital,
				}
	if best.is_empty():
		return {
			"region": FactionCatalog.region_of(tribe),
			"place": "No province",
			"province": NO_ID,
			"provinces": 0,
		}
	best["provinces"] = count
	return best


## An undiscovered people is nobody's news: the row prints only when the crown
## has an envoy with the Tribe or with the court that bought it.
static func _known(state: DiplomacyState, player: int, tribe: int, suzerain: int) -> bool:
	return state.has_relation(player, tribe) or state.has_relation(player, suzerain)


# --- assembly ---------------------------------------------------------------


## Reading order: the crown's own colonies first, then the sealed, then by the
## court that holds them and the people's own id — so a crown reads the trade it
## can still make before the trade a rival has shut.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a["ours"]) != bool(b["ours"]):
		return bool(a["ours"])
	if bool(a["sealed"]) != bool(b["sealed"]):
		return not bool(a["sealed"])
	if int(a["suzerain"]) != int(b["suzerain"]):
		return int(a["suzerain"]) < int(b["suzerain"])
	return int(a["id"]) < int(b["id"])
