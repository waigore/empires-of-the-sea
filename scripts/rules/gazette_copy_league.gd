class_name GazetteCopyLeague
extends RefCounted
## The court's business abroad: overtures, interventions, proposals, subsidies,
## favoured trading pacts, boycotts and aid. Each line states only what the
## diplomacy ledger already settled — a stage, a share, a sum — and the desk
## phrases it (wiki: the-gazette § Item catalog; REQ-P2-03).


static func overture_established(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var label: String = String(rec.get("label", ""))
	if bool(rec.get("self_act", false)):
		return "Our court has established the %s with %s." % [label, whom]
	return "%s has established the %s with %s." % [who, label, whom]


static func overture_rejected(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var label: String = String(rec.get("label", ""))
	if bool(rec.get("self_act", false)):
		return "Our offer of the %s to %s was refused." % [label, whom]
	return "%s was refused the %s by %s." % [who, label, whom]


static func intervention_protest(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var aggressor: String = String(rec.get("aggressor", ""))
	var target: String = String(rec.get("target", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our crown protests the war of %s upon %s; the ministry makes its "
			+ "displeasure plain before every court."
		) % [aggressor, target]
	return "%s protests %s's war upon %s." % [who, aggressor, target]


static func intervention_intervened(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var aggressor: String = String(rec.get("aggressor", ""))
	var target: String = String(rec.get("target", ""))
	if bool(rec.get("self_act", false)):
		return (
			"Our crown intervenes against %s on the side of %s; the sword is drawn in "
			+ "another's quarrel."
		) % [aggressor, target]
	return "%s intervenes against %s in the defence of %s." % [who, aggressor, target]


static func intervention_do_nothing(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var aggressor: String = String(rec.get("aggressor", ""))
	var target: String = String(rec.get("target", ""))
	if bool(rec.get("self_act", false)):
		return "Our court stood aside while %s made war on %s." % [aggressor, target]
	return "%s stood aside while %s fell upon %s." % [who, aggressor, target]


static func proposal_accepted(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var label: String = String(rec.get("label", ""))
	if bool(rec.get("self_act", false)):
		return "%s has accepted our offer of %s." % [whom, label]
	return "Our court has accepted %s's offer of %s." % [who, label]


static func proposal_refused(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var label: String = String(rec.get("label", ""))
	if bool(rec.get("self_act", false)):
		return "%s has refused our offer of %s." % [whom, label]
	return "Our court has declined %s's offer of %s." % [who, label]


static func subsidy_set(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var percent: int = int(rec.get("percent", 0))
	if bool(rec.get("self_act", false)):
		return "A subsidy of %d%% of our trade is settled on %s." % [percent, whom]
	return "%s settles a subsidy of %d%% on %s." % [who, percent, whom]


static func subsidy_cancelled(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return "Our subsidy to %s is cancelled." % whom
	return "%s has cancelled its subsidy to %s." % [who, whom]


static func ftp_signed(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return (
			"A favoured trading pact is signed with %s; our merchants take precedence "
			+ "in its ports."
		) % whom
	return "%s and %s have signed a favoured trading pact." % [who, whom]


static func ftp_refused(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return "Our offer of a favoured trading pact was refused by %s." % whom
	return "%s refused %s's offer of a favoured trading pact." % [whom, who]


## A pact ended by a declaration is the war's doing, not the court's choice.
static func ftp_revoked(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if String(rec.get("cause", "")) == "war":
		return "The war has ended the favoured trading pact with %s." % whom
	if bool(rec.get("self_act", false)):
		return "Our court has ended the favoured trading pact with %s." % whom
	return "%s has ended its favoured trading pact with %s." % [who, whom]


static func boycott_set(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if bool(rec.get("self_act", false)):
		return "Our colonies are closed to %s's trade." % whom
	return "%s has closed its colonies to %s's trade." % [who, whom]


## A boycott lifted by a declaration is the war's doing, not the court's choice.
static func boycott_revoked(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	if String(rec.get("cause", "")) == "war":
		if bool(rec.get("self_act", false)):
			return "The war ends our boycott of %s's colonies." % whom
		return "The war has lifted %s's boycott of our colonies." % who
	if bool(rec.get("self_act", false)):
		return "Our court lifts its boycott of %s." % whom
	return "%s has lifted its boycott of our colonies." % who


static func grant_aid(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var money: String = GazetteCopyVoice.money(rec)
	if bool(rec.get("self_act", false)):
		return "The crown sends %s in aid to %s." % [money, whom]
	if whom == GazetteCopyVoice.CROWN:
		return "The crown receives %s in aid from %s." % [money, who]
	return "%s sends %s in aid to %s." % [who, money, whom]
