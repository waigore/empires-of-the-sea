class_name TechPlan
extends RefCounted
## The road to an advance: what a crown still lacks for any catalog tech, and
## the order the college must study it in (wiki: tech-tree § Prerequisites,
## § Research Model — goal slot). Pure queries over `TechCatalog` and
## `ResearchState`, so the tree tab, its tests and any later planner read one
## answer instead of re-deriving the DAG (REQ-P2-03, REQ-P3-03).
##
## Nothing here spends, assigns or unlocks: a road is a reading, never an order.

## Where one catalog advance stands for one crown.
enum State { KNOWN, STUDYING, OPEN, LOCKED }


## Known, at study, open now, or still gated. An unknown id is never open.
static func state_of(state: ResearchState, tech_id: String) -> int:
	if state == null or not TechCatalog.known(tech_id):
		return State.LOCKED
	if state.is_unlocked(tech_id):
		return State.KNOWN
	if state.is_active(tech_id):
		return State.STUDYING
	if state.prerequisites_met(tech_id) and state.discovered(tech_id):
		return State.OPEN
	return State.LOCKED


## The techs standing between the crown and `tech_id`, prerequisites first —
## every ancestor still unknown, whether or not it is already in a slot. Empty
## when the crown already knows it (or the id is not in the catalog).
static func road(state: ResearchState, tech_id: String) -> Array[String]:
	var out: Array[String] = []
	if state == null or not TechCatalog.known(tech_id):
		return out
	if state.is_unlocked(tech_id):
		return out
	_walk(state, tech_id, {}, out)
	return out


## The next study on the road that the college can start this turn: the first
## road tech with its own prerequisites met and its discovery found. "" when the
## road holds nothing startable — the advance is in hand, or an explorer still
## has to find the resource.
static func next_step(state: ResearchState, tech_id: String) -> String:
	for step: String in road(state, tech_id):
		if state_of(state, step) == State.OPEN:
			return step
	return ""


## Direct prerequisites still unknown (not the whole ancestry): what a row names
## when it says an advance needs something.
static func blocked_by(state: ResearchState, tech_id: String) -> Array[String]:
	var out: Array[String] = []
	if state == null or not TechCatalog.known(tech_id):
		return out
	for prereq: String in TechCatalog.prerequisites(tech_id):
		if not state.is_unlocked(prereq):
			out.append(prereq)
	return out


## One sentence a player reads on the row without a hover (REQ-P1-05): why this
## advance is where it is. A tech whose prerequisites stand but whose discovery
## does not names the explorer's errand instead.
static func reason(state: ResearchState, tech_id: String) -> String:
	match state_of(state, tech_id):
		State.KNOWN:
			return "Known."
		State.STUDYING:
			return "In the study."
		State.OPEN:
			return "Open now."
	var missing: Array[String] = blocked_by(state, tech_id)
	if not missing.is_empty():
		return "Needs %s." % _names(missing)
	var findings: Array[String] = []
	for commodity: String in TechCatalog.discovery_resources(tech_id):
		findings.append(CommodityCatalog.label(commodity))
	if not findings.is_empty():
		return "An explorer must find %s." % " or ".join(findings)
	return "Locked."


## How many catalog advances stand in each state — the tab's summary line, read
## from the same predicates the rows use.
static func counts(state: ResearchState) -> Dictionary:
	var out: Dictionary = {
		State.KNOWN: 0, State.STUDYING: 0, State.OPEN: 0, State.LOCKED: 0,
	}
	for tech_id: String in TechCatalog.ids():
		var kind: int = state_of(state, tech_id)
		out[kind] = int(out[kind]) + 1
	return out


## The goal in a sentence: what the crown reads under the tree when a goal is
## set. Names the study to start now, or says the road is already walked.
static func road_line(state: ResearchState, tech_id: String) -> String:
	if not TechCatalog.known(tech_id):
		return ""
	var name: String = TechCatalog.display_name(tech_id)
	if state_of(state, tech_id) == State.KNOWN:
		return "%s is known — the goal is walked." % name
	var step: String = next_step(state, tech_id)
	if not step.is_empty():
		return "Toward %s: study %s next." % [name, TechCatalog.display_name(step)]
	var missing: Array[String] = blocked_by(state, tech_id)
	if not missing.is_empty():
		return "Toward %s: nothing on the road can start yet." % name
	return "Toward %s: an explorer must find the resource first." % name


# --- helpers -----------------------------------------------------------------


## Post-order walk over the unmet prerequisite edges: a tech lands after every
## one of its unknown prerequisites, so the array reads as a study order.
static func _walk(
	state: ResearchState, tech_id: String, seen: Dictionary, out: Array[String]
) -> void:
	if seen.has(tech_id):
		return
	seen[tech_id] = true
	for prereq: String in TechCatalog.prerequisites(tech_id):
		if state.is_unlocked(prereq):
			continue
		_walk(state, prereq, seen, out)
	out.append(tech_id)


## "Saw Mill, Land Enclosure and Horse Artillery" — the catalog's deepest fan is
## three prerequisites, so the line always names them all.
static func _names(tech_ids: Array[String]) -> String:
	var shown: PackedStringArray = []
	for tech_id: String in tech_ids:
		shown.append(TechCatalog.display_name(tech_id))
	return ", ".join(shown)
