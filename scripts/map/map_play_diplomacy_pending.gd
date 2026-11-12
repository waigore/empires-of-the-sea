class_name MapPlayDiplomacyPending
extends RefCounted
## Consent decisions waiting on the human court: call to arms, intervention and
## rival proposals. Presentation only — opens the diplomacy panel and raises
## each decision once (wiki: diplomacy § Alliances / Intervention). Split from
## MapPlayDiplomacy so the phase orchestrator does not own the despatch copy
## (REQ-P3-01).


## One decision's identity, so the court is told about it once and not again on
## every press that re-opens the panel (wiki: diplomacy § Intervention — the
## choice is presented once, at war declaration time).
static func decision_key(kind: String, parts: Array) -> String:
	var out: PackedStringArray = [kind]
	for part: Variant in parts:
		out.append(str(part))
	return ":".join(out)


## Raises a decision's despatch unless the court has already heard it.
static func announce(play: PlaySession, key: String, text: String) -> void:
	if play.announced_decisions.has(key):
		return
	play.announced_decisions[key] = true
	play.hud.toast(text)


## Marks every decision now waiting as told. The AI pass raises each new
## decision's line itself, so the court must not repeat it when the turn
## resolver opens the panel on the same press.
static func mark_announced(play: PlaySession) -> void:
	if play.diplomacy == null:
		return
	for call: Dictionary in play.diplomacy.pending_calls:
		play.announced_decisions[
			decision_key("call", [int(call["aggressor"]), int(call["defender"])])
		] = true
	for offer: Dictionary in play.diplomacy.pending_interventions:
		play.announced_decisions[
			decision_key("intervention", [int(offer["aggressor"]), int(offer["target"])])
		] = true
	for proposal: Dictionary in play.diplomacy.pending_offers:
		play.announced_decisions[
			decision_key("offer", [int(proposal["from"]), String(proposal["kind"])])
		] = true


## Opens the court on the waiting call and tells the player what is at stake.
static func show_call(play: PlaySession) -> void:
	if play.diplomacy == null or play.hud == null:
		return
	var call: Dictionary = CallToArms.pending_call_for(play.diplomacy, play.player_faction)
	if call.is_empty():
		return
	MapPlayDiplomacy.open(play)
	announce(
		play,
		decision_key("call", [int(call["aggressor"]), int(call["defender"])]),
		"%s calls on our alliance against %s."
		% [
			FactionCatalog.name_of(int(call["defender"])),
			FactionCatalog.name_of(int(call["aggressor"])),
		]
	)


## Opens the court on a waiting intervention and names what is at stake.
static func show_intervention(play: PlaySession) -> void:
	if play.diplomacy == null or play.hud == null:
		return
	var offer: Dictionary = Intervention.pending_for(play.diplomacy, play.player_faction)
	if offer.is_empty():
		return
	MapPlayDiplomacy.open(play)
	announce(
		play,
		decision_key("intervention", [int(offer["aggressor"]), int(offer["target"])]),
		"%s declares war on %s. %s"
		% [
			FactionCatalog.name_of(int(offer["aggressor"])),
			FactionCatalog.name_of(int(offer["target"])),
			Intervention.offer_text(offer),
		]
	)


## Opens the court on a waiting rival proposal and names what is offered.
static func show_offer(play: PlaySession) -> void:
	if play.diplomacy == null or play.hud == null:
		return
	var offer: Dictionary = DiplomacyProposals.pending_for(
		play.diplomacy, play.player_faction
	)
	if offer.is_empty():
		return
	MapPlayDiplomacy.open(play)
	announce(
		play,
		decision_key("offer", [int(offer["from"]), String(offer["kind"])]),
		"%s proposes %s. Answer the proposal."
		% [
			FactionCatalog.name_of(int(offer["from"])),
			DiplomacyProposals.describe(
				String(offer["kind"]), String(offer.get("stage", ""))
			),
		]
	)
