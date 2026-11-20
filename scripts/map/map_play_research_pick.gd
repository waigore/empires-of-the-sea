class_name MapPlayResearchPick
extends RefCounted
## What the court's own college would study next: the advance the published
## research policy opens in the crown's first free slot (wiki: tech-tree
## § Research model, ai-architecture § Research planner; DR-20261121-01).
##
## The plan is not a second opinion: it is `AiResearchScores`'s ranking — the
## candidates `AiResearchPlanner` walks for a court's empty slot — taken in that
## walk's own order on this crown's college, its own stores and its own door (the
## yard's next hull, the envoy chain's next stage, the study a charted deed waits
## on). The door chain itself is `MapPlayEconomyCourtBook.door`'s, so the reading
## and the rival pass cannot walk two different chains (REQ-P2-03).
##
## A reading only: nothing here assigns a slot, moves a funding preset or spends
## a ducat, and the crown still presses her own study (REQ-P3-03, REQ-P5-06).

## The door the ranking answered: the yard's next hull (`AiNavy`), the envoy
## chain's next stage (`AiTribeColony`), or the study a charted deed waits on
## (`AiMerchantWork`).
const WHY_HULL: String = MapPlayEconomyCourtBook.DOOR_HULL
const WHY_CHAIN: String = MapPlayEconomyCourtBook.DOOR_CHAIN
const WHY_DEED: String = MapPlayEconomyCourtBook.DOOR_DEED


## The study one college would open next, as the sheet reads it: `{tech, why,
## line}`. Empty when the court has no free slot (there is nothing to open), the
## campaign is decided, the session runs no planner, or every study the court
## could take is already under way.
static func pick(play: PlaySession) -> Dictionary:
	if play == null or play.economy == null or play.economy.economy == null:
		return {}
	if play.diplomacy == null or play.campaign_over():
		return {}
	var economy: PlayerEconomy = play.economy.economy
	if economy.research == null or economy.research.free_slot() < 0:
		return {}
	var faction: int = play.player_faction
	var kind: String = AiControl.court_kind(play, faction)
	if kind == AiControl.KIND_NONE:
		return {}
	var config: Variant = AiBind.config(kind, faction, play.map_seed, play.ensure_ai().profiles)
	if not (config is AiConfig):
		return {}
	var at_war: bool = MapPlayCourt.at_war(play, faction)
	var door: Dictionary = MapPlayEconomyCourtBook.door(
		play, faction, economy,
		AiBind.phase_for(kind, config, play.diplomacy),
		at_war, MapPlayCourt.warships(play, faction)
	)
	return counsel(config, economy, at_war, door)


## The ranking's own answer, given a court's college and the door it stands in:
## the first study the planner's own walk would take for an empty slot — the
## door's when the door is open, else the best-ranked study the court is not
## already reading (`AiResearchPlanner._pick_for_slot`'s order, without the
## assignment). Pure: the ranking reads the state and writes nothing.
static func counsel(
	config: AiConfig, economy: PlayerEconomy, at_war: bool, door: Dictionary = {}
) -> Dictionary:
	if config == null or economy == null or economy.research == null:
		return {}
	var door_tech: String = String(door.get("tech", ""))
	var tech: String = ""
	for entry: Dictionary in AiResearchScores.candidates(config, economy, at_war, door_tech):
		var candidate: String = String(entry.get("tech", ""))
		if candidate.is_empty() or economy.research.is_active(candidate):
			continue
		tech = candidate
		break
	if tech.is_empty():
		return {}
	# The door's reason only stands while the door's own study is the answer: a
	# scoring win somewhere else carries no reason the policy gave it.
	var why: String = String(door.get("why", "")) if tech == door_tech else ""
	var line: String = MapPlayResearchPickWords.line(TechCatalog.display_name(tech), why)
	if line.is_empty():
		return {}
	return {"tech": tech, "why": why, "line": line}


## The sheet's line: the pick's own sentence, or nothing when the court has no
## free slot or no study left to open.
static func line(play: PlaySession) -> String:
	return MapPlayResearchPickWords.sentence(String(pick(play).get("line", "")))