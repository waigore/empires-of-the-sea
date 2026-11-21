class_name MapPlayColonyPick
extends RefCounted
## The Tribe the court's own envoy is drawing into the empire this turn, named on
## THE COLONIES before the crown presses a row (wiki: diplomacy § GP–Tribe Rules;
## DR-20261121-16).
##
## The reading is not a second opinion: it is `AiTribeColony.best` — the ambition
## the rival pass and the objective ledger price the `expansion.tribe_chain` slot
## with — asked for this crown on her own relations, purse, studies and footing,
## so the sheet cannot name a link the court's pass would not take
## (REQ-P2-03, REQ-P3-03).
##
## The study gate is the pass's own too: `DiplomacyCatalog.tech_needed` names the
## study that opens the next link, exactly as `AiTribeColony.door` does for the
## pass, so a court missing it reads the door it owes rather than a link it
## cannot sign (DR-20261114-05).
##
## A reading only: nothing here sends an envoy, signs an overture, buys a colony
## or spends a ducat, and the crown still presses her own order (REQ-P5-06).

## The court would press its chain one link toward a colony.
const KIND_CHAIN: String = "chain"
## The next link is open to the court, but the study it needs is missing.
const KIND_STUDY: String = "study"
## A war footing holds a new chain shut and the court holds no stake to keep.
const KIND_CLOSED: String = "closed"

## What a footing at war says instead of a link: the same reason the pass denies
## the slot with (`AiTribeColony.REASON_WAR`), worded for the colony sheet.
const CLOSED_LINE: String = (
	"the court would open no colony chain this turn — at war, its envoy waits "
	+ "on the front"
)

## The stage's own words, the catalogue's names lowered into prose: what the
## envoy would offer the Tribe this turn.
const STAGE_WORDS: Dictionary = {
	DiplomacyCatalog.STAGE_CONSULATE: "a Trade Consulate",
	DiplomacyCatalog.STAGE_EMBASSY: "an Embassy",
	DiplomacyCatalog.STAGE_NAP: "a Non-Aggression Pact",
	DiplomacyCatalog.STAGE_JOIN_EMPIRE: "the Join Empire",
}


## The sheet's sentence: the pick's own clause, capitalised and closed — the
## same one wording every pick surface prints (REQ-P3-02, REQ-P5-06).
static func line(play: PlaySession, _snapshot: Dictionary = {}) -> String:
	return MapPlayPickProse.sentence_of(pick(play))


## The colony sheet's pick as THE COLONIES prints it: `{kind, target, stage,
## cost, line}` for a link the court would press, `{kind, target, study, line}`
## for a chain its studies hold, `{kind, line}` for a footing that shuts new
## chains, and {} when the court has no chain to name. Empty as well for a crown
## that runs no planner, an observer session, a decided campaign or a session
## with no diplomacy, no chart or no ledger.
static func pick(play: PlaySession) -> Dictionary:
	if not _court_ready(play):
		return {}
	var faction: int = play.player_faction
	var kind: String = AiControl.court_kind(play, faction)
	if kind == AiControl.KIND_NONE:
		return {}
	var config: Variant = AiBind.config(
		kind, faction, play.map_seed, play.ensure_ai().profiles
	)
	if config == null:
		return {}
	var economy: PlayerEconomy = play.ledger_for(faction)
	if economy == null:
		return {}
	var posture: String = AiBind.phase_for(kind, config, play.diplomacy)
	var ambition: Dictionary = AiTribeColony.best(
		play.diplomacy, play.world, play.court_charts, faction,
		economy.treasury, economy.tech_unlocked, posture
	)
	if not ambition.is_empty():
		return of(ambition, economy.tech_unlocked)
	# No link is wanted: the footing says whether a chain is refused or merely
	# unaffordable, and only the refusal earns a gate (the sheet names no gate
	# for a purse, exactly as the estates ledger does).
	var closed: String = AiTribeColony.closed_reason(posture)
	if closed.is_empty():
		return {}
	return {"kind": KIND_CLOSED, "line": CLOSED_LINE}


## The pick worded off one ambition read and the court's own studies: pure, so a
## sheet and its suite drive it without a session.
static func of(ambition: Dictionary, tech: Dictionary) -> Dictionary:
	var target: int = int(ambition.get("target", -1))
	var stage: String = String(ambition.get("stage", ""))
	if target < 0 or stage.is_empty():
		return {}
	var tribe: String = _tribe(target)
	var needed: String = DiplomacyCatalog.tech_needed(
		stage, FactionCatalog.Type.TRIBE
	)
	if not needed.is_empty() and not tech.has(needed):
		return {
			"kind": KIND_STUDY,
			"target": target,
			"study": needed,
			"line": study_line(tribe, TechCatalog.display_name(needed)),
		}
	return {
		"kind": KIND_CHAIN,
		"target": target,
		"stage": stage,
		"cost": int(ambition.get("cost", 0)),
		"line": chain_line(tribe, stage),
	}


## "the court would offer the Guaraní a Trade Consulate this turn, one link
## toward a colony" — the last link names the bond instead, because Join Empire
## is the link that makes the colony.
static func chain_line(tribe: String, stage: String) -> String:
	var offer: String = String(STAGE_WORDS.get(stage, ""))
	if offer.is_empty():
		return ""
	if stage == DiplomacyCatalog.STAGE_JOIN_EMPIRE:
		return "the court would offer %s %s this turn — the bond that makes it a colony" % [
			tribe, offer
		]
	return "the court would offer %s %s this turn, one link toward a colony" % [
		tribe, offer
	]


## "the court's chain with the Guaraní waits on Diplomatic Expertise" — no link
## this turn, and the study the pass names as the door it owes.
static func study_line(tribe: String, study: String) -> String:
	if study.is_empty():
		return ""
	return "the court's chain with %s waits on %s" % [tribe, study]


## The Tribe as the sheet words it: the catalogue's own name behind its article,
## so two Tribes never read alike.
static func _tribe(target: int) -> String:
	return "the %s" % FactionCatalog.name_of(target)


## True when the crown's own court may be read at all: a live campaign with a
## world, a diplomacy record and its own charts.
static func _court_ready(play: PlaySession) -> bool:
	if play == null or play.world == null or play.diplomacy == null:
		return false
	if play.observer_mode or play.campaign_over():
		return false
	if play.court_charts == null or play.ai == null:
		return false
	return play.ledger_for(play.player_faction) != null
