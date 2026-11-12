class_name GazetteCopyCourt
extends RefCounted
## The crown's reach over other peoples: a court joining the empire, colonies
## planted and released, and first contact. Epoch facts, not transactions; the
## desk speaks them in the sheet's own voice (wiki: the-gazette § Item catalog).


static func join_empire(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"The court of %s has joined our empire; its provinces are ours to govern "
			+ "and its people ours to protect."
		) % whom
	return (
		"The minor court of %s is swallowed by %s; its towns now answer to that "
		+ "crown."
	) % [whom, who]


static func colony_formed(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our crown has taken the people of %s under its protection as a colony."
			% whom
		)
	return (
		"%s has planted its colours over the tribe of %s; another people answers to "
		+ "its court."
	) % [who, whom]


static func colony_released(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return "The colony of %s is released from our protection and stands alone." % whom
	return "%s has released %s from its colonial protection." % [who, whom]


static func first_contact(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our court has made first contact with %s; a new people enters our "
			+ "reckoning."
		) % whom
	return "%s has made first contact with %s." % [who, whom]
