class_name TownLedgerRow
extends RaiseLedgerRow
## One town in the crown's ledger: a bare town's first numeral, the seat under
## the name and the press that sends a Builder (wiki: extraction-and-improvements
## § Town manufacturing bonus, civilian-units § Builder upgrade_town;
## DR-20261115-12). The dress, the shared chip states and the intent are
## [RaiseLedgerRow]'s; only the words are this sheet's (REQ-P3-02).


func _medallion_empty() -> String:
	return "I"


func _place_text() -> String:
	return "%s  ·  %s" % [
		String(data.get("region_label", "Uncharted")),
		"the seat" if bool(data.get("capital", false)) else "a province",
	]


func _raise_tooltip() -> String:
	return "Send the nearest idle Builder to raise %s" % String(data.get("name", "Province"))


func _chip_reading() -> Dictionary:
	match String(data.get("state", "")):
		TownLedger.STATE_NO_BUILDER:
			return {"text": "NO BUILDER", "color": Palette.SURVEY_VACANT}
		TownLedger.STATE_DEVELOPED:
			return {"text": "DEVELOPED", "color": Palette.GOLD_DIM}
	return super._chip_reading()
