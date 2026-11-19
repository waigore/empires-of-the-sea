class_name ObserverTurnFeed
extends RefCounted
## The AI observatory's order feed: the newest whole turns of `play.ai_turns`,
## every row printed, newest first, plus the caption that counts what the feed
## holds (REQ-P3-01). Presentation only — the panel hands over the session and
## writes whatever text comes back onto its label (REQ-P5-05).

## Rows the feed reaches back through before it stops. A merged turn is one
## record for every crown — T1 of a standard campaign resolves 41 rows — so the
## window is a row budget, not a turn count: a quiet late turn buys more history
## than a crowded opening one, and the plate's own cost stays bounded whatever
## the campaign's length (REQ-P4-01, REQ-P5-05).
const ROW_BUDGET: int = 120
## Turns the feed always keeps, however busy they are. The newest turn alone
## would hide the order that caused it, so the window never shrinks below a pair.
const MIN_TURNS: int = 2
const EMPTY_TEXT: String = "No orders recorded yet."


## The first turn the feed still shows; turns after it are whole.
static func first_kept(ai_turns: Array) -> int:
	var kept: int = 0
	var rows: int = 0
	var index: int = ai_turns.size() - 1
	while index >= 0:
		var turn_rows: int = (ai_turns[index].get("events", []) as Array).size()
		if kept >= MIN_TURNS and rows + turn_rows > ROW_BUDGET:
			break
		rows += turn_rows
		kept += 1
		index -= 1
	return ai_turns.size() - kept


## The turns the feed keeps, newest row first, every row printed: the plate
## scrolls rather than choosing which orders a watcher may read (REQ-P5-05).
static func text(ai_turns: Array) -> String:
	if ai_turns.is_empty():
		return EMPTY_TEXT
	var lines: PackedStringArray = PackedStringArray()
	var first: int = first_kept(ai_turns)
	for index in range(ai_turns.size() - 1, first - 1, -1):
		var merged: Dictionary = ai_turns[index]
		var events: Array = merged.get("events", [])
		for cursor in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[cursor]
			lines.append("T%d  %s" % [int(merged["turn"]), String(event["text"])])
	return "\n".join(lines) if not lines.is_empty() else EMPTY_TEXT


## What the feed holds, so the rows off-screen are counted and the turns the
## window reaches back to are named — a watcher reading T12–T17 of 200 knows how
## much calendar sits behind the plate (REQ-P5-05).
static func caption(ai_turns: Array) -> String:
	var first: int = first_kept(ai_turns)
	var rows: int = 0
	var turns: int = 0
	for index in range(first, ai_turns.size()):
		rows += (ai_turns[index].get("events", []) as Array).size()
		turns += 1
	if turns == 0:
		return "Recent orders"
	return "Recent orders  ·  %s  ·  %d row%s over %d turn%s, newest first" % [
		_span(ai_turns, first), rows, MoneyText.plural(rows),
		turns, MoneyText.plural(turns),
	]


## The window's turns as one span: `T12` for a single turn, `T12–T17` for more.
static func _span(ai_turns: Array, first: int) -> String:
	var oldest: int = int(ai_turns[first]["turn"])
	var newest: int = int(ai_turns[ai_turns.size() - 1]["turn"])
	if oldest == newest:
		return "T%d" % oldest
	return "T%d–T%d" % [oldest, newest]
