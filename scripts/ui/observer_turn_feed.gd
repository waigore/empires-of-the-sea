class_name ObserverTurnFeed
extends RefCounted
## The AI observatory's order feed: the newest whole turns of `play.ai_turns`,
## every row printed, newest first, plus the caption that counts what the feed
## holds (REQ-P3-01). Presentation only — the panel hands over the session and
## writes whatever text comes back onto its label (REQ-P5-05).

## Turns the feed keeps. A merged turn is one record for every crown — T1 of a
## standard campaign resolves 41 rows — so the feed scrolls through whole turns
## instead of cutting a busy turn's first rows (REQ-P5-05).
const FEED_TURNS: int = 2
const EMPTY_TEXT: String = "No orders recorded yet."


## The first turn the feed still shows; turns after it are whole.
static func first_kept(total_turns: int) -> int:
	return maxi(total_turns - FEED_TURNS, 0)


## The turns the feed keeps, newest row first, every row printed: the plate
## scrolls rather than choosing which orders a watcher may read (REQ-P5-05).
static func text(ai_turns: Array) -> String:
	if ai_turns.is_empty():
		return EMPTY_TEXT
	var lines: PackedStringArray = PackedStringArray()
	var first: int = first_kept(ai_turns.size())
	for index in range(ai_turns.size() - 1, first - 1, -1):
		var merged: Dictionary = ai_turns[index]
		var events: Array = merged.get("events", [])
		for cursor in range(events.size() - 1, -1, -1):
			var event: Dictionary = events[cursor]
			lines.append("T%d  %s" % [int(merged["turn"]), String(event["text"])])
	return "\n".join(lines) if not lines.is_empty() else EMPTY_TEXT


## What the feed holds, so the rows off-screen are counted (REQ-P5-05).
static func caption(ai_turns: Array) -> String:
	var rows: int = 0
	var turns: int = 0
	for index in range(first_kept(ai_turns.size()), ai_turns.size()):
		rows += (ai_turns[index].get("events", []) as Array).size()
		turns += 1
	if turns == 0:
		return "Recent orders"
	return "Recent orders  ·  %d rows over %d turn%s, newest first" % [
		rows, turns, "" if turns == 1 else "s",
	]
