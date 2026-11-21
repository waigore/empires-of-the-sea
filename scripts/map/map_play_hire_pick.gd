class_name MapPlayHirePick
extends RefCounted
## The crew the court's own hire order takes at its capital next, and the gate
## that holds it back (wiki: civilian-units § Training, civilian-build-planner
## § Staff; DR-20261121-06).
##
## The reading is not a second opinion: it is the `training` the court's own
## civilian pass books for its home region — `AiCivilianHire.training_order`
## over the region's own asks, the court's archetype taste and its purse, asked
## through `MapPlayCivilianAi.plan_all`, the call the economy turn makes — and,
## when the pass takes no hire at all, the next name in the published queue
## (`next_crew`) with the study or the purse that stops it (REQ-P2-03).
##
## A reading only: nothing here queues, pays or musters a crew, and the crown
## still presses her own Train (REQ-P3-03, REQ-P5-06).

## The hire order takes this crew next, as the published queue leads it.
const KIND_TAKE: String = "take"
## The hire order takes the crew the court's own archetype keeps beyond the asks.
const KIND_TASTE: String = "taste"
## The hire order names this crew next and cannot take it: a study or the purse.
const KIND_WAIT: String = "wait"
## The footing shuts the hire: a war keeps the expansion crews, the bank the rest.
const KIND_GATE: String = "gate"
## Every crew the region asks for already stands.
const KIND_FULL: String = "full"

## Every crew the region asks for already stands: the hire order is one line the
## court reads before it presses a craft its staffs already fill.
const FULL_LINE: String = "Every crew this region asks for already stands."
## The bank's refusal, in the crown's words: a court short of the bar keeps its
## chest and hires only the crews its provision arms (issue #1059).
const BANK_LINE: String = "The bank holds the purse: your hire order takes no new crew."


## The rail's line for the capital, or "" when there is none to print: no
## planner, no ledger, no capital, or a capital whose staff the court cannot hire.
static func line(play: PlaySession) -> String:
	return String(pick(play).get("line", ""))


## The court's own hire pick as its capital rail reads it: `{kind, crew, gate,
## price, line}`. Empty when the session runs no planner for the crown, the
## campaign is decided, the crown keeps no ledger, or the home region seats no
## capital to hire at.
##
## The plan is priced on the crown's standing purse with no reserve held back (a
## pick the crown could not press today is no advice at all), but it is read on
## the same footing the pass itself reads: the war posture and the court's own
## conquest bank, so the rail cannot name a crew the published hire order would
## refuse (wiki: civilian-units § Training; DR-20261121-06, issue #995).
static func pick(play: PlaySession) -> Dictionary:
	if not MapPlayPickProse.crown_ready(play):
		return {}
	if play.world == null or play.civilian_layer == null:
		return {}
	var faction: int = play.player_faction
	var economy: PlayerEconomy = play.ledger_for(faction)
	if economy == null:
		return {}
	var kind: String = AiControl.court_kind(play, faction)
	var config: Variant = AiBind.config(
		kind, faction, play.map_seed, play.ensure_ai().profiles
	)
	if not (config is AiConfig):
		return {}
	var home: int = FactionCatalog.region_of(faction)
	for entry: Dictionary in MapPlayCivilianAi.plan_all(
		play, faction, economy, config,
		MapPlayEconomyAi._overseas(play, faction, economy), economy.stockpile, 0, -1,
		banks(play, faction, economy, config, kind)
	):
		if int(entry.get("region", -1)) != home:
			continue
		# A region without a seated capital hires nobody: the pass takes no order
		# there, and the rail says nothing rather than naming a crew the crown
		# could not engage (wiki: civilian-units § Training).
		var context: Dictionary = entry.get("context", {})
		if int(context.get("capital_province", -1)) < 0:
			return {}
		var plan: Dictionary = entry.get("plan", {})
		return of(
			plan.get("training", {}), String(plan.get("next_crew", "")), economy
		)
	return {}


## Whether the court is banking for its army this turn: the win-bar pressure,
## the host, the hull's chest and the purses, read through the same income plan
## `MapPlayEconomyCourt` stages the pass with, so the rail and the hire order
## answer the bank gate the same way (issue #995; wiki: civilian-units
## § Training). A baseline court keeps its published doctrine and never banks.
static func banks(
	play: PlaySession, faction: int, economy: PlayerEconomy, config: Variant,
	kind: String
) -> bool:
	if play == null or play.world == null or play.ai == null or economy == null:
		return false
	if kind == AiControl.KIND_BASELINE:
		return false
	var pressure: Dictionary = AiVictoryPressure.read(
		play.world, faction, play.human_faction_id(), play.difficulty, config
	)
	var income: Dictionary = AiBindEconomy.income_plan(
		kind, config, economy, MapPlayCourt.at_war(play, faction),
		MapPlayCourt.regiments(play, faction), MapPlayCourt.navy_chest(play, faction),
		MapPlayCourt.warships(play, faction),
		AiDeferral.stall_for(play.ai.deferrals, faction, "muster.line"),
		int(pressure.get("need", 0)) > 0
	)
	return AiIncome.banking(config, play.ai, income)


## The pick, worded off data alone: the pass's own `training` row, the queue's
## `next_crew`, and the crown's purse and studies for the gates the pass leaves
## to the order. Pure — a sheet and its suite drive it without a session.
static func of(
	training: Dictionary, next_crew: String, economy: PlayerEconomy
) -> Dictionary:
	var treasury: int = 0
	var paper: int = 0
	var tech: Dictionary = {}
	if economy != null:
		treasury = economy.treasury
		paper = economy.quantity("paper")
		tech = economy.tech_unlocked
	if bool(training.get("ok", false)):
		var crew: String = String(training.get("type_id", ""))
		if crew.is_empty():
			return {}
		var taste: bool = bool(training.get("taste", false))
		var read: Dictionary = _worded(
			KIND_TASTE if taste else KIND_TAKE, crew, "",
			take_line(crew, taste)
		)
		read["taste"] = taste
		return read
	if not training.is_empty():
		var gate: String = String(training.get("reason", ""))
		if gate != AiCivilianHire.REASON_CREWS and gate != AiCivilianHire.REASON_BANK:
			return {}
		return _worded(KIND_GATE, next_crew, gate, gate_line(next_crew, gate))
	if next_crew.is_empty():
		return _worded(KIND_FULL, "", "", FULL_LINE)
	var study: String = CivilianHire.locked_tech(next_crew, tech)
	if not study.is_empty():
		return _worded(KIND_WAIT, next_crew, study, wait_line(next_crew, study))
	if not CivilianCatalog.can_afford(next_crew, treasury, paper):
		return _worded(KIND_WAIT, next_crew, "", short_line(next_crew))
	# The pass names a crew it could take and takes none: no gate the sheet can
	# read, so it prints the queue's own name rather than inventing a refusal.
	return _worded(KIND_TAKE, next_crew, "", take_line(next_crew, false))


## "Your hire order takes a Builder next — 1,000 cash + 2 paper." A crew the
## court's own archetype keeps says so, because the hire is in character rather
## than the region's ask (wiki: civilian-build-planner § Archetype weights).
static func take_line(crew: String, taste: bool) -> String:
	if crew.is_empty() or not CivilianCatalog.known(crew):
		return ""
	var head: String = (
		"Your court's taste takes %s next" % with_article(crew)
		if taste
		else "Your hire order takes %s next" % with_article(crew)
	)
	return "%s — %s." % [head, CivilianCatalog.training_cost_text(crew)]


## The footing's own refusal, in plain words: a war shuts the expansion crews,
## the bank every other crew (wiki: civilian-units § Training).
static func gate_line(crew: String, gate: String) -> String:
	if gate == AiCivilianHire.REASON_BANK:
		return BANK_LINE
	if gate == AiCivilianHire.REASON_CREWS:
		var named: String = (
			CivilianCatalog.display_name(crew) if CivilianCatalog.known(crew) else "crew"
		)
		return "At war your hire order takes no new %s — the front's own crews keep hiring." % named
	return ""


## A crew the queue names but the college has not opened: the study that holds
## the hire, in the same words the rail's craft rows grey out on.
static func wait_line(crew: String, study: String) -> String:
	if crew.is_empty() or study.is_empty() or not CivilianCatalog.known(crew):
		return ""
	return "Your hire order takes %s next, and waits on %s." % [
		with_article(crew), TechCatalog.display_name(study)
	]


## A crew the queue names and the purse cannot cover: the price it cannot pay,
## never a figure the crown does not hold (REQ-P5-06).
static func short_line(crew: String) -> String:
	if crew.is_empty() or not CivilianCatalog.known(crew):
		return ""
	return "Your hire order takes %s next, and the purse cannot cover %s." % [
		with_article(crew), CivilianCatalog.training_cost_text(crew)
	]


## The craft with its article: "a Builder", "an Explorer". Its own name carries
## the capital, so the sentence reads as prose rather than a label; a name the
## roster does not know prints nothing rather than the catalog's fallback craft.
static func with_article(crew: String) -> String:
	if crew.is_empty() or not CivilianCatalog.known(crew):
		return ""
	var name: String = CivilianCatalog.display_name(crew)
	if name.is_empty():
		return ""
	return "%s %s" % ["an" if _vowel(name) else "a", name]


static func _vowel(word: String) -> bool:
	if word.is_empty():
		return false
	return "aeiouAEIOU".contains(word.substr(0, 1))


static func _worded(kind: String, crew: String, gate: String, line: String) -> Dictionary:
	if line.is_empty():
		return {}
	return {
		"kind": kind,
		"crew": crew,
		"gate": gate,
		"price": CivilianCatalog.treasury_cost(crew) if CivilianCatalog.known(crew) else 0,
		"line": line,
	}
