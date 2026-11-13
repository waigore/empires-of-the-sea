class_name GazetteMuster
extends RefCounted
## Files the crown's Build/work records on Our court page: the worker the
## workshops trained, the civilian engaged at the capital, the regiment the drill
## yard mustered and the hull the slips launched. The records arrive already
## decided and narrated by the rules; this only places them, so the sheet's
## classes and order stay [Gazette]'s (wiki: the-gazette § Item catalog).


static func push(pages: Array[Array], musters: Array) -> void:
	for raw: Variant in musters:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = raw
		Gazette.push(pages, Gazette.Class.COURT, String(rec.get("kind", "")), rec)
