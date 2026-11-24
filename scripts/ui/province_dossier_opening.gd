class_name ProvinceDossierOpening
extends RefCounted
## Everything one opening of the province dossier reads (REQ-P3-02): the live
## tables the boot seats it with — the chart, its works, the crews on it, the
## crown's fog, its capital and studies, and the purse and blockades the town
## and estate orders price against. The seat is named field by field, like the
## fleet, civilian and army openings, so a longer dossier adds a field instead
## of shifting every argument under MapPlaySetup, ProvincePanel and the suites.
##
## This is data, not a reading: the rows themselves come from the rules and the
## map helpers (REQ-P3-03). A sheet seated with no opening reads the same
## defaults a bare panel always did — no purse, no blockades, no crown.

## The chart on show; null for a panel no boot has seated.
var model: MapModel = null
## The chart's improvements: what each estate already carries.
var works: LandWorks = null
## The crews standing on the chart, for the survey rows.
var units: Array[CivilianState] = []
## The crown's own fog: what a survey row may name.
var visibility: VisibilityModel = null
## The crown's capital tile, so a road plan prices the link it would make.
var capital_tile: Vector2i = CivilianState.NO_TILE
## The court reading the sheet — the crown's own, or another when a rival's
## ground is inspected; -1 when no court is seated.
var faction: int = -1
## The crown's studies as caps and as the unlocked set: the town, wall, ward and
## hire rows gate on them.
var tech_caps: Dictionary = {}
var tech_unlocked: Dictionary = {}
## The crown's live purse, or null when the caller keeps no stores: the town
## order reads one money gate with the order itself (REQ-P2-03).
var stockpile: Variant = null
## The crown's sealed coasts: a blockaded harbour's estates read cut here exactly
## as the Extraction phase cuts them (wiki: capital-and-connectivity § Blockade).
var blockade: Blockades = null


## The three tables every dossier paint needs: the chart, its works and the
## crews on it. A caller adds the rest by name, so no seat is built by position.
static func of(
	p_model: MapModel, p_works: LandWorks, p_units: Array[CivilianState]
) -> ProvinceDossierOpening:
	var opening := ProvinceDossierOpening.new()
	opening.model = p_model
	opening.works = p_works
	opening.units = p_units
	return opening
