class_name GroundsWindow
extends RefCounted
## The passengers block's ground list window (DR-20261119-03): how many of a
## coast's legal grounds stand whole in the list before it scrolls, and how tall
## that window is. A coast is a **tile** (wiki: civilian-units § Landing), so a
## port province offers its whole land — 32 rows at Madrid — and the list grew
## the fleet dossier's own scroll by every one of them, putting the split,
## combine and yard drawers at the foot of a long swipe on a handset.
##
## Pure reads over integers: the block applies them, so no rule, no order and no
## state lives here (REQ-P3-03).

## A row's tap height, as the block builds every press it appends.
const ROW_HEIGHT: float = 36.0
## The gap the block's row boxes keep between rows.
const ROW_GAP: int = 4
## The atlas and a tablet have the room for a longer list.
const WIDE_ROWS: int = 8
## A handset reads four rows under the way back and scrolls the rest.
const COMPACT_ROWS: int = 4


## How many of the coast's grounds stand whole in the window: every one of them
## when the list is short, the sheet's own budget when it is long.
static func rows(count: int, compact: bool) -> int:
	return clampi(count, 0, COMPACT_ROWS if compact else WIDE_ROWS)


## The window's height in whole rows — never a half row, so a row is never cut
## by the window's edge — and `0` for a coast with nothing to list.
static func height(count: int, compact: bool) -> float:
	var shown: int = rows(count, compact)
	if shown <= 0:
		return 0.0
	return ROW_HEIGHT * float(shown) + float(ROW_GAP) * float(shown - 1)
