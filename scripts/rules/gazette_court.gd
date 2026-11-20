class_name GazetteCourt
extends RefCounted
## Our-court Gazette sources that are not fights or diplomacy: finished studies,
## deed income, and raids the crown took or suffered (wiki: the-gazette § Item
## catalog). Records arrive already decided; this only files them on Our court
## page so [Gazette] keeps class order (REQ-P2-03, REQ-P3-01).


## Only the crown's own studies print. Another court's finished technology is
## not public news: it stays the spy's court report and the dossier's evidence
## (wiki: the-gazette § What the crown can know; civilian-units § Spy;
## DR-20261110-28).
static func studies(pages: Array[Array], viewer: int, research: Dictionary) -> void:
	var raw: Variant = research.get(viewer, [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for tech: Variant in raw as Array:
		Gazette.push(
			pages,
			Gazette.Class.COURT,
			"techFinished",
			{
				"who": GazetteCopy.CROWN,
				"label": TechCatalog.display_name(String(tech)),
				"self_act": true,
			}
		)


static func treasury(pages: Array[Array], richness: int) -> void:
	if richness <= 0:
		return
	Gazette.push(pages, Gazette.Class.COURT, "richesRendered", {"amount": richness})


## Raids are the crown's own until the rules say otherwise, so both directions
## print on Our court page (wiki: the-gazette § Item catalog — Our court).
static func raids(pages: Array[Array], raids: Array) -> void:
	for raw: Variant in raids:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var raid: Dictionary = raw
		var place: String = String(raid.get("zone_name", "")).strip_edges()
		if place.is_empty():
			place = "open water"
		var prize: String = BattleReport.cargo_of(raid.get("losses", {}) as Dictionary)
		var sunk: String = BattleReport.sunk_of(raid.get("hulls_lost", []))
		var kind: String = "raidPrize" if String(raid.get("kind", "")) == "prize" else "raidSuffered"
		Gazette.push(pages, Gazette.Class.COURT, kind, {"place": place, "prize": prize, "sunk": sunk})
