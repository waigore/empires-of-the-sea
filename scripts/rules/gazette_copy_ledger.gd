class_name GazetteCopyLedger
extends RefCounted
## The crown's book: a finished study, the year's rents, and prizes taken or
## lost to raiders. Every sum and cargo arrives in the record, already counted by
## the rules; the desk only sets it in the sheet's voice (wiki: the-gazette
## § Item catalog; REQ-P2-03).


static func tech_finished(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var label: String = String(rec.get("label", ""))
	if bool(rec.get("self_act", false)):
		return "Our scholars have finished the %s; its secrets are ours to use." % label
	return "%s has completed the %s." % [who, label]


static func riches_rendered(rec: Dictionary) -> String:
	return (
		"The estates render %s into the crown's coffers this year, and the ledger "
		+ "closes the richer."
	) % GazetteCopyVoice.money(rec)


static func raid_suffered(rec: Dictionary) -> String:
	var place: String = String(rec.get("place", ""))
	var prize: String = String(rec.get("prize", "no cargo"))
	var sunk: String = String(rec.get("sunk", ""))
	if sunk.is_empty():
		return (
			"Raiders have taken %s off %s; no hull was lost, but the cargo is gone."
			% [prize, place]
		)
	return "Raiders have taken %s off %s and sent the %s to the bottom." % [
		prize, place, sunk
	]


static func raid_prize(rec: Dictionary) -> String:
	var place: String = String(rec.get("place", ""))
	var prize: String = String(rec.get("prize", "no cargo"))
	var sunk: String = String(rec.get("sunk", ""))
	if sunk.is_empty():
		return "Our station takes %s off %s as lawful prize." % [prize, place]
	return "Our station takes %s off %s as lawful prize and sends the %s down." % [
		prize, place, sunk
	]
