class_name MoneyText
extends RefCounted
## The court's purse in one hand (REQ-P3-01): whole-number grouping, the pound
## mark the diplomacy pages print and the cost line a muster or yard row shows
## before the press. The catalogs, the ledgers and the panels all read their
## figures through here, so no page can grow a private formatter that groups or
## signs a sum differently (REQ-P2-03, REQ-P3-03).
##
## Pure text over integers: no nodes, no economy, so a suite can read it alone.


## "1234567" -> "1,234,567"; keeps a leading minus for debts.
static func thousands(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


## "£1,234": the diplomacy pages' purse.
static func money(value: int) -> String:
	return "£%s" % thousands(value)


## "1,234 ducats": the muster and market ledgers' purse.
static func ducats(value: int) -> String:
	return "%s ducats" % thousands(value)


## "8,000 ducats · 2 Lumber · 1 Fabric · 1 worker": the cost line a yard or
## muster row prints before the press. Materials read in the catalog's own
## labels and in the order the row lists them; the worker part is dropped when
## the row spends no headcount.
static func cost_line(gold: int, materials: Dictionary, workers: int = 0) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(ducats(gold))
	for commodity: Variant in materials.keys():
		parts.append(
			"%d %s"
			% [int(materials[commodity]), CommodityCatalog.label(String(commodity))]
		)
	if workers > 0:
		parts.append("%d worker%s" % [workers, "" if workers == 1 else "s"])
	return " · ".join(parts)
