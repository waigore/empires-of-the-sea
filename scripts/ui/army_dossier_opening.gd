class_name ArmyDossierOpening
extends RefCounted
## Everything one opening of the army dossier reads (REQ-P3-02). The map
## helpers name each field, so a longer dossier adds a field instead of
## shifting every argument under HudPanels and ArmyPanel.

var army: ArmyState = null
var is_player: bool = false
## Another standard in the province this one may fold into.
var can_merge: bool = false
## The commander line from the army layer; empty for a Minor Nation or Tribe.
var command: String = ""
## Drill-yard rows; empty for a rival's dossier.
var muster: Array[Dictionary] = []
## The boarding press: `{caption, ok}` for the squadron waiting in the army's port
## — ready with the deck it would take (`Embark aboard the fleet · 5 hulls, 2
## free`), or refused with the rules' own reason as the caption — and empty when
## no squadron waits there (wiki: ships-and-naval § Naval transport;
## DR-20261124-14).
var embark: Dictionary = {}
## The crown's standing Quick Battle plan (wiki: quick-battle).
var plan: String = "balanced"
## The field-hospital order: `{caption, ok}` or empty when none is offered.
var hospital: Dictionary = {}
## The march the court would order from this dossier (DR-20261121-03).
var pick: String = ""
## The crown's own ration coverage — the share of last turn's army bill the
## granary fed, which the next exchange reads as its morale (wiki: combat
## § Feeding modifiers; DR-20261124-02). `ArmyRationRead.NO_READING` for another
## court's standard: her larder is not the crown's to read, so the sheet prints
## no line.
var rations: float = ArmyRationRead.NO_READING
## The crown's own studies, for the land-battle price her next storm pays
## (wiki: tech-tree-military § Economy modifiers; DR-20261124-11). Empty for
## another court's standard: her studies are not the crown's to read, so the
## sheet prices no battle.
var attack_unlocked: Dictionary = {}
## The line the court's muster would raise (DR-20261121-03). The pick travels,
## not the sentence it words, so the yard marks its rows off the same reading
## (DR-20261122-12).
var muster_pick: Dictionary = {}


## A standard's dossier at its plainest: the caller adds the blocks it has.
static func of(p_army: ArmyState, p_is_player: bool) -> ArmyDossierOpening:
	var opening := ArmyDossierOpening.new()
	opening.army = p_army
	opening.is_player = p_is_player
	return opening
