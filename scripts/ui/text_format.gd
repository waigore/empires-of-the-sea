class_name TextFormat
extends RefCounted
## Shared text helpers for the ledger panels: whole-number money formatting.
## Kept in one place so panels do not grow private copies (REQ-P3-01).


## "1234567" -> "1,234,567"; keeps a leading minus for debts.
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


## Signed per-turn movement for the treasury plaque. Keeps the chip a fixed
## width: five figures collapse to "12.4k" instead of pushing the bar.
static func delta(value: int) -> String:
	var size: int = absi(value)
	var text: String = thousands(size)
	if size >= 10000:
		text = "%d.%dk" % [size / 1000, (size % 1000) / 100]
	return ("+" if value >= 0 else "-") + text
