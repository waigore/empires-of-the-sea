class_name AiResearchPlan
extends RefCounted
## What a rival court's free slot opens this turn (wiki: ai-architecture
## § Research planner, tech-tree § Research model).
##
## [AiResearchPlanner] owns the turn — it prices the purse and books the slots;
## this home walks that purse and answers one question: which study does a free
## slot take, and at what preset. The walk's order, its skip of a study already
## taken, and the door's own funding gate live here so the plan and the crown's
## college read one answer and cannot name a study the policy refuses
## (issue #484, #490; DR-20261121-01; REQ-P2-03, REQ-P3-01, REQ-P3-03).
##
## The slot's preset is the one the book was priced at ([method
## AiResearchPlanner.book]): the standing slot and the first slot of a
## still-free book pay the standing preset, every other paid slot the ladder's.


## The row the walk takes for one empty slot, its funding included, or `{}` when
## every row is spent or barred. One home for the walk's order, its skip of a
## study already in a slot, and the door's own funding gate (issue #484).
## `taken` is booked here, never assigned, so the caller keeps the walk and the
## rules' own refusals.
static func walk(
	economy: PlayerEconomy,
	purse: Dictionary,
	slot: int,
	candidates: Array[Dictionary],
	taken: Dictionary
) -> Dictionary:
	var state: ResearchState = economy.research
	for entry: Dictionary in candidates:
		var tech: String = String(entry.get("tech", ""))
		if taken.has(tech) or state.is_active(tech):
			taken[tech] = true
			continue
		taken[tech] = true
		var funding: String = funding_of(economy, purse, slot, tech)
		if funding.is_empty():
			continue
		return {
			"tech": tech,
			"slot": slot,
			"funding": funding,
			"score": int(entry.get("score", 0)),
		}
	return {}


## The preset the walk opens one candidate at, or "" when the rules refuse it.
## The door's study is the one row a court may not open unpayable: it pays the
## richest preset above the court's floor, and when even the cheapest would dip
## the court does not open it at all while it saves for its chest (issue #484).
## Every other row opens at the slot's preset, `none` included — an unpaid study
## is still a study the court has taken (wiki: tech-tree § Research model).
static func funding_of(
	economy: PlayerEconomy, purse: Dictionary, slot: int, tech: String
) -> String:
	var standing: int = int(purse["standing"])
	var can_stand: bool = bool(purse["can_stand"])
	var door: String = String(purse["door"])
	if not door.is_empty() and tech == door:
		var funding: String = AiResearchPurse.door_funding(
			economy, int(purse["door_floor"])
		)
		if funding == ResearchFunding.ORDER[0]:
			if not can_stand:
				return ""
			funding = AiResearchPurse.STANDING_FUNDING
		return funding
	if book_slot(slot, standing, can_stand):
		return AiResearchPurse.STANDING_FUNDING
	return String(purse["preset"])


## True when a slot is paid the standing preset: the one the book already holds
## a study on, or, on a book with no study yet, the one its first assignment
## took (`standing` turns that slot into the standing one). [method AiResearchPlanner.book]
## calls this before it assigns, so the study the plan expects is the study the
## rules are asked to open.
static func book_slot(slot: int, standing: int, can_stand: bool) -> bool:
	return slot == standing or (standing < 0 and can_stand)
