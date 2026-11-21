class_name MapPlayMarketPick
extends RefCounted
## The trade the court's own market pass would book this phase: the offers and
## bids `MapPlayEconomyCourtBook.trade` stages at the turn's close, named before
## the crown presses a row (wiki: world-market § Trade orders; DR-20261121-09).
##
## The reading is not a second opinion: it is `trade_plan` — the plan `trade`
## stages — asked over a court read through `MapPlayEconomyCourt.draft` and
## `rehearse`, the same figures the pass plans with, so the sheet cannot name a
## trade the pass would not book (REQ-P2-03, REQ-P3-03).
##
## A reading only: nothing here stages an order, spends a hold or pays a ducat,
## and the crown still presses her own rows (REQ-P5-06).

## The plan books at least one row: the phase would offer and/or bid.
const KIND_TRADE: String = "trade"
## The plan books nothing: the stores already meet the reserve it keeps.
const KIND_QUIET: String = "quiet"

## The most goods one side names before it counts the rest, so a handset's
## reading stays one line of chrome (REQ-P5-07).
const NAMED_LIMIT: int = 3

const QUIET_LINE: String = (
	"the court would trade nothing this phase — its stores already meet the "
	+ "reserve it keeps"
)
## At war the footing holds the speculative top-up shut (DR-20261117-01): the
## sheet names the bar rather than an empty page.
const FOOTING_LINE: String = (
	"the court would bid nothing this phase — at war, its top-up waits on the front"
)


## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession) -> String:
	return sentence(String(pick(play).get("line", "")))


## `text` as a printed sentence: "the court would offer …" → "The court would offer …".
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## The ledger's pick as the MARKET tab prints it: `{kind, offers, bids, line}`,
## where each row map is commodity → units. Empty when the session runs no
## planner for the crown, an observer session, a decided campaign, a crown with
## no ledger or a session with no civilian layer.
static func pick(play: PlaySession) -> Dictionary:
	if play == null or play.world == null or play.campaign_over():
		return {}
	if play.observer_mode or play.civilian_layer == null:
		return {}
	var faction: int = play.player_faction
	if play.ledger_for(faction) == null:
		return {}
	if AiControl.court_kind(play, faction) == AiControl.KIND_NONE:
		return {}
	var court: MapPlayEconomyCourt = MapPlayEconomyCourt.draft(
		play, faction, MapPlayEconomyAi._market(play)
	)
	court.rehearse()
	return of(MapPlayEconomyCourtBook.trade_plan(court))


## The pick, worded off the pretended plan alone: the rows the plan books in the
## catalogue order the page prints them, or the gate that leaves the book empty.
## Pure — a sheet and its suite drive it without a session.
static func of(drafted: Dictionary) -> Dictionary:
	if drafted.is_empty():
		return {}
	var plan: Dictionary = drafted.get("plan", {}) as Dictionary
	if plan.is_empty():
		return {}
	var offers: Dictionary = _rows(plan.get("offers"))
	var bids: Dictionary = _rows(plan.get("bids"))
	var blocked: bool = drafted.has("bids_blocked")
	var kind: String = (
		KIND_QUIET if offers.is_empty() and bids.is_empty() else KIND_TRADE
	)
	return {
		"kind": kind,
		"offers": offers,
		"bids": bids,
		"line": trade_line(offers, bids, blocked),
	}


## "the court would offer Grain ×2 and bid Cast Iron ×3 this phase". A side the
## plan books nothing for is named as such — an empty book reads as advice, not
## as a page the crown has to interpret. `blocked` is the footing's own refusal
## (the speculation slot, DR-20261117-01).
static func trade_line(offers: Dictionary, bids: Dictionary, blocked: bool = false) -> String:
	var offer_part: String = list_line(offers, "offer")
	var bid_part: String = list_line(bids, "bid")
	if not offer_part.is_empty() and not bid_part.is_empty():
		return "the court would %s and %s this phase" % [offer_part, bid_part]
	if not offer_part.is_empty():
		var tail: String = (
			" — at war, its bids wait on the front" if blocked
			else ", and bid nothing"
		)
		return "the court would %s this phase%s" % [offer_part, tail]
	if not bid_part.is_empty():
		return "the court would %s this phase and offer nothing" % bid_part
	return FOOTING_LINE if blocked else QUIET_LINE


## "offer Grain ×2 and Lumber ×1": one side of the book in the catalogue's own
## order — the order the page prints its rows in — and beyond three it counts the
## rows it cannot name (`… and 1 more`) so a rich plan stays one line of chrome.
static func list_line(rows: Dictionary, verb: String) -> String:
	var named: Array[String] = []
	var hidden: int = 0
	for id: String in CommodityCatalog.all_ids():
		if not rows.has(id):
			continue
		if named.size() >= NAMED_LIMIT:
			# A row left out of the clause, not the units it holds: "and 2 more"
			# after three named goods reads as two more rows, the way the
			# ledger's own capped lines count their items (REQ-P5-07).
			hidden += 1
			continue
		named.append("%s ×%d" % [CommodityCatalog.label(id), int(rows[id])])
	if named.is_empty():
		return ""
	var joined: String = _join(named)
	if hidden > 0:
		joined += " and %d more" % hidden
	return "%s %s" % [verb, joined]


## The plan's rows as commodity → units, dropping anything a formatter cannot
## name (an empty id, a row that holds nothing).
static func _rows(source: Variant) -> Dictionary:
	var rows: Dictionary = {}
	if not (source is Array):
		return rows
	for raw: Variant in source as Array:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var id: String = String(row.get("commodity", ""))
		var quantity: int = int(row.get("quantity", 0))
		if id.is_empty() or quantity <= 0:
			continue
		rows[id] = int(rows.get(id, 0)) + quantity
	return rows


## A list read the way prose reads it: "A", "A and B", "A, B and C".
static func _join(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() <= 2:
		return " and ".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]
