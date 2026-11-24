class_name DeedBar
extends RefCounted
## The province sheet's Deeds row: who has bought land in this province and how
## many tiles each holds (wiki: diplomacy § GP–Minor Rules § Intervention —
## purchased land is a stake; REQ-P2-03, REQ-P5-03).
##
## The counts are [DeedProtection.province_holders]', so the row can never name a
## holding the intervention trial would not count.


## The province sheet's Deeds row: "England 2 tiles · Portugal 1 tile", or "" for
## a province no crown has bought land in — the row hides rather than printing an
## absence.
static func holders(deeds: Dictionary) -> String:
	var parts: PackedStringArray = []
	for raw: Variant in deeds.keys():
		var tiles: int = int(deeds[raw])
		parts.append(
			"%s %d tile%s" % [
				FactionCatalog.name_of(int(raw)), tiles, "" if tiles == 1 else "s",
			]
		)
	return " · ".join(parts)
