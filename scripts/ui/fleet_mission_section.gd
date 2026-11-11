class_name FleetMissionSection
extends FleetDossierSection
## The fleet dossier's mission block: the current station note and one button
## per station or hostile coast the squadron could take (wiki: ships-and-naval
## § Missions and Movement). Emits intents; the rules modules own validation.


func _ready() -> void:
	_setup("MISSIONS")


## Empty data hides the block: a fresh squadron has no landing duty yet.
func set_data(note: String, rows: Array[Dictionary]) -> void:
	visible = not note.is_empty() or not rows.is_empty()
	_begin(note)
	for row: Dictionary in rows:
		var province: int = int(row.get("province", -1))
		_add_row(
			String(row.get("label", "Mark %s" % String(row.get("name", "the coast")))),
			String(row.get("action", "beachhead:%d" % province))
		)
