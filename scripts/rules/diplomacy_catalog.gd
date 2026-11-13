class_name DiplomacyCatalog
extends RefCounted
## Diplomacy constants and display text (wiki: diplomacy § Configurable Values).
## Pure data: rules, the court panel and tests read one table, so thresholds and
## costs never drift between systems (REQ-P2-01, REQ-P3-03).

enum State { AT_PEACE, AT_WAR }

const STAGE_NONE: String = "none"
const STAGE_CONSULATE: String = "consulate"
const STAGE_EMBASSY: String = "embassy"
const STAGE_NAP: String = "nap"
const STAGE_JOIN_EMPIRE: String = "join_empire"

const STAGES: Array[String] = [
	STAGE_NONE,
	STAGE_CONSULATE,
	STAGE_EMBASSY,
	STAGE_NAP,
	STAGE_JOIN_EMPIRE,
]
const STAGE_LABELS: Dictionary = {
	STAGE_NONE: "No overture",
	STAGE_CONSULATE: "Trade Consulate",
	STAGE_EMBASSY: "Embassy",
	STAGE_NAP: "Non-Aggression Pact",
	STAGE_JOIN_EMPIRE: "Join Empire",
}

## Costs in pounds (wiki: diplomacy § Configurable Values).
const CONSULATE_COST: int = 500
const EMBASSY_COST: int = 1000
const JOIN_EMPIRE_BASE_COST: int = 5000
const JOIN_EMPIRE_PER_PROVINCE: int = 2000

## Grant Aid is a positive multiple of £1,000; the relation modifier is fixed
## and does not scale with the amount (wiki: diplomacy § GP–Minor Rules).
const GRANT_AID_STEP: int = 1000
const GRANT_AID_RELATION: float = 5.0

## Percentage subsidies: 5–20 in steps of 5, no treasury charge (R3).
const SUBSIDY_MIN: int = 5
const SUBSIDY_MAX: int = 20
const SUBSIDY_STEP: int = 5
const SUBSIDY_OPTIONS: Array[int] = [5, 10, 15, 20]

## Favoured Trading Partner (GP–GP): the target accepts at this standing
## (wiki: world-market § FTP). Each pact shifts our world-market terms 5%.
const FTP_MIN_SCORE: float = 65.0
const FTP_TERMS: float = 0.05

## A colonial boycott worsens the boycotted crown's market terms by 10%
## (wiki: diplomacy § GP–Tribe — Boycott; terms model: docs/diplomacy.md).
const BOYCOTT_TERMS: float = 0.10

## Price multipliers stay inside these rails so stacked pacts can never hand a
## crown free goods or an absurd windfall.
const TERMS_BUY_MIN: float = 0.70
const TERMS_BUY_MAX: float = 1.50
const TERMS_SELL_MIN: float = 0.50
const TERMS_SELL_MAX: float = 1.30

const INITIAL_SCORE: float = 50.0
const EQUILIBRIUM: float = 50.0
const RELATION_DECAY: float = 4.0
const ALLIANCE_MIN_SCORE: float = 51.0
const NAP_MIN_SCORE: float = 26.0
const PEACE_MIN_SCORE: float = 26.0
const JOIN_EMPIRE_MIN_SCORE: float = 51.0
const ALLY_DEFENCE_MIN_SCORE: float = 50.0
const ALLIANCE_CLAMP: float = 76.0
const BREAK_ALLY_PENALTY: float = 50.0
const BREAK_CASCADE_PENALTY: float = 10.0
const PROTEST_PENALTY: float = 10.0
## Protest against an aggressor holding Propaganda (wiki: tech-tree-diplomacy-civilian).
const PROTEST_PENALTY_PROPAGANDA: float = 5.0
const SPY_DEATH_PENALTY: float = 8.0

const METER_LABELS: Array[String] = [
	"Hostile",
	"Antagonistic",
	"Distrustful",
	"Unfriendly",
	"Wary",
	"Neutral",
	"Cordial",
	"Amicable",
	"Friendly",
	"Devoted",
]

## Ten-step ladder bands are half-open [low, high), with 100 in the top step.
const METER_BANDS: Array[Vector2] = [
	Vector2(0, 10),
	Vector2(10, 20),
	Vector2(20, 30),
	Vector2(30, 40),
	Vector2(40, 50),
	Vector2(50, 60),
	Vector2(60, 70),
	Vector2(70, 80),
	Vector2(80, 90),
	Vector2(90, 100),
]


static func stage_label(stage: String) -> String:
	return String(STAGE_LABELS.get(stage, "No overture"))


## The pact's published rate, in the words the court that must answer it reads:
## a favoured pact clears the crown's lots at 95% of the price and sells at
## 105% (wiki: world-market § FTP — the pact publishes those terms; DR-20261110-10).
static func ftp_terms_text() -> String:
	return "imports at %d%%, exports at %d%%" % [
		roundi((1.0 - FTP_TERMS) * 100.0),
		roundi((1.0 + FTP_TERMS) * 100.0),
	]


## Next link in the overture chain, or "" when Join Empire is already held.
static func next_stage(stage: String) -> String:
	match stage:
		STAGE_NONE:
			return STAGE_CONSULATE
		STAGE_CONSULATE:
			return STAGE_EMBASSY
		STAGE_EMBASSY:
			return STAGE_NAP
		STAGE_NAP:
			return STAGE_JOIN_EMPIRE
		_:
			return ""


static func knows_stage(stage: String) -> bool:
	return STAGES.has(stage)


## Stage costs. Join Empire scales with the target's province count.
static func stage_cost(stage: String, provinces: int = 0) -> int:
	match stage:
		STAGE_CONSULATE:
			return CONSULATE_COST
		STAGE_EMBASSY:
			return EMBASSY_COST
		STAGE_JOIN_EMPIRE:
			return JOIN_EMPIRE_BASE_COST + JOIN_EMPIRE_PER_PROVINCE * maxi(provinces, 0)
		_:
			return 0


static func relation_level(score: float) -> String:
	if score <= 25.0:
		return "Hostile"
	if score <= 50.0:
		return "Neutral"
	if score <= 75.0:
		return "Friendly"
	return "Allied"


## 1–10; boundaries go to the higher step and 100 stays in step 10.
static func meter_step(score: float) -> int:
	var value: float = clampf(score, 0.0, 100.0)
	if value >= 100.0:
		return 10
	for index in METER_BANDS.size():
		var band: Vector2 = METER_BANDS[index]
		if value >= band.x and value < band.y:
			return index + 1
	return 1


static func meter_label(score: float) -> String:
	return METER_LABELS[meter_step(score) - 1]


static func is_valid_aid(amount: int) -> bool:
	return amount >= GRANT_AID_STEP and amount % GRANT_AID_STEP == 0


static func is_valid_subsidy(percent: int) -> bool:
	return (
		percent >= SUBSIDY_MIN
		and percent <= SUBSIDY_MAX
		and (percent - SUBSIDY_MIN) % SUBSIDY_STEP == 0
	)


## Tech gate for an overture, or "" when the stage is allowed. GP→GP embassies
## are exempt; Empire Building gates absorbing a Great Power only
## (wiki: tech-tree-diplomacy-civilian).
static func tech_gate(stage: String, target_type: int, tech: Dictionary) -> String:
	if (
		stage == STAGE_EMBASSY
		and target_type != FactionCatalog.Type.GREAT_POWER
		and not tech.has("diplomatic_expertise")
	):
		return "Diplomatic Expertise is required for an embassy."
	if (
		stage == STAGE_JOIN_EMPIRE
		and target_type == FactionCatalog.Type.GREAT_POWER
		and not tech.has("empire_building")
	):
		return "Empire Building is required to absorb a Great Power."
	return ""


static func state_label(at_war: bool) -> String:
	return "At War" if at_war else "At Peace"


static func thousands(value: int) -> String:
	var text: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


static func money(value: int) -> String:
	return "£%s" % thousands(value)
