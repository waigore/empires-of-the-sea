class_name GazetteCopyWar
extends RefCounted
## The sword abroad: declarations, peace, leagues, calls to arms, and a Great
## Power struck from the roll of powers. Every party and figure arrives in the
## record; the desk only gives them the sheet's voice (wiki: the-gazette
## § Item catalog; REQ-P2-03).


static func war_declared(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our crown has cast the glove at %s: war is proclaimed and letters of "
			+ "marque go out to every captain."
		) % whom
	if whom == GazetteCopyVoice.CROWN:
		return (
			"%s has thrown down the glove before our court: the crown is at war, "
			+ "and the sea will be the judge of it."
		) % who
	return (
		"The gauntlet passes between %s and %s; war is proclaimed, and no merchant "
		+ "sail is safe between them."
	) % [who, whom]


static func peace_made(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Peace is concluded with %s. The drums fall silent and the crown's "
			+ "captains are recalled to their stations."
		) % whom
	return "%s and %s have laid down the sword and concluded a peace." % [who, whom]


static func alliance_formed(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"A formal alliance is sealed with %s; our fortunes are joined before all "
			+ "the world."
		) % whom
	return "%s and %s have clasped hands in a formal league." % [who, whom]


static func alliance_broken(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our alliance with %s is broken. The court will remember who quitted whom."
			% whom
		)
	return "%s has broken faith with %s and quitted the alliance." % [who, whom]


static func call_to_arms_accepted(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var aggressor: String = String(rec.get("aggressor", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our crown answers the call of %s and joins the war against %s; the "
			+ "alliance is honoured."
		) % [whom, aggressor]
	return (
		"%s answers our call to arms and joins the war against %s; the league holds."
	) % [who, aggressor]


static func call_to_arms_refused(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var aggressor: String = String(rec.get("aggressor", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our crown refuses the call of %s against %s. The alliance is broken by it, "
			+ "and the court knows the price."
		) % [whom, aggressor]
	return (
		"%s refuses our call to arms against %s; that alliance is at an end."
	) % [who, aggressor]


static func great_power_fell(rec: Dictionary) -> String:
	return (
		"%s is fallen. Its seat is taken, its provinces pass to %s, and its name is "
		+ "struck from the roll of powers."
	) % [String(rec.get("who", "")), String(rec.get("whom", ""))]
