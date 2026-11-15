class_name MapPlayTurn
extends RefCounted
## Turn closure: the consent ladder, then the handed-over finish. A pending
## consent decision stops the calendar until the court answers; once the ladder
## is clear, every answer path resumes the same way (REQ-P3-02).
##
## Movement, rearmament, combat, upkeep and the new turn live in
## MapPlayTurnFinish, one named phase per step. Campaign close and standing live
## in MapPlayCampaign, land battles in MapPlayLandTurn, sea battles in
## MapPlayNavalTurn, fog decay in MapPlayFogTurn.

## False when no view is mounted to follow: the headless harness
## (`tools/ai_vs_ai.gd`) runs the same rules with no chart, HUD or lens refresh,
## so the turn skips the pure-view pass (docs/ai-observer.md § Performance
## budget). Live play leaves this true.
static var view_live: bool = true


static func end_turn(play: PlaySession) -> void:
	# Auto holds the seat: the paced driver presses the turn, not the court
	# (wiki: auto-mode § End Turn. The seal stays visible and inert).
	if play.auto_active:
		return
	# The battle plate owns input while a Quick Battle plays; a second turn would
	# stack behind it (REQ-P5-06).
	if play.hud != null and play.hud.is_quick_battle_shown():
		return
	# A decided or calendar-closed campaign accepts no further turns
	# (wiki: victory § Victory Check, turn-time-mapping § Campaign calendar cap).
	if play.campaign_over():
		play.hud.toast(MapPlayCampaign.closed_message(play))
		return
	# A consent decision already waiting keeps the calendar shut.
	var human: int = play.human_faction_id()
	if CallToArms.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyConsent.show_call(play)
		return
	if Intervention.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyConsent.show_intervention(play)
		return
	if DiplomacyProposals.has_pending(play.diplomacy, human):
		play.turn_suspended = true
		MapPlayDiplomacyConsent.show_offer(play)
		return
	if not MapPlayDiplomacy.resolve_turn(play):
		return
	_finish_turn(play)


## The paced driver's turn, once Auto holds the crown's seat: each waiting
## decision is answered in the crown's own interest, then the turn runs to its
## staged passes (wiki: auto-mode § No interruptions).
static func auto_turn(play: PlaySession) -> void:
	if play.hud != null and play.hud.is_quick_battle_shown():
		return
	if play.campaign_over():
		MapPlayAuto.note(play, MapPlayCampaign.closed_message(play))
		return
	# A decision the player left open when the seat changed hands, and any the
	# rival pass raises below: Auto answers each one rather than holding the
	# calendar. The guard keeps a malformed ladder from spinning the driver.
	var answered: int = 0
	while MapPlayAuto.answer_pending(play) and answered < 8:
		answered += 1
	if not MapPlayDiplomacy.resolve_turn(play):
		if not MapPlayAuto.answer_pending(play):
			return
		MapPlayDiplomacy.close_turn(play)
	play.turn_suspended = false
	_finish_turn(play)


## The player answers a call to arms; the suspended turn then runs to its end
## (wiki: diplomacy § Alliances § Mutual defence).
static func answer_call(play: PlaySession, accept: bool) -> void:
	if play.diplomacy == null:
		return
	# A stale button press must never close the phase or advance the calendar.
	if not CallToArms.has_pending(play.diplomacy, play.player_faction):
		return
	var result: Dictionary = CallToArms.resolve_human(play.diplomacy, accept)
	_resume(play, result, "No call awaits an answer.")


## The player answers a waiting intervention; the suspended turn then runs to
## its end, or stops again for another waiting decision (wiki: diplomacy).
static func answer_intervention(play: PlaySession, kind: String) -> void:
	if play.diplomacy == null:
		return
	var offer: Dictionary = Intervention.pending_for(play.diplomacy, play.player_faction)
	if offer.is_empty():
		return
	# Protesting an aggressor holding Propaganda costs 5, not 10; the rules read
	# that crown's ledger, never ours (wiki: tech-tree-diplomacy-civilian).
	var ledger: PlayerEconomy = play.ledger_for(int(offer.get("aggressor", -1)))
	var tech: Dictionary = ledger.tech_unlocked if ledger != null else {}
	var result: Dictionary = Intervention.resolve_human(play.diplomacy, kind, tech)
	_resume(play, result, "No intervention awaits an answer.")


## The player answers a rival proposal; the suspended turn then runs to its end,
## or stops again for another waiting decision (wiki: diplomacy § GP AI policy).
static func answer_offer(play: PlaySession, accept: bool) -> void:
	if play.diplomacy == null:
		return
	if not DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		return
	var result: Dictionary = DiplomacyProposals.resolve_human(play.diplomacy, play.world, accept)
	if bool(result.get("ok", false)):
		_book_overture(play, result, accept)
	_resume(play, result, "No proposal awaits an answer.")


## The proposing court pays for its overture; the human treasury is untouched.
## A peace offer starts its own cooldown once the court answers; every other
## proposal starts the improve-relations cooldown (DR-20261109-06/07). The answer
## is the asking court's memory either way (DR-20261115-01).
static func _book_overture(play: PlaySession, result: Dictionary, accept: bool) -> void:
	if play.ai == null:
		return
	var from_id: int = int(result.get("from", -1))
	if String(result.get("kind", "")) == DiplomacyProposals.KIND_PEACE:
		play.ai.note_peace(from_id, play.player_faction, play.turn, accept)
	else:
		play.ai.note_overture(from_id, play.player_faction, play.turn)


## One answer path: a refused answer says why and leaves the phase shut; an
## accepted one says its piece, refreshes the ladder and either opens the next
## waiting decision or runs the suspended turn to its end (wiki: diplomacy).
## `fallback` names the refusal when the rules gave no reason.
static func _resume(play: PlaySession, result: Dictionary, fallback: String) -> void:
	if not bool(result.get("ok", false)):
		if play.hud != null:
			play.hud.toast(String(result.get("reason", fallback)))
		return
	if play.hud != null:
		var message: String = String(result.get("message", ""))
		if not message.is_empty():
			play.hud.toast(message)
	MapPlayDiplomacy.refresh(play)
	if _show_pending(play):
		return
	play.turn_suspended = false
	MapPlayDiplomacy.close_turn(play)
	_finish_turn(play)


## Opens the court on whichever consent decision still waits — a call to arms,
## an intervention or a rival proposal — so each answer path resumes the same
## ladder. True when one did.
static func _show_pending(play: PlaySession) -> bool:
	if CallToArms.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacyConsent.show_call(play)
		return true
	if Intervention.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacyConsent.show_intervention(play)
		return true
	if DiplomacyProposals.has_pending(play.diplomacy, play.player_faction):
		MapPlayDiplomacyConsent.show_offer(play)
		return true
	return false


## Movement, combat, upkeep and the new turn, once the diplomacy phase closed.
## MapPlayTurnFinish owns the phases and their order.
static func _finish_turn(play: PlaySession) -> void:
	MapPlayTurnFinish.run(play)
