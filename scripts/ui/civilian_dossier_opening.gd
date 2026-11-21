class_name CivilianDossierOpening
extends RefCounted
## Everything one opening of the civilian dossier reads (REQ-P3-02). The map
## helpers name each field, so a longer dossier adds a field instead of
## shifting every argument under HudPanels and CivilianPanel.

var unit: CivilianState = null
var works: LandWorks = null
var units: Array[CivilianState] = []
var stockpile: Dictionary = {}
var visibility: VisibilityModel = null
## Extraction caps and researched techs the work rows price with.
var tech_caps: Dictionary = {}
var tech_unlocked: Dictionary = {}
## The pick the court would take, plus the panel's viewing context.
var context: Dictionary = {}
## The court reading the sheet: a rival's sheet prices no orders.
var viewer: int = FactionCatalog.PLAYER_FACTION


## A crew's dossier at its plainest: the caller adds the session's readings.
static func of(p_unit: CivilianState) -> CivilianDossierOpening:
	var opening := CivilianDossierOpening.new()
	opening.unit = p_unit
	return opening
