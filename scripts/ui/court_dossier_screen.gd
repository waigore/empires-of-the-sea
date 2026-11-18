class_name CourtDossierScreen
extends SheetFrame
## The full court dossier sheet (wiki: ai-dossier § Logical sections;
## DR-20261110-25): a sheet over the HUD that hosts [CourtDossierBody]. The
## sheet chrome — header, safe-area fit, open/close — comes from SheetFrame, so
## the page itself stays one domain and the rules never touch a node
## (REQ-P3-01, REQ-P2-03).
##
## Built once with the court (DiplomacyHud) over its own canvas layer, so opening
## it costs a repaint. The sheet takes the state it is shown with, so it needs no
## session reference and the HUD bootstrap stays untouched (REQ-P3-02).

## The page, kept public for tests and for a caller that wants the body alone.
var _body: CourtDossierBody = null
## The court's arms in the sheet's head, re-dressed on every open.
var _arms: FactionCrest = null

## The head's crest size: the sheet's own, so the arms sit where the generic
## crest sat before them.
const CREST_PIXELS: float = 40.0


func _init() -> void:
	title_text = "THE DOSSIER"
	title_pixels = 26
	hint_pixels = 11
	hint_text = (
		"Bands are suspicion from what the court could see, not proof: "
		+ "'Confirmed' never names the agenda. Tap an agenda to read its timeline."
	)


## Renders and shows the reading for `faction_id`. The caller holds the state, so
## the sheet needs no session reference.
func show_for(
	state: DiplomacyState, world: WorldMap, viewer: int, faction_id: int
) -> void:
	if _body == null:
		return
	var report: Dictionary = IntelDossier.report(state, world, viewer, faction_id)
	_subtitle.text = _court_line(faction_id)
	if _arms != null:
		_arms.set_faction(faction_id)
	_body.show_report(report, state, world, viewer, faction_id)
	_fit()
	_reveal()


# --- sheet hooks -------------------------------------------------------------


func _build_crest() -> Control:
	# The head wears the arms of the court the sheet is open on; a sheet with no
	# court yet draws a bare gap of the same size (DR-20261118-30).
	_arms = FactionCrest.new(-1, CREST_PIXELS)
	return _arms


func _build_body(column: VBoxContainer) -> void:
	_body = CourtDossierBody.new()
	_append_scroll(column).add_child(_body)


static func _court_line(faction: int) -> String:
	return "%s  ·  %s  ·  %s" % [
		FactionCatalog.name_of(faction),
		FactionCatalog.type_label(FactionCatalog.type_of(faction)),
		FactionCatalog.region_label(FactionCatalog.region_of(faction)),
	]
