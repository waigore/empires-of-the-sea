class_name WallLedgerRow
extends RaiseLedgerRow
## One wall in the crown's ledger: an open shore's dash, the wall that meets an
## attack today and the press that sends an Engineer (wiki: siege-mechanics
## § Fort Levels, § Wall Protection; DR-20261116-01). The dress, the shared chip
## states and the intent are [RaiseLedgerRow]'s; only the words are this sheet's
## (REQ-P3-02).


func _place_text() -> String:
	return "%s  ·  %s" % [
		String(data.get("line", "No fort")),
		String(data.get("region_label", "Uncharted")),
	]


func _raise_tooltip() -> String:
	return "Send the nearest idle Engineer to wall %s" % String(data.get("name", "Province"))


func _chip_reading() -> Dictionary:
	match String(data.get("state", "")):
		WallLedger.STATE_NO_ENGINEER:
			return {"text": "NO ENGINEER", "color": Palette.SURVEY_VACANT}
		WallLedger.STATE_RAISED:
			return {"text": "WALLED", "color": Palette.GOLD_DIM}
	return super._chip_reading()
