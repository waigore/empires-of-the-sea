class_name GazetteCopyBattle
extends RefCounted
## The fighting, on land and at sea: captures, held fields, mutual ruin,
## standoffs, and the water won or yielded. The combat phase has already decided
## every outcome and counted every loss; the desk prints only what the crown's
## own page may know (wiki: the-gazette § What the crown can know; REQ-P2-03).


## The crown's own dead close the sentence they belong to: a won field, a taken
## province and a held sea all name what the crown spent to hold them, beside
## the beaten side's loss ([DR-20261119-07]) — "…; 1 of our regiments is lost."
## A record with no loss left for the crown reads as it was, so a bloodless
## fight prints nothing extra (REQ-P2-03: the record's shape is the rule).
static func _with_own(line: String, rec: Dictionary, noun: String) -> String:
	var dead: int = GazetteCopyVoice.own(rec)
	if dead <= 0:
		return line
	return "%s; %d of our %s %s lost." % [
		line.trim_suffix("."), dead, noun, "is" if dead == 1 else "are"
	]


static func battle_capture(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	var count: int = GazetteCopyVoice.count(rec)
	if bool(rec.get("self_act", false)):
		if count <= 0:
			return _with_own(
				"Our crown has taken %s; %s's flag is struck." % [place, whom], rec, "regiments"
			)
		return _with_own(
			(
				"Our crown takes %s at the point of the bayonet; %s yields the province and "
				+ "%s."
			) % [place, whom, GazetteCopyVoice.regiments(count)],
			rec,
			"regiments"
		)
	if whom == GazetteCopyVoice.CROWN:
		if count <= 0:
			return "%s has carried %s from our crown; the province changes hands." % [who, place]
		return (
			"%s has carried %s from our crown; %d of our regiments %s lost with it."
		) % [who, place, count, GazetteCopyVoice.verb(count)]
	return "%s has taken %s from %s at the point of the bayonet." % [who, place, whom]


static func battle_held(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	var defended: bool = bool(rec.get("defended", false))
	if bool(rec.get("self_act", false)):
		if defended:
			var broken: int = GazetteCopyVoice.count(rec)
			return _with_own(
				(
					"Our crown holds %s against %s; %d of their regiments %s broken."
				) % [place, whom, broken, GazetteCopyVoice.verb(broken)],
				rec,
				"regiments"
			)
		var mauled: int = GazetteCopyVoice.count(rec)
		return _with_own(
			"Our crown holds the field at %s; %d of their regiments %s broken." % [
				place, mauled, GazetteCopyVoice.verb(mauled)
			],
			rec,
			"regiments"
		)
	if not rec.has("count"):
		if defended:
			return "%s holds %s against %s." % [who, place, whom]
		return "%s holds the field at %s against %s." % [who, place, whom]
	if defended:
		var broken: int = GazetteCopyVoice.count(rec)
		# The crown is the beaten side here (another court's `count` is never
		# recorded), so its dead are its own and are named as ours
		# (wiki: the-gazette § What the crown can know; DR-20261119-07).
		return "%s holds %s against our crown; %d of our regiments %s broken." % [
			who, place, broken, GazetteCopyVoice.verb(broken)
		]
	# The crown's own losses always print their numbers, even in a field
	# battle it lost (wiki: the-gazette § What the crown can know).
	if whom == GazetteCopyVoice.CROWN:
		var own: int = GazetteCopyVoice.own(rec)
		return (
			"%s holds the field at %s against our crown; %d of our regiments %s lost."
		) % [who, place, own, GazetteCopyVoice.verb(own)]
	return "%s holds the field at %s against %s." % [who, place, whom]


static func battle_annihilated(rec: Dictionary) -> String:
	var place: String = String(rec.get("place", ""))
	var ruin: String = "At %s the two crowns ruin one another; the field is left empty." % place
	var bonus: String = String(rec.get("bonus", ""))
	if not bonus.is_empty():
		ruin += " A %s garrison re-forms in the ruin." % bonus
	return ruin


## A province taken without a fight: no shot was fired and no regiment fell, so
## the line prints the flag coming down and never a battle's casualty count
## (wiki: the-gazette § Item catalog — "Provinces the crown took or lost";
## § Prose — a line never invents an outcome).
static func province_occupied(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Not a shot was fired at %s: the province passes to our crown and %s's flag is "
			+ "struck."
		) % [place, whom]
	if whom == GazetteCopyVoice.CROWN:
		return (
			"Not a shot was fired at %s: the province passes to %s and our crown's flag is "
			+ "struck."
		) % [place, who]
	return "Not a shot was fired at %s: the province passes from %s to %s." % [place, whom, who]


## A standoff still buries men: the crown's own dead are counted
## (wiki: the-gazette § What the crown can know).
static func battle_standoff(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		return _with_own(
			(
				"Our crown and %s stand off at %s; the guns fall silent with nothing "
				+ "settled."
			) % [whom, place],
			rec,
			"regiments"
		)
	return _with_own(
		"%s and %s stand off at %s; the guns fall silent unsettled." % [who, whom, place],
		rec,
		"regiments"
	)


static func sea_held(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		var sunk: int = GazetteCopyVoice.count(rec)
		return _with_own(
			(
				"Our squadrons hold the %s, and %s loses %s to the bottom."
			) % [place, whom, GazetteCopyVoice.hulls(sunk)],
			rec,
			"hulls"
		)
	if not rec.has("count"):
		return "%s holds the %s against %s." % [who, place, whom]
	var lost: int = GazetteCopyVoice.count(rec)
	return "%s holds the %s; %d hulls of %s %s sunk or taken." % [
		who, place, lost, whom, GazetteCopyVoice.verb(lost)
	]


## The crown holds the water but still spends hulls to do it: its own loss is
## counted (wiki: the-gazette § What the crown can know).
static func sea_withdrew(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var place: String = String(rec.get("place", ""))
	if bool(rec.get("self_act", false)):
		return _with_own(
			"Our squadron quits the %s; %s holds the water." % [place, whom], rec, "hulls"
		)
	if whom == GazetteCopyVoice.CROWN:
		return _with_own(
			"%s withdraws from the %s, and our crown holds the zone." % [who, place],
			rec,
			"hulls"
		)
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
