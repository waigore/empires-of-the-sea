class_name AiControl
extends RefCounted
## Planner gate for the full-AI observer and headless AI-vs-AI harness
## (docs/ai-observer.md). Controls whether a Great Power issues planner orders.
##
## - FULL: every Great Power runs the shared planners (default).
## - NOOP: every Great Power is inert — no diplomacy, land, sea, economy, or
##   civilian orders (control baseline).
## - BENCH: only `play.ai_live_faction_id()` plans; other crowns are no-op
##   controls for quantitative win-seeking checks.

const FULL: String = "full"
const NOOP: String = "noop"
const BENCH: String = "bench"


## Live crown under BENCH (`NO_ID` → setup `player_faction`).
static func live_faction(play: PlaySession) -> int:
	if play == null:
		return MapModel.NO_ID
	if play.ai_live_faction == MapModel.NO_ID:
		return play.player_faction
	return play.ai_live_faction


## True when this Great Power may issue planner orders this session.
static func plans(play: PlaySession, faction: int) -> bool:
	if play == null:
		return true
	match play.ai_mode:
		NOOP:
			return false
		BENCH:
			return faction == live_faction(play)
		_:
			return true


## Parse a CLI / UI token into a mode string; unknown values become FULL.
static func parse(raw: String) -> String:
	var token: String = raw.strip_edges().to_lower()
	if token == NOOP or token == BENCH or token == FULL:
		return token
	return FULL
