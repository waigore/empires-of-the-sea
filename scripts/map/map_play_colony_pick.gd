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
## The press's own gate is the third reading: `DiplomacyRules.can_establish_overture`
## is the call every envoy row answers before it signs a link, so a chain the
## crown's press would refuse — a cold court before the Join Empire, a court its
## envoy already visited this turn, a purse one step short — names the reason the
## row would give rather than an offer the crown cannot make this turn.
##
## The fourth reading is the envoy's own one order (DR-20261121-18): a court gives
## `AiDiplomacyPlanner.decide` one order a turn, and THE COURT prints where it
## went (`MapPlayDiplomacyPick`). A chain the one order did not take reads the
## wait it is — with the court the order went to — so two sheets of one turn
## never promise two orders (REQ-P2-03, REQ-P5-05).
##
## A reading only: nothing here sends an envoy, signs an overture, buys a colony
## or spends a ducat, and the crown still presses her own order (REQ-P5-06).

## The court would press its chain one link toward a colony.
const KIND_CHAIN: String = "chain"
## The next link is open to the court, but the study it needs is missing.
const KIND_STUDY: String = "study"
## A war footing holds a new chain shut and the court holds no stake to keep.
const KIND_CLOSED: String = "closed"
## The next link is open on paper and the crown's own press would refuse it: the
## gate the envoy row answers is why (a cold court before the Join Empire, a
## court its envoy already visited this turn, a purse one step short).
const KIND_GATE: String = "gate"
## The link is open and the press would take it, but the court's one envoy order
## is bound elsewhere this turn: the chain waits behind it, and the line names
## the court the order went to (the same order THE COURT's sheet prints).
const KIND_ENVOY: String = "envoy"

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
## chains, `{kind, target, other, line}` for a link the court's one order does
## not take this turn, and {} when the court has no chain to name. Empty as well
## for a crown that runs no planner, an observer session, a decided campaign or a
## session with no diplomacy, no chart or no ledger.
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
		var read: Dictionary = of(ambition, economy.tech_unlocked)
		# A study the court owes is a gate of its own and reads first; the press's
		# gate only answers for a link the court could otherwise sign.
		if String(read.get("kind", "")) != KIND_CHAIN:
			return read
		var gate: Dictionary = _gate(play, faction, ambition, economy)
		if not bool(gate.get("ok", false)):
			return gated(ambition, String(gate.get("reason", "")))
		# The court's one order (DR-20261121-18): a link the staff's own order did
		# not take this turn reads as the wait it is, with the court that order
		# went to — the same fact THE COURT prints, so two sheets of one turn
		# never promise two orders (REQ-P2-03, REQ-P5-05).
		var plan: Dictionary = MapPlayDiplomacyPick.plan(play)
		if plan.is_empty():
			return read
		var action: Dictionary = plan.get("action", {}) as Dictionary
		if envoy_gives(action, ambition):
			return read
		return behind(ambition, action)
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


## The pick a refused press earns: `{kind, target, line}`, the rule's own reason
## as the clause (`the court's chain with the Guaraní waits this turn (Join Empire
## needs a warmer court than this one — …)`), and {} when the rule gave no reason
## to print — a sheet with nothing to say stays silent rather than guessing.
static func gated(ambition: Dictionary, reason: String) -> Dictionary:
	var target: int = int(ambition.get("target", -1))
	if target < 0:
		return {}
	var line: String = gate_line(_tribe(target), reason)
	if line.is_empty():
		return {}
	return {"kind": KIND_GATE, "target": target, "line": line}


## "the court's chain with the Guaraní waits this turn (Join Empire needs a
## warmer court than this one — the gate stands one step up the meter)" — the
## envoy row's own refusal, said on the colony sheet so the two cannot disagree.
static func gate_line(tribe: String, reason: String) -> String:
	var said: String = reason.strip_edges().trim_suffix(".")
	if said.is_empty() or tribe.is_empty():
		return ""
	return "the court's chain with %s waits this turn (%s)" % [tribe, said]


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


## True when the court's one envoy order this turn is the chain's own rung: the
## same court at the same stage. The planner emits the rung as an overture
## (`AiDiplomacyTreaties.best`), so THE COLONIES and THE COURT read one order
## (REQ-P2-03).
static func envoy_gives(action: Dictionary, ambition: Dictionary) -> bool:
	if action.is_empty():
		return false
	if String(action.get("kind", "")) != DiplomacyOrders.KIND_OVERTURE:
		return false
	if int(action.get("target", -1)) != int(ambition.get("target", -1)):
		return false
	return String(action.get("stage", "")) == String(ambition.get("stage", ""))


## The pick a chain earns when the court's one order is bound elsewhere:
## `{kind, target, other, line}`, `other` the court the order went to (-1 when
## the planner weighed the turn and named nobody).
static func behind(ambition: Dictionary, action: Dictionary) -> Dictionary:
	var target: int = int(ambition.get("target", -1))
	if target < 0:
		return {}
	var other: int = int(action.get("target", -1))
	var line: String = envoy_line(_tribe(target), other)
	if line.is_empty():
		return {}
	return {"kind": KIND_ENVOY, "target": target, "other": other, "line": line}


## "the court's chain with the Guaraní waits this turn — its one order goes to
## England", or "… — its envoy gives the turn no order" when the planner named
## nobody. The wait is the staff's own one order, never a rule that bars the
## press, so the crown may still take the link herself (REQ-P5-05, REQ-P5-06).
static func envoy_line(tribe: String, other: int) -> String:
	if tribe.is_empty():
		return ""
	if other < 0:
		return (
			"the court's chain with %s waits this turn — its envoy gives the "
			% tribe + "turn no order"
		)
	return "the court's chain with %s waits this turn — its one order goes to %s" % [
		tribe, FactionCatalog.name_of(other)
	]


## The Tribe as the sheet words it: the catalogue's own name behind its article,
## so two Tribes never read alike.
static func _tribe(target: int) -> String:
	return "the %s" % FactionCatalog.name_of(target)


## The press's own gate — `DiplomacyRules.can_establish_overture`, the one call
## the envoy row answers — read for the link the ambition named, so the sheet
## names nothing the crown's press would refuse (REQ-P2-03, REQ-P3-01).
static func _gate(
	play: PlaySession, faction: int, ambition: Dictionary, economy: PlayerEconomy
) -> Dictionary:
	return DiplomacyRules.can_establish_overture(
		play.diplomacy, play.world, faction, int(ambition.get("target", -1)),
		String(ambition.get("stage", "")), economy.treasury, economy.tech_unlocked
	)


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
