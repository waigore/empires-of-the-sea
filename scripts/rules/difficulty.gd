class_name Difficulty
extends RefCounted
## New-game difficulty layer (wiki: ruleset-config § Layers; combat § Modifiers).
## Fixed at creation. It scales the rival courts' opening stores and their
## strength in the field and at sea when they meet the human crown; it never
## changes an AI's decision algorithm (wiki: ai-architecture, ai-personalities).
##
## Normal is the published default and is byte-identical to the previous game:
## symmetric courts, published combat maths. The other three levels are this
## product's data-shaped choice, recorded in DR-20261110-12.

const DEFAULT: String = "normal"

## Ordered so the setup screen can walk them from easiest to hardest.
const IDS: Array[String] = ["introductory", "normal", "hard", "impossible"]

const LABELS: Dictionary = {
	"introductory": "Introductory",
	"normal": "Normal",
	"hard": "Hard",
	"impossible": "Impossible",
}

## Rival courts' opening purse and stockpile, percent of the published row
## (wiki: ruleset-config § Starting stockpiles; PlayerEconomy.START_*).
const AI_START_PERCENT: Dictionary = {
	"introductory": 60,
	"normal": 100,
	"hard": 140,
	"impossible": 180,
}

## Rival land and naval strength against the human crown, percent of the
## published maths (wiki: combat § Modifiers, ships-and-naval § Naval Combat
## Resolution — difficulty scales attacker and defender on both surfaces).
const AI_COMBAT_PERCENT: Dictionary = {
	"introductory": 85,
	"normal": 100,
	"hard": 115,
	"impossible": 130,
}


## Unknown or empty ids fall back to Normal, so a legacy save plays as published.
static func normalize(id: String) -> String:
	var key: String = id.strip_edges().to_lower()
	return key if IDS.has(key) else DEFAULT


static func index_of(id: String) -> int:
	return IDS.find(normalize(id))


static func label(id: String) -> String:
	return String(LABELS.get(normalize(id), LABELS[DEFAULT]))


static func ai_start_percent(id: String) -> int:
	return int(AI_START_PERCENT.get(normalize(id), AI_START_PERCENT[DEFAULT]))


static func ai_combat_percent(id: String) -> int:
	return int(AI_COMBAT_PERCENT.get(normalize(id), AI_COMBAT_PERCENT[DEFAULT]))


## Plain-language effect for setup and the pause page: one line, no jargon.
static func hint(id: String) -> String:
	match normalize(id):
		"introductory":
			return "Rivals open with 60% of their stores and fight at 85% strength."
		"hard":
			return "Rivals open with 140% of their stores and fight at 115% strength."
		"impossible":
			return "Rivals open with 180% of their stores and fight at 130% strength."
	return "The published rules: every court opens and fights alike."


## Rounds a published quantity onto the difficulty's percentage.
static func scaled(value: int, percent: int) -> int:
	return maxi(0, roundi(float(value) * float(percent) / 100.0))


## Scales a rival's freshly founded ledger. The human crown never passes through
## here: its start stays the published row (wiki: ruleset-config § Starting
## stockpile symmetry). Peasants, techs and assignments are untouched.
static func scale_start(economy: PlayerEconomy, id: String) -> void:
	if economy == null:
		return
	var percent: int = ai_start_percent(id)
	if percent == 100:
		return
	economy.treasury = scaled(economy.treasury, percent)
	for commodity: Variant in economy.stockpile.keys():
		economy.stockpile[commodity] = scaled(int(economy.stockpile[commodity]), percent)


## owner id -> strength multiplier, read by the field and the sea alike. Every
## rival court is scaled and the human crown is not; two rivals share one
## multiplier, so their mutual battles keep the published ratio, and the full-AI
## observer (no human) is unchanged.
static func combat_multipliers(human: int, id: String, factions: Array[int]) -> Dictionary:
	var result: Dictionary = {}
	var factor: float = float(ai_combat_percent(id)) / 100.0
	for faction: int in factions:
		if faction != human:
			result[faction] = factor
	return result
