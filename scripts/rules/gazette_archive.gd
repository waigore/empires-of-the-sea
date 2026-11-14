class_name GazetteArchive
extends RefCounted
## The history screen's reading filter (wiki: the-gazette § History screen;
## DR-20261115-06). A campaign files one sheet a turn and keeps every one of
## them, so a long age's archive is a hundred pages of three classes mixed
## together. The filter selects which of those pages the screen walks and which
## of a page's lines it prints; it never re-orders, re-words or invents a line,
## so the archive still prints the classes in their order and the prose the turn
## wrote (REQ-P2-03, REQ-P3-03).
##
## Pure data: the plate reads it, the save never sees it, and a filter is a
## reading of the filed sheets rather than a second archive.

## No filter: every filed sheet, the quiet ones included, because an empty turn
## is still archived so the history has no gaps (wiki: the-gazette § When it
## appears).
const ALL: int = -1

## The order the plate's chips walk: every class, then each class alone.
const ORDER: Array[int] = [ALL, Gazette.Class.WORLD, Gazette.Class.COURT, Gazette.Class.INTEREST]

## The line a filter that matches nothing prints.
const NONE_LINE: String = "No sheet in the archive holds that news."


## The chip's word for a filter. The three classes keep the headings the sheet
## itself prints, so a chip and the page it selects read the same.
static func label(cls: int) -> String:
	match cls:
		Gazette.Class.WORLD:
			return "The world"
		Gazette.Class.COURT:
			return "Our court"
		Gazette.Class.INTEREST:
			return "Courts of interest"
	return "All news"


## What the chip buys, in the sheet's own terms (touch parity: the hint is a
## tooltip on desktop and the chip's own word on a phone, REQ-P5-07).
static func hint(cls: int) -> String:
	match cls:
		Gazette.Class.WORLD:
			return "Only the world's epoch-scale news: wars and peaces between other courts, a people absorbed or colonized, a crown struck from the age."
		Gazette.Class.COURT:
			return "Only your own crown's news: its wars, treaties, battles, provinces, studies and deliveries."
		Gazette.Class.INTEREST:
			return "Only the doings of the courts you follow, at the tier of knowledge your chart holds."
	return "Every class, in the sheet's own order, quiet turns included."


## The sheet as the filter prints it: the same turn, the same order, only the
## lines of the chosen class. `ALL` hands the sheet back untouched, so the
## unfiltered archive is exactly what the turn filed.
static func sheet(sheet: Dictionary, cls: int) -> Dictionary:
	if cls == ALL:
		return sheet
	var items: Array[Dictionary] = []
	for raw: Variant in sheet.get("items", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw
		if int(item.get("class", Gazette.Class.COURT)) == cls:
			items.append(item)
	return {"turn": int(sheet.get("turn", 0)), "items": items}


## True when the sheet holds a line the filter prints. `ALL` holds every sheet,
## including the turn that printed nothing.
static func holds(sheet: Dictionary, cls: int) -> bool:
	if cls == ALL:
		return true
	for raw: Variant in sheet.get("items", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if int((raw as Dictionary).get("class", Gazette.Class.COURT)) == cls:
			return true
	return false


## The pages the history screen walks, in the order it was handed them (newest
## first): every filed sheet under `ALL`, else only those holding a line of the
## class. A quiet turn is skipped by a class filter because it holds no line of
## that class — the archive still keeps it for the unfiltered reading.
static func walk(sheets: Array[Dictionary], cls: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sheet: Dictionary in sheets:
		if holds(sheet, cls):
			out.append(sheet)
	return out


## How many lines of the class the whole archive holds, for the chip's tally.
static func tally(sheets: Array[Dictionary], cls: int) -> int:
	var count: int = 0
	for entry: Dictionary in sheets:
		if cls == ALL:
			count += (entry.get("items", []) as Array).size()
			continue
		count += (sheet(entry, cls).get("items", []) as Array).size()
	return count
