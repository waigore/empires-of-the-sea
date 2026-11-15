class_name ConsentLadder
extends RefCounted
## The order the court answers its blocking consent decisions in: a call to arms
## first, then an intervention, then a rival's proposal (wiki: diplomacy
## § Alliances § Mutual defence, § Intervention, § Court proposals).
##
## One court, one answer at a time, so the turn press, a loaded save, an order
## at court and the Auto seat all ask here instead of keeping a ladder of their
## own. Each pending test still belongs to its own rule ([CallToArms],
## [Intervention], [DiplomacyProposals]); this module only decides which answer
## the court owes first, and [ConsentCopy] still owns the words
## (REQ-P3-02, REQ-P3-03).

## The three blocking decisions, in the order the court answers them.
const CALL: String = "call"
const INTERVENTION: String = "intervention"
const OFFER: String = "offer"


## The first decision still waiting on `faction`, or "" when the court owes no
## answer and may act. A null state has nothing waiting.
static func pending_kind(state: DiplomacyState, faction: int) -> String:
	if CallToArms.has_pending(state, faction):
		return CALL
	if Intervention.has_pending(state, faction):
		return INTERVENTION
	if DiplomacyProposals.has_pending(state, faction):
		return OFFER
	return ""
