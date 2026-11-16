class_name HudLedgerDoors
extends RefCounted
## The crown's whole-empire sheets — the people, the muster roll, its army, the
## realm's provinces, the crown's eyes, its commanders, its towns, walls,
## hospitals and navy. Each rides its own layer above the pause menu, binds the
## one session it reads and sets itself aside when a phone's back gesture lands.
##
## Those three readings are written once here, so a new sheet is one entry in
## `sheets` rather than another copy of the same layer, the same bind and the
## same back branch in three files (REQ-P3-01, REQ-P3-02, REQ-P5-07).


## Mounts `sheet` on its own named layer. The caller keeps the typed handle:
## GameHud's fields are the public doors and each sheet's own signal opens it.
static func mount(hud: GameHud, layer_name: String, sheet: SheetFrame) -> void:
	ModalShell.mount_layer(hud, layer_name).add_child(sheet)


## The sheets in the order the back gesture walks them: the roster, the muster
## roll and the realm's raise sheets, then the province, eyes, command and navy
## siblings. Nulls are dropped, so a HUD built without the chrome still reads
## cleanly.
static func sheets(hud: GameHud) -> Array[SheetFrame]:
	var found: Array[SheetFrame] = []
	if hud == null:
		return found
	for sheet: SheetFrame in [
		hud.civilian_roster,
		hud.muster_roll,
		hud.army_ledger,
		hud.towns_ledger,
		hud.walls_ledger,
		hud.hospitals_ledger,
		hud.province_ledger,
		hud.spy_ledger,
		hud.colonies_ledger,
		hud.command_ledger,
		hud.navy_ledger,
	]:
		if sheet != null:
			found.append(sheet)
	return found


## Binds every sheet to the session the screen is playing, once the region is
## painted and the economy exists (MapPlaySetup.build_hud).
static func bind_all(hud: GameHud, play: PlaySession) -> void:
	for sheet: SheetFrame in sheets(hud):
		sheet.bind(play)


## A phone's back press closes the newest ledger a door opened. Returns true
## when a sheet took the press; false leaves the press to the map's dossiers.
static func dismiss_open(hud: GameHud) -> bool:
	for sheet: SheetFrame in sheets(hud):
		if sheet.is_open():
			sheet.close()
			return true
	return false
