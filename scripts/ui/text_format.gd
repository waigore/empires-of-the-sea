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
