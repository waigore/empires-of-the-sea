class_name MapPlayPickProse
extends RefCounted
## Shared wording for every counsel-pick surface: one capital and a full stop,
## a prose list join, a capped line that counts the rest (`… and N more`), the
## court line a collection pick prints, and the row order it reads down.
## Domain picks and *Words modules name their own clauses; they do not re-own
## this chrome (REQ-P3-01, REQ-P3-02, REQ-P5-06).

## The most rows one counsel line names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07). A sheet that names more passes
## its own cap to `court_line_capped`; no sheet restates the common one.
const NAMED_LIMIT: int = 3


## `text` as a printed sentence: "the court would …" → "The court would …".
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The pick's own clause as a printed sentence: every surface opens and closes
## the line the same way, so no module re-owns the capital and the full stop
## (REQ-P3-02, REQ-P5-06).
static func sentence_of(pick: Dictionary) -> String:
	return sentence(String(pick.get("line", "")))


## A list read the way prose reads it: "A", "A and B", "A, B and C".
static func join(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() <= 2:
		return " and ".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]


## First `limit` parts in prose, then "and N more" for the rest — so a handset's
## reading stays one line of chrome (REQ-P5-07). Empty when nothing is named.
## When the line is capped it joins the named heads with commas (not "and"),
## matching every sheet that already prints `…, X and N more`. `extra` counts
## crews whose clause a repeat collapsed into one the line already names, so the
## tail still counts every crew behind the sentence (issue #1304).
static func capped(parts: Array[String], limit: int, extra: int = 0) -> String:
	if parts.is_empty() or limit <= 0:
		return ""
	var named: Array[String] = parts.slice(0, mini(parts.size(), limit))
	var more: int = parts.size() - named.size() + maxi(extra, 0)
	if more <= 0:
		return join(parts)
	return "%s and %d more" % [", ".join(named), more]


## Clauses with an exact repeat collapsed into its first, plus the count of
## clauses the repeats stood for: a roster with three crews on one order would
## otherwise read as a stutter, and the tail still counts every crew behind the
## one clause it names (issue #1304).
static func unique_clauses(clauses: Array[String]) -> Dictionary:
	var seen: Dictionary = {}
	var kept: Array[String] = []
	var extra: int = 0
	for clause: String in clauses:
		if clause.is_empty():
			continue
		if seen.has(clause):
			extra += 1
			continue
		seen[clause] = true
		kept.append(clause)
	return {"clauses": kept, "extra": extra}


## The one court line every collection pick prints: `head`, the clauses a sheet
## can name (capped, blanks dropped), then `tail`. Empty when nothing is named —
## a pick with no word never prints a headless sentence (REQ-P3-02, REQ-P5-06).
static func court_line(
	head: String, clauses: Array[String], tail: String = "this turn"
) -> String:
	return court_line_capped(head, clauses, tail, NAMED_LIMIT)


## `court_line` with the sheet's own cap: a wide sheet (manufacture, the realm)
## names more rows than the common three before it counts the rest. The cap is
## the sheet's fact; the capital, the joins and the tail stay here (REQ-P3-02).
static func court_line_capped(
	head: String, clauses: Array[String], tail: String, limit: int, extra: int = 0
) -> String:
	var named: Array[String] = []
	for clause: String in clauses:
		if not clause.is_empty():
			named.append(clause)
	var joined: String = capped(named, limit, extra)
	if joined.is_empty():
		return ""
	if tail.is_empty():
		return "%s %s" % [head, joined]
	return "%s %s %s" % [head, joined, tail]


## The gate a silent pass earns: `waiting` rows stood for an order and the policy
## gave none, so the sheet names that rather than a clause it cannot print. A
## sheet with nothing waiting has nothing to say (REQ-P5-06).
static func gate(waiting: int, rows_key: String, line: String) -> Dictionary:
	if waiting <= 0:
		return {}
	var none: Array[Dictionary] = []
	return {rows_key: none, "line": line}


## A row's key: the chart it stands on and the id its roster minted it. The
## sheet's own heading may name the id differently from the pick entry (a
## squadron heading says `fleet`, its pick entry `fleet_id`), so `sheet_field`
## reads the heading when the entry carries no id of its own.
static func row_key(
	entry: Dictionary, id_field: String, sheet_field: String = ""
) -> String:
	var id: int = int(entry.get(id_field, entry.get(sheet_field, -1)))
	return "%d:%d" % [int(entry.get("region", -1)), id]


## The entries in the order the sheet prints them (`printed`: its own rows or
## groups), so a counsel line reads down the page it answers. An entry the sheet
## does not print keeps the pass's order after them, and the id breaks ties.
static func in_printed_order(
	entries: Array[Dictionary], printed: Array, id_field: String, sheet_field: String = ""
) -> Array[Dictionary]:
	var order: Dictionary = {}
	var index: int = 0
	for raw: Variant in printed:
		var row: Dictionary = raw
		var key: String = row_key(row, id_field, sheet_field)
		if order.has(key):
			continue
		order[key] = index
		index += 1
	if order.is_empty():
		return entries
	var keyed: Array[Dictionary] = entries.duplicate()
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: int = int(order.get(row_key(a, id_field, sheet_field), 1 << 30))
		var right: int = int(order.get(row_key(b, id_field, sheet_field), 1 << 30))
		if left != right:
			return left < right
		return int(a.get(id_field, 0)) < int(b.get(id_field, 0))
	)
	return keyed


## True when a counsel pick may read the crown's session at all: a live,
## unobserved campaign, a chart, relations, and a court that plans. Every pick
## surface answers this first, so no two sheets disagree on when the crown's page
## is silent (REQ-P3-02).
static func crown_ready(play: PlaySession) -> bool:
	if play == null or play.observer_mode or play.campaign_over():
		return false
	if play.world == null or play.diplomacy == null:
		return false
	return AiControl.court_kind(play, play.player_faction) != AiControl.KIND_NONE


## True when a crew-backed counsel pick may read the crown's session: the crown
## gate with a civilian layer and a ledger. Market, estates, people and spy picks
## share this gate so they cannot disagree on when the page is silent
## (REQ-P3-02).
static func crown_crew_ready(play: PlaySession) -> bool:
	if not crown_ready(play) or play.civilian_layer == null:
		return false
	return play.ledger_for(play.player_faction) != null
