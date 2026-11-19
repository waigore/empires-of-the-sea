class_name ResearchSheetFit
extends RefCounted
## The college sheet's height rule (DR-20261119-02, DR-20261120-03): how much of
## the room the queue's window takes and how much the two lists keep. It reads the
## heights the sheet has already laid out and returns the two minimums the panel
## applies — no rule, no order, no state (REQ-P3-03).
##
## The room it is handed is the **sheet's own box** (the plate the college stands
## in), never the dock the dossiers ride: every bar door opens a full-screen sheet
## (issue #692), so a budget read from the dock's margins is a budget 66 points
## short of the plate on a desktop and 12 short on a phone (DR-20261120-03).

## The room a college sheet has at `panel`: the box its plate lays it in. Every
## cartouche door opens a full-screen plate (issue #692, DR-20261119-10), so the
## college measures the sheet it stands in — the dock's margins (84/104 wide,
## 64/10 thin) are the dossiers' and are 66 points short of a desktop plate and 12
## short of a phone's (DR-20261120-03). A panel mounted without a plate above it (a
## suite's fixture, a shot harness) keeps the viewport arithmetic it always had.
static func room(panel: Control, compact: bool) -> float:
	if stands_on_sheet(panel):
		var plate: float = panel.get_parent_area_size().y
		if plate > 1.0:
			return plate
	var view: Vector2 = panel.get_viewport_rect().size
	var top: float = 64.0 if compact else PanelDock.TOP
	var bottom: float = 10.0 if compact else absf(PanelDock.BOTTOM)
	return maxf(view.y - top - bottom, 0.0)


## Whether a sheet of its own (a `ModalShell`) stands above the panel.
static func stands_on_sheet(panel: Control) -> bool:
	var node: Node = panel.get_parent()
	while node != null:
		if node is ModalShell:
			return true
		node = node.get_parent()
	return false


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
## their gaps and the padding — is measured first; the window and the pages
## divide what is left. The queue takes **whole rows** only, and takes the
## tallest run of them that still leaves the pages their floor; what the queue
## does not take goes to the pages, up to their cap. When the room cannot stand
## the pages' bar beside even one whole row, the window gives way — it scrolls,
## the tab strip does not — so the plate is never taller than its own box.
static func split(
	column: VBoxContainer, slots: Control, tabs: Control, body: Control,
	room: float, pad: float
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
	var budget: float = maxf(room - fixed, 0.0)
	var natural: float = body.get_combined_minimum_size().y
	if natural <= 0.0 and body.get_child_count() > 0:
		# A body read before the frame has laid its rows out reports nothing; the
		# rows still know the height they will stand. Without this the window
		# collapses to zero on the very fit a profile change asks for
		# (DR-20261120-03).
		natural = 0.0
		for row: Node in body.get_children():
			natural += _row_height(row as Control)
		natural += sep * float(maxi(body.get_child_count() - 1, 0))
	var window: float = natural
	if natural + LISTS_FLOOR > budget:
		# The queue's own height would eat the pages' floor: the pages keep the
		# room and the queue keeps one whole row — the least it is read in — and
		# scrolls to the rows below it (DR-20261119-02).
		var tallest: float = 0.0
		for row: Node in body.get_children():
			tallest = maxf(tallest, _row_height(row as Control))
		window = minf(tallest, natural)
	var pages: float = budget - window
	# The sheet is the room it is given: a budget that cannot carry the tab strip
	# beside the queue's window is answered by the window, because a page under a
	# scrolling queue still reads and a clipped tab strip does not.
	if pages < TABS_FLOOR:
		window = maxf(budget - TABS_FLOOR, 0.0)
		pages = budget - window
	return {
		"slots": clampf(window, 0.0, natural),
		"tabs": clampf(pages, 0.0, TABS_CAP),
	}


## The height a row will stand: what the frame has measured, or the minimum the
## row carries before it is laid out.
static func _row_height(row: Control) -> float:
	if row == null:
		return 0.0
	return maxf(row.get_combined_minimum_size().y, row.custom_minimum_size.y)
