class_name GazetteCopy
extends RefCounted
## The Gazette's voice: thick imperial prose over one structured record
## (wiki: the-gazette § Prose; DR-20261110-14). One register for all three
## classes — the crown's sheet speaks with the same authority about its own
## deeds and the doings of the courts it follows.
##
## Pure string work: every figure and name arrives in the record, so no template
## can invent an outcome the rules did not decide (REQ-P2-03, REQ-P3-03).
##
## Record keys, all optional but `kind`:
##   kind      item kind (see [Gazette])
##   self_act  true when our crown is the actor, so the line speaks as "our"
##   who       the court the item is about
##   whom      its counterpart
##   aggressor / target   the parties of a war a court answered or watched
##   place     province or sea zone
##   label     a treaty stage, proposal or technology
##   count     hulls or regiments lost by the beaten side
##   prize     the cargo a raid took, already phrased ("3 grain")
##   bonus     a regiment type that re-formed after a mutual ruin
##   cause     "war" when a pact fell to a declaration
##   amount    ducats
##   percent   subsidy share
##   defended  true when the actor held a province against an attack


## The crown's own voice in a printed line.
const CROWN: String = "our crown"


## One printed line. An unknown kind prints nothing, so a new event can never
## reach the sheet as an empty rule (REQ-P2-03).
static func line(rec: Dictionary) -> String:
	var who: String = String(rec.get("who", ""))
	var whom: String = String(rec.get("whom", ""))
	var aggressor: String = String(rec.get("aggressor", ""))
	var target: String = String(rec.get("target", ""))
	var place: String = String(rec.get("place", ""))
	var label: String = String(rec.get("label", ""))
	var self_act: bool = bool(rec.get("self_act", false))
	match String(rec.get("kind", "")):
		"warDeclared":
			if self_act:
				return (
					"Our crown has cast the glove at %s: war is proclaimed and letters of "
					+ "marque go out to every captain."
				) % whom
			if whom == CROWN:
				return (
					"%s has thrown down the glove before our court: the crown is at war, "
					+ "and the sea will be the judge of it."
				) % who
			return (
				"The gauntlet passes between %s and %s; war is proclaimed, and no merchant "
				+ "sail is safe between them."
			) % [who, whom]
		"peaceMade":
			if self_act:
				return (
					"Peace is concluded with %s. The drums fall silent and the crown's "
					+ "captains are recalled to their stations."
				) % whom
			return "%s and %s have laid down the sword and concluded a peace." % [who, whom]
		"allianceFormed":
			if self_act:
				return (
					"A formal alliance is sealed with %s; our fortunes are joined before all "
					+ "the world."
				) % whom
			return "%s and %s have clasped hands in a formal league." % [who, whom]
		"allianceBroken":
			if self_act:
				return (
					"Our alliance with %s is broken. The court will remember who quitted whom."
					% whom
				)
			return "%s has broken faith with %s and quitted the alliance." % [who, whom]
		"joinEmpire":
			if self_act:
				return (
					"The court of %s has joined our empire; its provinces are ours to govern "
					+ "and its people ours to protect."
				) % whom
			return (
				"The minor court of %s is swallowed by %s; its towns now answer to that "
				+ "crown."
			) % [whom, who]
		"colonyFormed":
			if self_act:
				return (
					"Our crown has taken the people of %s under its protection as a colony."
					% whom
				)
			return (
				"%s has planted its colours over the tribe of %s; another people answers to "
				+ "its court."
			) % [who, whom]
		"colonyReleased":
			if self_act:
				return "The colony of %s is released from our protection and stands alone." % whom
			return "%s has released %s from its colonial protection." % [who, whom]
		"overtureEstablished":
			if self_act:
				return "Our court has established the %s with %s." % [label, whom]
			return "%s has established the %s with %s." % [who, label, whom]
		"overtureRejected":
			if self_act:
				return "Our offer of the %s to %s was refused." % [label, whom]
			return "%s was refused the %s by %s." % [who, label, whom]
		"callToArmsAccepted":
			if self_act:
				return (
					"Our crown answers the call of %s and joins the war against %s; the "
					+ "alliance is honoured."
				) % [whom, aggressor]
			return (
				"%s answers our call to arms and joins the war against %s; the league holds."
			) % [who, aggressor]
		"callToArmsRefused":
			if self_act:
				return (
					"Our crown refuses the call of %s against %s. The alliance is broken by it, "
					+ "and the court knows the price."
				) % [whom, aggressor]
			return (
				"%s refuses our call to arms against %s; that alliance is at an end."
			) % [who, aggressor]
		"interventionProtest":
			if self_act:
				return (
					"Our crown protests the war of %s upon %s; the ministry makes its "
					+ "displeasure plain before every court."
				) % [aggressor, target]
			return "%s protests %s's war upon %s." % [who, aggressor, target]
		"interventionIntervened":
			if self_act:
				return (
					"Our crown intervenes against %s on the side of %s; the sword is drawn in "
					+ "another's quarrel."
				) % [aggressor, target]
			return "%s intervenes against %s in the defence of %s." % [who, aggressor, target]
		"interventionDoNothing":
			if self_act:
				return "Our court stood aside while %s made war on %s." % [aggressor, target]
			return "%s stood aside while %s fell upon %s." % [who, aggressor, target]
		"proposalAccepted":
			if self_act:
				return "%s has accepted our offer of %s." % [whom, label]
			return "Our court has accepted %s's offer of %s." % [who, label]
		"proposalRefused":
			if self_act:
				return "%s has refused our offer of %s." % [whom, label]
			return "Our court has declined %s's offer of %s." % [who, label]
		"subsidySet":
			if self_act:
				return "A subsidy of %d%% of our trade is settled on %s." % [
					int(rec.get("percent", 0)), whom
				]
			return "%s settles a subsidy of %d%% on %s." % [
				who, int(rec.get("percent", 0)), whom
			]
		"subsidyCancelled":
			if self_act:
				return "Our subsidy to %s is cancelled." % whom
			return "%s has cancelled its subsidy to %s." % [who, whom]
		"ftpSigned":
			if self_act:
				return (
					"A favoured trading pact is signed with %s; our merchants take precedence "
					+ "in its ports."
				) % whom
			return "%s and %s have signed a favoured trading pact." % [who, whom]
		"ftpRefused":
			if self_act:
				return "Our offer of a favoured trading pact was refused by %s." % whom
			return "%s refused %s's offer of a favoured trading pact." % [whom, who]
		"ftpRevoked":
			if String(rec.get("cause", "")) == "war":
				return "The war has ended the favoured trading pact with %s." % whom
			if self_act:
				return "Our court has ended the favoured trading pact with %s." % whom
			return "%s has ended its favoured trading pact with %s." % [who, whom]
		"boycottSet":
			if self_act:
				return "Our colonies are closed to %s's trade." % whom
			return "%s has closed its colonies to %s's trade." % [who, whom]
		"boycottRevoked":
			if String(rec.get("cause", "")) == "war":
				if self_act:
					return "The war ends our boycott of %s's colonies." % whom
				return "The war has lifted %s's boycott of our colonies." % who
			if self_act:
				return "Our court lifts its boycott of %s." % whom
			return "%s has lifted its boycott of our colonies." % who
		"grantAid":
			if self_act:
				return "The crown sends %s in aid to %s." % [_money(rec), whom]
			if whom == CROWN:
				return "The crown receives %s in aid from %s." % [_money(rec), who]
			return "%s sends %s in aid to %s." % [who, _money(rec), whom]
		"firstContact":
			if self_act:
				return (
					"Our court has made first contact with %s; a new people enters our "
					+ "reckoning."
				) % whom
			return "%s has made first contact with %s." % [who, whom]
		"greatPowerFell":
			return (
				"%s is fallen. Its seat is taken, its provinces pass to %s, and its name is "
				+ "struck from the roll of powers."
			) % [who, whom]
		"battleCapture":
			if self_act:
				return (
					"Our crown takes %s at the point of the bayonet; %s yields the province and "
					+ "%d regiments."
				) % [place, whom, _count(rec)]
			if whom == CROWN:
				return (
					"%s has carried %s from our crown; %d of our regiments are lost with it."
				) % [who, place, _count(rec)]
			return "%s has taken %s from %s at the point of the bayonet." % [who, place, whom]
		"battleHeld":
			if self_act:
				if bool(rec.get("defended", false)):
					return (
						"Our crown holds %s against %s; %d of their regiments are broken."
					) % [place, whom, _count(rec)]
				return "Our crown holds the field at %s; %d of their regiments are broken." % [
					place, _count(rec)
				]
			if not rec.has("count"):
				if bool(rec.get("defended", false)):
					return "%s holds %s against %s." % [who, place, whom]
				return "%s holds the field at %s against %s." % [who, place, whom]
			if bool(rec.get("defended", false)):
				return "%s holds %s against %s; %d regiments are broken." % [
					who, place, whom, _count(rec)
				]
			# The crown's own losses always print their numbers, even in a field
			# battle it lost (wiki: the-gazette § What the crown can know).
			if whom == CROWN:
				return (
					"%s holds the field at %s against our crown; %d of our regiments are lost."
				) % [who, place, _own(rec)]
			return "%s holds the field at %s against %s." % [who, place, whom]
		"battleAnnihilated":
			var ruin: String = "At %s the two crowns ruin one another; the field is left empty." % place
			var bonus: String = String(rec.get("bonus", ""))
			if not bonus.is_empty():
				ruin += " A %s garrison re-forms in the ruin." % bonus
			return ruin
		"battleStandoff":
			# A standoff still buries men: the crown's own dead are counted
			# (wiki: the-gazette § What the crown can know).
			var own: int = _own(rec)
			var tail: String = "" if own <= 0 else " %d of our regiments lost." % own
			if self_act:
				return (
					"Our crown and %s stand off at %s; the guns fall silent with nothing "
					+ "settled."
				) % [whom, place] + tail
			return "%s and %s stand off at %s; the guns fall silent unsettled." % [
				who, whom, place
			] + tail
		"seaHeld":
			if self_act:
				return (
					"Our squadrons hold the %s, and %s loses %d hulls to the bottom."
				) % [place, whom, _count(rec)]
			if not rec.has("count"):
				return "%s holds the %s against %s." % [who, place, whom]
			return "%s holds the %s; %d hulls of %s are sunk or taken." % [
				who, place, _count(rec), whom
			]
		"seaWithdrew":
			if self_act:
				return "Our squadron quits the %s; %s holds the water." % [place, whom]
			# The crown holds the water but still spends hulls to do it: its own
			# loss is counted (wiki: the-gazette § What the crown can know).
			if whom == CROWN and _own(rec) > 0:
				return (
					"%s withdraws from the %s, and our crown holds the zone; %d of our hulls lost."
				) % [who, place, _own(rec)]
			return "%s withdraws from the %s, and %s holds the zone." % [who, place, whom]
		"seaDraw":
			if self_act:
				return (
					"Our squadrons and %s trade broadsides in the %s and part with nothing "
					+ "decided."
				) % [whom, place]
			return "%s and %s trade broadsides in the %s and withdraw." % [who, whom, place]
		"techFinished":
			if self_act:
				return "Our scholars have finished the %s; its secrets are ours to use." % label
			return "%s has completed the %s." % [who, label]
		"richesRendered":
			return (
				"The estates render %s into the crown's coffers this year, and the ledger "
				+ "closes the richer."
			) % _money(rec)
		"raidSuffered":
			if String(rec.get("sunk", "")).is_empty():
				return (
					"Raiders have taken %s off %s; no hull was lost, but the cargo is gone."
					% [String(rec.get("prize", "no cargo")), place]
				)
			return "Raiders have taken %s off %s and sent the %s to the bottom." % [
				String(rec.get("prize", "no cargo")), place, String(rec.get("sunk", ""))
			]
		"raidPrize":
			if String(rec.get("sunk", "")).is_empty():
				return "Our station takes %s off %s as lawful prize." % [
					String(rec.get("prize", "no cargo")), place
				]
			return "Our station takes %s off %s as lawful prize and sends the %s down." % [
				String(rec.get("prize", "no cargo")), place, String(rec.get("sunk", ""))
			]
	return ""


static func _count(rec: Dictionary) -> int:
	return maxi(int(rec.get("count", 0)), 0)


## The crown's own dead in a battle it fought. Another court's fight carries no
## `own_lost`, so its losses are never counted (wiki: the-gazette § What the
## crown can know).
static func _own(rec: Dictionary) -> int:
	return maxi(int(rec.get("own_lost", 0)), 0)


static func _money(rec: Dictionary) -> String:
	return DiplomacyCatalog.money(int(rec.get("amount", 0)))
