class_name TextFormat
extends RefCounted
## Shared text helpers for the ledger panels: whole-number money formatting.
## The grouping itself is the rules' own reading ([MoneyText]), so a panel, a
## catalog and a ledger row cannot group or sign the same sum two ways
## (REQ-P3-01).


## "1234567" -> "1,234,567"; keeps a leading minus for debts.
static func thousands(value: int) -> String:
	return MoneyText.thousands(value)


## Signed per-turn movement for the treasury plaque. Keeps the chip a fixed
## width: five figures collapse to "12.4k" instead of pushing the bar.
static func delta(value: int) -> String:
	var size: int = absi(value)
	var text: String = thousands(size)
	if size >= 10000:
		text = "%d.%dk" % [size / 1000, (size % 1000) / 100]
	return ("+" if value >= 0 else "-") + text
