class_name AiControl
extends RefCounted
## Planner gate for the full-AI observer and headless AI-vs-AI harness
## (docs/ai-observer.md). Controls whether a Great Power issues planner orders
## and, under BENCH, which court backend it uses.
##
## - FULL: every Great Power runs the shared planners (default).
## - NOOP: every Great Power is inert — no diplomacy, land, sea, economy, or
##   civilian orders (control baseline).
## - BENCH: subject (live crown) uses the submission AI surface; the two
##   smallest other GP ids use origin/main planners (`scripts/ai_mainline/`);
##   remaining GPs take random legal economy/civilian actions. Official
##   ai-bench scores only the subject.

const FULL: String = "full"
const NOOP: String = "noop"
const BENCH: String = "bench"

const KIND_SUBJECT: String = "subject"
const KIND_BASELINE: String = "baseline"
const KIND_RANDOM: String = "random"
const KIND_NONE: String = "none"


## Live crown under BENCH (`NO_ID` → setup `player_faction`).
static func live_faction(play: PlaySession) -> int:
	if play == null:
		return MapModel.NO_ID
	if play.ai_live_faction == MapModel.NO_ID:
		return play.player_faction
	return play.ai_live_faction


## Two baseline rival ids: the smallest Great Power ids other than the subject.
static func baseline_factions(play: PlaySession) -> Array[int]:
	var live: int = live_faction(play)
	var out: Array[int] = []
	for faction: int in FactionCatalog.great_power_ids():
		if faction == live:
			continue
		out.append(faction)
		if out.size() >= 2:
			break
	return out


## Court backend under the current mode. Non-BENCH sessions treat every
## planning crown as the submission subject surface.
static func court_kind(play: PlaySession, faction: int) -> String:
	if play == null or not _is_great_power(faction):
		return KIND_NONE
	match play.ai_mode:
		NOOP:
			return KIND_NONE
		BENCH:
			if faction == live_faction(play):
				return KIND_SUBJECT
			if baseline_factions(play).has(faction):
				return KIND_BASELINE
			return KIND_RANDOM
		_:
			return KIND_SUBJECT


## True when this Great Power may issue planner (or random-court) orders.
static func plans(play: PlaySession, faction: int) -> bool:
	if play == null:
		return true
	match play.ai_mode:
		NOOP:
			return false
		BENCH:
			return _is_great_power(faction)
		_:
			return true


static func _is_great_power(faction: int) -> bool:
	return FactionCatalog.type_of(faction) == FactionCatalog.Type.GREAT_POWER


## Parse a CLI / UI token into a mode string; unknown values become FULL.
static func parse(raw: String) -> String:
	var token: String = raw.strip_edges().to_lower()
	if token == NOOP or token == BENCH or token == FULL:
		return token
	return FULL
