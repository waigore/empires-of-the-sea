class_name MoneyText
extends RefCounted
## The court's purse in one hand (REQ-P3-01): whole-number grouping, the one
## word the crown's money prints ("1,234 ducats"), the cost line a muster or
## yard row shows before the press, and the plural every count line in the
## crown's sheets shares. The catalogs, the ledgers and the panels all read
## their figures and their "1 regiment / 3 regiments" through here, so no page
## can grow a private formatter that groups, signs or pluralises differently
## (REQ-P2-03, REQ-P3-03).
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


## "1,234 ducats": the crown's purse, wherever a page names what it holds or
## what an order costs. One word, one grouping, so the bar, the college, the
## ledger, the province sheet and the court can never print four forms.
static func ducats(value: int) -> String:
	return "%s ducats" % thousands(value)


## "+1,234" / "-1,234" / "0": a per-turn movement, grouped and signed, for a
## line that names what the purse gains or loses.
static func signed(value: int) -> String:
	if value == 0:
		return "0"
	return ("+" if value > 0 else "") + thousands(value)


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
		parts.append("%d worker%s" % [workers, plural(workers)])
	return " · ".join(parts)


## The ending a count gives a following noun: "" for one, "s" for the rest.
## Every count line in the crown's sheets runs through this one call, so a
## sentence can never print "1 regiments" (REQ-P3-01).
static func plural(count: int) -> String:
	return "" if count == 1 else "s"


## The third-person "s" a sentence gives a verb about a count: "1 row waits",
## "3 rows wait". A verb and a noun take opposite endings, so both live here
## instead of as a bare ternary in every line that names a wait.
static func verb_s(count: int) -> String:
	return "" if count != 1 else "s"


## "1 regiment" / "3 regiments": the count and its noun in one word pair, for
## a line that names what it counts.
static func counted(count: int, word: String) -> String:
	if word.is_empty():
		return str(count)
	return "%d %s%s" % [count, word, plural(count)]
