class_name HospitalLedgerRow
extends RaiseLedgerRow
## One ward in the crown's ledger: the level medallion, the province it stands
## in, what it heals today, what the next one costs and waits on, and the press
## that files the Engineer's order (wiki: combat § Regiment condition;
## DR-20261116-02). The dress, the shared chip states and the intent are
## [RaiseLedgerRow]'s; only the words are this sheet's (REQ-P3-02).


func _place_text() -> String:
	return "%s  ·  %s" % [
		String(data.get("line", "No hospital")),
		String(data.get("region_label", "Uncharted")),
	]


func _raise_tooltip() -> String:
	return (
		"Send the nearest idle Engineer to raise the ward of %s"
		% String(data.get("name", "Province"))
	)


func _chip_reading() -> Dictionary:
	match String(data.get("state", "")):
		HospitalLedger.STATE_NO_ENGINEER:
			return {"text": "NO ENGINEER", "color": Palette.SURVEY_VACANT}
		HospitalLedger.STATE_RAISED:
			return {"text": "WARDED", "color": Palette.GOLD_DIM}
	return super._chip_reading()
