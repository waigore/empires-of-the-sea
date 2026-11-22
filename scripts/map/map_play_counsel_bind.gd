class_name MapPlayCounselBind
extends RefCounted
## The court's own reading on every sheet the screen boots: each gold line is
## the pick its published pass would issue this phase, read on the sheet's own
## snapshot so the line reads down the page it answers and marks the rows it
## names (REQ-P3-01, REQ-P3-02, REQ-P5-06).
##
## MapPlaySetup binds these once, while the screen opens; the boot itself owns
## the economy and the chrome, and this module owns which court reading each
## sheet answers. A sheet that is absent (a HUD without the eyes, the people or
## the tree) is simply not bound — no caller invents a line for it.


## Binds every sheet the open screen carries. `play.improvements` and the
## province dossier are always there when the boot runs; the three optional
## sheets are named by the HUD and skipped when it does not mount them.
static func bind(play: PlaySession) -> void:
	if play == null or play.hud == null:
		return
	_bind_estates(play)
	_bind_province(play)
	_bind_spy(play)
	_bind_people(play)
	_bind_research(play)


## The estates ledger names the estates the court's own Builder pass would raise
## this phase, read on the ledger's own snapshot so the line reads down the page
## it answers, and marks those rows with the counsel's `▸` so the raise is found
## among a long page (wiki: extraction-and-improvements § Estates ledger;
## DR-20261121-10, DR-20261122-04).
static func _bind_estates(play: PlaySession) -> void:
	play.improvements.counsel_source = (
		func(data: Dictionary) -> Dictionary: return MapPlayEstatesPick.pick(play, data)
	)


## The province dossier names the orders the court would give on its ground: the
## work the civilian pass would put crews to here and the hosts the land pass
## would send here, read on the chart the sheet is showing (wiki: world-model
## § The crown's provinces; DR-20261121-19).
static func _bind_province(play: PlaySession) -> void:
	play.hud.panels.panel.counsel_source = (
		func(model: MapModel, province_id: int) -> String:
			return MapPlayProvinceCounsel.line(play, model, province_id)
	)


## THE CROWN'S EYES names the spies the court's own espionage pass would walk,
## screen or keep this turn, read on the sheet's own snapshot so the line reads
## down the network it answers (wiki: civilian-units § Spy; DR-20261121-11).
static func _bind_spy(play: PlaySession) -> void:
	var eyes: SpyLedgerPanel = play.hud.spy_ledger
	if eyes == null:
		return
	eyes.counsel_source = (
		func(data: Dictionary) -> String: return MapPlaySpyPick.line(play, data)
	)


## THE CROWN'S PEOPLE names the work the court's own civilian pass would put its
## crews to this turn and marks those crews `▸` in the roster, read on the
## roster's own snapshot so the line reads down the page it answers and one read
## paints both the line and its marks (wiki: civilian-units § Empire roster;
## DR-20261121-12, DR-20261122-06).
static func _bind_people(play: PlaySession) -> void:
	var people: CivilianRosterPanel = play.hud.civilian_roster
	if people == null:
		return
	people.counsel_source = (
		func(data: Dictionary) -> Dictionary: return MapPlayPeoplePick.pick(play, data)
	)


## THE TECH TREE names the study the court's own research policy would open — the
## college's own gold sentence — and marks that advance `▸` on the chart, so the
## crown sees where the court would go without scanning 113 nodes (wiki:
## tech-tree § Research Model; DR-20261121-20).
##
## THE CROWN'S NAVY is absent here on purpose: the naval panel reads its own pass
## in its own method, so a bound callable cannot outlive the session it reads and
## the squadrons the line names can wear its mark (wiki: ships-and-naval § The
## crown's navy; DR-20261121-13, DR-20261121-14, DR-20261122-05).
static func _bind_research(play: PlaySession) -> void:
	var tree: TechTreePanel = play.hud.tech_tree
	if tree == null:
		return
	tree.counsel_source = (
		func() -> Dictionary: return MapPlayResearchPick.pick(play)
	)
