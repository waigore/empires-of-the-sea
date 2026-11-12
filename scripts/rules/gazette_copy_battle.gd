class_name GazetteCopyBattle
extends RefCounted
## The fighting, on land and at sea: captures, held fields, mutual ruin,
## standoffs, and the water won or yielded. The combat phase has already decided
## every outcome and counted every loss; the desk prints only what the crown's
## own page may know (wiki: the-gazette § What the crown can know; REQ-P2-03).


static func battle_capture(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	var count: int = GazetteCopyVoice.count(rec)
	if bool(rec.get("self_act", false)):
		return (
			"Our crown takes %s at the point of the bayonet; %s yields the province and "
			+ "%d regiments."
		) % [place, whom, count]
	if whom == GazetteCopyVoice.CROWN:
		return (
			"%s has carried %s from our crown; %d of our regiments are lost with it."
		) % [who, place, count]
	return "%s has taken %s from %s at the point of the bayonet." % [who, place, whom]


static func battle_held(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	var defended: bool = bool(rec.get("defended", false))
	if bool(rec.get("self_act", false)):
		if defended:
			return (
				"Our crown holds %s against %s; %d of their regiments are broken."
			) % [place, whom, GazetteCopyVoice.count(rec)]
		return "Our crown holds the field at %s; %d of their regiments are broken." % [
			place, GazetteCopyVoice.count(rec)
		]
	if not rec.has("count"):
		if defended:
			return "%s holds %s against %s." % [who, place, whom]
		return "%s holds the field at %s against %s." % [who, place, whom]
	if defended:
		return "%s holds %s against %s; %d regiments are broken." % [
			who, place, whom, GazetteCopyVoice.count(rec)
		]
	# The crown's own losses always print their numbers, even in a field
	# battle it lost (wiki: the-gazette § What the crown can know).
	if whom == GazetteCopyVoice.CROWN:
		return (
			"%s holds the field at %s against our crown; %d of our regiments are lost."
		) % [who, place, GazetteCopyVoice.own(rec)]
	return "%s holds the field at %s against %s." % [who, place, whom]


static func battle_annihilated(rec: Dictionary) -> String:
	var place: String = String(rec.get("place", ""))
	var ruin: String = "At %s the two crowns ruin one another; the field is left empty." % place
	var bonus: String = String(rec.get("bonus", ""))
	if not bonus.is_empty():
		ruin += " A %s garrison re-forms in the ruin." % bonus
	return ruin


## A standoff still buries men: the crown's own dead are counted
## (wiki: the-gazette § What the crown can know).
static func battle_standoff(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	var own: int = GazetteCopyVoice.own(rec)
	var tail: String = "" if own <= 0 else " %d of our regiments lost." % own
	if bool(rec.get("self_act", false)):
		return (
			"Our crown and %s stand off at %s; the guns fall silent with nothing "
			+ "settled."
		) % [whom, place] + tail
	return "%s and %s stand off at %s; the guns fall silent unsettled." % [
		who, whom, place
	] + tail


static func sea_held(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our squadrons hold the %s, and %s loses %d hulls to the bottom."
		) % [place, whom, GazetteCopyVoice.count(rec)]
	if not rec.has("count"):
		return "%s holds the %s against %s." % [who, place, whom]
	return "%s holds the %s; %d hulls of %s are sunk or taken." % [
		who, place, GazetteCopyVoice.count(rec), whom
	]


## The crown holds the water but still spends hulls to do it: its own loss is
## counted (wiki: the-gazette § What the crown can know).
static func sea_withdrew(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		return "Our squadron quits the %s; %s holds the water." % [place, whom]
	if whom == GazetteCopyVoice.CROWN and GazetteCopyVoice.own(rec) > 0:
		return (
			"%s withdraws from the %s, and our crown holds the zone; %d of our hulls lost."
		) % [who, place, GazetteCopyVoice.own(rec)]
	return "%s withdraws from the %s, and %s holds the zone." % [who, place, whom]


static func sea_draw(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our squadrons and %s trade broadsides in the %s and part with nothing "
			+ "decided."
		) % [whom, place]
	return "%s and %s trade broadsides in the %s and withdraw." % [who, whom, place]
