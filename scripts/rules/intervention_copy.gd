class_name InterventionCopy
extends RefCounted
## Names the wardens of a Minor Nation or Tribe before a declaration, so the
## court panel can print them beside Declare War (REQ-P5-03,
## DR-20261110-20). The offer's own sentence lives with the rules that queue it
## (`Intervention.offer_text`).


## "England and France may intervene", or "" when the victim stands alone.
static func warden_hint(
	state: DiplomacyState, world: WorldMap, aggressor: int, target: int
) -> String:
	var names: Array[String] = []
	for court: int in Intervention.candidates(state, aggressor, target, world):
		names.append(FactionCatalog.name_of(court))
	if names.is_empty():
		return ""
	return "%s may intervene." % _join_names(names)


## "A", "A and B", "A, B and C" — one Oxford-free list for the court copy.
static func _join_names(names: Array[String]) -> String:
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	var head: String = ""
	for index in names.size() - 1:
		head += ("" if index == 0 else ", ") + names[index]
	return "%s and %s" % [head, names[names.size() - 1]]
