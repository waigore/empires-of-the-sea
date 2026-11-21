class_name MapPlayResearchPickWords
extends RefCounted
## How the college's pick is worded (wiki: tech-tree § Research model;
## DR-20261121-01): the advance the published policy would open, named in the
## catalogue's own display name, with the reason the door gives when the door is
## why. A reading, never an order (REQ-P2-03, REQ-P5-06).

## The study the court would open. Empty when the study has no name, so the sheet
## can never print an id or a blank advance.
static func line(name: String, why: String) -> String:
	if name.strip_edges().is_empty():
		return ""
	match why:
		MapPlayResearchPick.WHY_HULL:
			return "the court would open %s — the yard's next hull needs it" % name
		MapPlayResearchPick.WHY_CHAIN:
			return "the court would open %s — the envoy chain's next stage" % name
		MapPlayResearchPick.WHY_DEED:
			return "the court would open %s — the deed waits on it" % name
	return "the court would open %s" % name