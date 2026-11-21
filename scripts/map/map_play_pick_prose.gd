class_name MapPlayPickProse
extends RefCounted
## Shared wording for every counsel-pick surface: one capital and a full stop,
## a prose list join, and a capped line that counts the rest (`… and N more`).
## Domain picks and *Words modules name their own clauses; they do not re-own
## this chrome (REQ-P3-01, REQ-P3-02, REQ-P5-06).


## `text` as a printed sentence: "the court would …" → "The court would …".
static func sentence(text: String) -> String:
	if text.is_empty():
		return ""
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


## A list read the way prose reads it: "A", "A and B", "A, B and C".
static func join(parts: Array[String]) -> String:
	if parts.is_empty():
		return ""
	if parts.size() <= 2:
		return " and ".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]


## First `limit` parts in prose, then "and N more" for the rest — so a handset's
## reading stays one line of chrome (REQ-P5-07). Empty when nothing is named.
## When the line is capped it joins the named heads with commas (not "and"),
## matching every sheet that already prints `…, X and N more`.
static func capped(parts: Array[String], limit: int) -> String:
	if parts.is_empty() or limit <= 0:
		return ""
	if parts.size() <= limit:
		return join(parts)
	var named: Array[String] = parts.slice(0, limit)
	return "%s and %d more" % [", ".join(named), parts.size() - limit]


## True when a crew-backed counsel pick may read the crown's session: a live
## campaign with a civilian layer, a ledger, and a court that plans. Market,
## estates and spy picks share this gate so they cannot disagree on when the
## page is silent (REQ-P3-02).
static func crown_crew_ready(play: PlaySession) -> bool:
	if play == null or play.world == null or play.campaign_over():
		return false
	if play.observer_mode or play.civilian_layer == null:
		return false
	var faction: int = play.player_faction
	if play.ledger_for(faction) == null:
		return false
	return AiControl.court_kind(play, faction) != AiControl.KIND_NONE
