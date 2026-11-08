class_name ResearchFunding
extends RefCounted
## Funding presets for one research slot and the research-phase treasury floor
## (wiki: tech-tree § Research Model; tech-tree-labour-economy § money_lending,
## banking). Pure data shared by the research phase and the ledger.

const ORDER: Array[String] = ["none", "low", "medium", "high", "maximum"]
## Gold/Turn and RP/Turn per preset. Efficiency is the wiki's RP per gold.
const PRESETS: Dictionary = {
	"none": {"label": "None", "gold": 0, "rp": 0},
	"low": {"label": "Low", "gold": 50, "rp": 100},
	"medium": {"label": "Medium", "gold": 150, "rp": 300},
	"high": {"label": "High", "gold": 400, "rp": 800},
	"maximum": {"label": "Maximum", "gold": 1000, "rp": 2500},
}
const DEFAULT: String = "medium"

const MONEY_LENDING: String = "money_lending"
const BANKING: String = "banking"
## Without Money Lending the treasury may not go below 0 in the research phase.
const DEBT_FLOOR: int = -500
const BANK_DEBT_FLOOR: int = -1000


static func known(funding: String) -> bool:
	return PRESETS.has(funding)


static func label(funding: String) -> String:
	return String((PRESETS.get(funding, PRESETS["none"]) as Dictionary)["label"])


static func gold(funding: String) -> int:
	return int((PRESETS.get(funding, PRESETS["none"]) as Dictionary)["gold"])


static func rp(funding: String) -> int:
	return int((PRESETS.get(funding, PRESETS["none"]) as Dictionary)["rp"])


## Next preset in the cycle; the ledger's funding button walks this order.
static func next(funding: String) -> String:
	var index: int = ORDER.find(funding)
	return ORDER[(index + 1) % ORDER.size()]


## Lowest treasury the research phase may spend down to (wiki: money_lending
## and banking extend it; banking alone changes nothing).
static func floor_for(unlocked: Dictionary) -> int:
	if bool(unlocked.get(MONEY_LENDING, false)) and bool(unlocked.get(BANKING, false)):
		return BANK_DEBT_FLOOR
	if bool(unlocked.get(MONEY_LENDING, false)):
		return DEBT_FLOOR
	return 0
