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
##
## Each desk owns one register of the sheet — [GazetteCopyWar],
## [GazetteCopyCourt], [GazetteCopyLeague], [GazetteCopyBattle],
## [GazetteCopyLedger] — and this class is the one table of kinds that routes a
## record to the desk that speaks it. A kind absent from the table prints
## nothing, so a new event can never reach the sheet as an empty rule
## (REQ-P2-03, REQ-P3-01).


## The crown's own voice in a printed line.
const CROWN: String = GazetteCopyVoice.CROWN

## kind → the desk function that speaks it. The table is the single place a kind
## is declared: no other file in the sheet keeps a parallel list.
static var _desks: Dictionary = {}


## Every kind the copy desk can print, in catalogue order.
static func kinds() -> Array[String]:
	var out: Array[String] = []
	for kind: String in _table().keys():
		out.append(kind)
	return out


## One printed line. An unknown kind prints nothing, so a new event can never
## reach the sheet as an empty rule (REQ-P2-03).
static func line(rec: Dictionary) -> String:
	var kind: String = String(rec.get("kind", ""))
	if not _table().has(kind):
		return ""
	return String((_table()[kind] as Callable).call(rec))


## The kind table, built once on first use: a static initializer cannot name the
## desks before their scripts have loaded.
static func _table() -> Dictionary:
	if _desks.is_empty():
		_desks = {
			# The sword abroad.
			"warDeclared": GazetteCopyWar.war_declared,
			"peaceMade": GazetteCopyWar.peace_made,
			"allianceFormed": GazetteCopyWar.alliance_formed,
			"allianceBroken": GazetteCopyWar.alliance_broken,
			"callToArmsAccepted": GazetteCopyWar.call_to_arms_accepted,
			"callToArmsRefused": GazetteCopyWar.call_to_arms_refused,
			"greatPowerFell": GazetteCopyWar.great_power_fell,
			# The crown's reach over other peoples.
			"joinEmpire": GazetteCopyCourt.join_empire,
			"colonyFormed": GazetteCopyCourt.colony_formed,
			"colonyReleased": GazetteCopyCourt.colony_released,
			"firstContact": GazetteCopyCourt.first_contact,
			# The court's business abroad.
			"overtureEstablished": GazetteCopyLeague.overture_established,
			"overtureRejected": GazetteCopyLeague.overture_rejected,
			"interventionProtest": GazetteCopyLeague.intervention_protest,
			"interventionIntervened": GazetteCopyLeague.intervention_intervened,
			"interventionDoNothing": GazetteCopyLeague.intervention_do_nothing,
			"proposalAccepted": GazetteCopyLeague.proposal_accepted,
			"proposalRefused": GazetteCopyLeague.proposal_refused,
			"subsidySet": GazetteCopyLeague.subsidy_set,
			"subsidyCancelled": GazetteCopyLeague.subsidy_cancelled,
			"ftpSigned": GazetteCopyLeague.ftp_signed,
			"ftpRefused": GazetteCopyLeague.ftp_refused,
			"ftpRevoked": GazetteCopyLeague.ftp_revoked,
			"boycottSet": GazetteCopyLeague.boycott_set,
			"boycottRevoked": GazetteCopyLeague.boycott_revoked,
			"grantAid": GazetteCopyLeague.grant_aid,
			# The fighting.
			"battleCapture": GazetteCopyBattle.battle_capture,
			"battleHeld": GazetteCopyBattle.battle_held,
			"battleAnnihilated": GazetteCopyBattle.battle_annihilated,
			"battleStandoff": GazetteCopyBattle.battle_standoff,
			"seaHeld": GazetteCopyBattle.sea_held,
			"seaWithdrew": GazetteCopyBattle.sea_withdrew,
			"seaDraw": GazetteCopyBattle.sea_draw,
			# The crown's book.
			"techFinished": GazetteCopyLedger.tech_finished,
			"richesRendered": GazetteCopyLedger.riches_rendered,
			"raidSuffered": GazetteCopyLedger.raid_suffered,
			"raidPrize": GazetteCopyLedger.raid_prize,
		}
	return _desks
