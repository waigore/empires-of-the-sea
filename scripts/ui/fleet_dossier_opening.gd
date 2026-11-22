class_name FleetDossierOpening
extends RefCounted
## Everything one opening of the fleet dossier reads (REQ-P3-02). The map
## helpers name each field, so a longer dossier adds a field instead of
## shifting every argument under HudPanels and FleetPanel.
##
## `fleet` null with a `slip` province is the capital yard before any squadron
## is afloat: the first launch founds the home fleet (wiki: ships-and-naval
## § Ship muster and the breaker's yard).

var fleet: FleetState = null
var is_player: bool = false
## The move note under the status row; empty when the squadron stays put.
var passage: String = ""
## Hulls the court's yard may lay; empty for a rival's dossier.
var yard_rows: Array[Dictionary] = []
## The slip province when no home fleet is afloat; -1 for a squadron dossier.
var slip: int = -1
## Owned coasts the carried army could land on.
var land_rows: Array[Dictionary] = []
var carried: int = 0
## Beachhead rows, their note and the hint under them.
var beach_rows: Array[Dictionary] = []
var beach_note: String = ""
## Colonists aboard: `{count, ...}` as MapPlayCivilianVoyage reads them.
var crew: Dictionary = {}
## The muster the dossier is allowed to show: `NavalStrength.fogged()` for a
## rival the crown has sighted but not read (wiki: ships-and-naval).
var strength: Dictionary = {}
## The home-fleet join on offer: `{ok, home, holds_text, note}`.
var merge: Dictionary = {}
var beach_hint: String = ""
## Every other squadron in this station, for the combine drawer.
var roster: Array[FleetState] = []
## The hull the court means to lay in the drawer it picks from.
var pick: String = ""
## The hostile coast the court's own expedition would mark this turn, for the
## mission rows to lead with the counsel's mark; -1 when the reading names no
## coast (a naval sail, or an expedition step that marks none). The id travels
## beside the sentence, so the block never parses words to find a row
## (DR-20261122-20).
var court_coast: int = -1
## The hull the court's own yard means to lay in the slip it launches from. The
## pick travels, not the sentence it words, so the slip marks its rows off the
## same reading (DR-20261122-12).
var yard_pick: Dictionary = {}


## A squadron's dossier at its plainest: the caller adds the blocks it has.
static func of(p_fleet: FleetState, p_is_player: bool) -> FleetDossierOpening:
	var opening := FleetDossierOpening.new()
	opening.fleet = p_fleet
	opening.is_player = p_is_player
	return opening
