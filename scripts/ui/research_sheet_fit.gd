class_name ResearchSheetFit
extends RefCounted
## The college sheet's height rule (DR-20261119-02): how much of the room the
## queue's window takes and how much the two lists keep. It reads the heights the
## sheet has already laid out and returns the two minimums the panel applies — no
## rule, no order, no state (REQ-P3-03).

## The lists keep at least this much of a handset's sheet — a tab bar and two
## rows — when the slots have to give way.
const LISTS_FLOOR: float = 60.0
## The tab bar's own height with empty pages: the least the lists can be read in.
const TABS_FLOOR: float = 28.0
## The pages never ask for more than this, however tall the sheet is.
const TABS_CAP: float = 300.0


## `column` is the sheet's own column, `slots` the queue's window, `tabs` the two
## lists and `body` the queue's rows; `pad` is the panel's vertical padding.
## Returns `slots` (the window's height) and `tabs` (the lists').
##
## Every row that never yields — the masthead, the slots heading, the one press,
## their gaps and the padding — is measured first; the two regions divide what is
## left. A wide chart hands the queue its own height and the lists the rest. A
## handset short of room gives the queue a window of whole rows that keeps
## `LISTS_FLOOR` under it, never less than one row, and the window scrolls.
static func split(
	column: VBoxContainer, slots: Control, tabs: Control, body: Control,
	room: float, compact: bool, pad: float
) -> Dictionary:
	var sep: float = float(column.get_theme_constant("separation"))
	var fixed: float = pad
	var seen: int = 0
	for child: Node in column.get_children():
		var row: Control = child as Control
		if row == null or not row.visible:
			continue
		seen += 1
		if row != slots and row != tabs:
			fixed += row.get_combined_minimum_size().y
	fixed += sep * float(maxi(seen - 1, 0))
	var natural: float = body.get_combined_minimum_size().y
	var window: float = natural
	if compact and natural + TABS_FLOOR > maxf(room - fixed, 0.0):
		var tallest: float = 0.0
		for row: Node in body.get_children():
			tallest = maxf(tallest, (row as Control).get_combined_minimum_size().y)
		var budget: float = maxf(room - fixed - LISTS_FLOOR, 0.0)
		var count: int = maxi(int((budget + sep) / maxf(tallest + sep, 1.0)), 1)
		window = minf(tallest * float(count) + sep * float(count - 1), natural)
	return {
		"slots": window,
		"tabs": clampf(maxf(room - fixed - window, TABS_FLOOR), 0.0, TABS_CAP),
	}
