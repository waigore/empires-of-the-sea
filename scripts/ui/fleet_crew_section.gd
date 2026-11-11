class_name FleetCrewSection
extends FleetDossierSection
## The fleet dossier's passenger block (DR-20261109-17): who is aboard, idle
## civilians to take on, coasts to put them ashore, and the home squadron's
## sortie zones. Emits intents; CivilianVoyage and FleetSortie own the rules.


func _ready() -> void:
	_setup("PASSENGERS")


## Empty data hides the block; every row is one tap on a phone.
func set_data(crew: Dictionary) -> void:
	var embark: Array = crew.get("embark", [])
	var land: Array = crew.get("land", [])
	var sortie: Array = crew.get("sortie", [])
	var count: int = int(crew.get("count", 0))
	visible = count > 0 or not embark.is_empty() or not land.is_empty() \
		or not sortie.is_empty()
	_begin(String(crew.get("note", "")))
	for raw: Variant in land:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Put ashore at %s" % String(row.get("name", "the coast")),
			"crew:land:%d" % int(row.get("province", -1))
		)
	for raw: Variant in embark:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Take %s aboard" % String(row.get("name", "a civilian")),
			"crew:embark:%d" % int(row.get("id", -1))
		)
	for raw: Variant in sortie:
		var row: Dictionary = raw as Dictionary
		_add_row(
			"Put to sea into %s" % String(row.get("name", "the roads")),
			"sortie:%d" % int(row.get("zone", -1))
		)
