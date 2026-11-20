class_name Gazette
extends RefCounted
## Builds one turn's Gazette sheet from the resolved turn's public record
## (wiki: the-gazette; DR-20261110-14). It selects and narrates: every rule
## outcome has already been decided elsewhere and arrives here as a structured
## record, so prose can never contradict combat, diplomacy or research
## (REQ-P2-03). Sources own their desks — [GazetteDiplomacy], [GazetteBattle],
## [GazetteCourt], [GazetteMuster] — and this class keeps class order and the
## push that prints a line (REQ-P3-01).
##
## Classification is exclusive and ordered — Our court (the crown is a party),
## then World (a public epoch-scale fact), then Courts of interest (a watched
## court is a party). Display order is World, Our court, Courts of interest,
## with resolution order kept inside each class.

enum Class { WORLD, COURT, INTEREST }


## One turn's sheet, ready to file and print: `{turn, items}` with the items in
## display order. A turn with nothing worth printing yields an empty item list,
## which the caller still archives so the history has no gaps.
##
## `research` maps a faction to the technologies it finished; `richness` is the
## crown's deed income the turn summary named; `raids` are MapPlayRaids reports.
## `charts` is the crown's own chart: a watched court's battle prints only where
## the crown has the place at fogged or better (wiki: the-gazette § What the
## crown can know; DR-20261110-28). A caller with no chart is a headless fixture.
## `musters` are the Build/work records the crown's own orders delivered.
static func collect(
	viewer: int,
	turn: int,
	world: WorldMap,
	state: DiplomacyState,
	watched: Array[int],
	land_battles: Array,
	naval_battles: Array,
	falls: Array,
	research: Dictionary,
	richness: int,
	raids: Array,
	charts: CourtCharts = null,
	musters: Array = []
) -> Dictionary:
	var pages: Array[Array] = [[], [], []]
	_diplomacy(pages, viewer, turn, state, watched)
	GazetteBattle.land(pages, viewer, world, state, land_battles, watched, charts)
	GazetteBattle.naval(pages, viewer, world, state, naval_battles, watched, charts)
	_falls(pages, viewer, state, falls)
	GazetteCourt.studies(pages, viewer, research)
	GazetteCourt.treasury(pages, richness)
	GazetteCourt.raids(pages, raids)
	GazetteMuster.push(pages, musters)
	var items: Array[Dictionary] = []
	for cls: int in [Class.WORLD, Class.COURT, Class.INTEREST]:
		for entry: Variant in pages[cls]:
			items.append(entry)
	return {"turn": turn, "items": items}


## True when a sheet prints nothing: the overlay is skipped, the archive entry
## is not (wiki: the-gazette § When it appears).
static func is_empty(sheet: Dictionary) -> bool:
	return (sheet.get("items", []) as Array).is_empty()


## Heading the plate prints above a class's run of lines.
static func heading(cls: int) -> String:
	match cls:
		Class.WORLD:
			return "THE WORLD"
		Class.COURT:
			return "OUR COURT"
	return "COURTS OF INTEREST"


# --- sources -----------------------------------------------------------------


static func _diplomacy(
	pages: Array[Array], viewer: int, turn: int, state: DiplomacyState, watched: Array[int]
) -> void:
	var sorted: Dictionary = GazetteDiplomacy.classify(viewer, turn, state, watched)
	for entry: Array in [[Class.WORLD, "world"], [Class.COURT, "court"], [Class.INTEREST, "interest"]]:
		for item: Variant in sorted[String(entry[1])]:
			var row: Dictionary = item
			push(pages, int(entry[0]), String(row["kind"]), row["rec"] as Dictionary)


## A Great Power's fall is the World page's news; the rules of who may be named
## live with the rest of the diplomacy desk (wiki: the-gazette § Item catalog).
static func _falls(pages: Array[Array], viewer: int, state: DiplomacyState, falls: Array) -> void:
	for entry: Dictionary in GazetteDiplomacy.falls(viewer, state, falls):
		push(pages, Class.WORLD, String(entry["kind"]), entry["rec"] as Dictionary)


# --- internals ---------------------------------------------------------------


static func push(pages: Array[Array], cls: Class, kind: String, rec: Dictionary) -> void:
	rec["kind"] = kind
	var text: String = GazetteCopy.line(rec)
	if not text.is_empty():
		pages[cls].append({"class": cls, "kind": kind, "text": text})
