class_name HudLedgerDoors
extends RefCounted
## The crown's whole-empire sheets — the people, the muster roll, its army, the
## realm's provinces, the crown's eyes, its commanders, its towns, walls,
## hospitals and navy — as one registry (REQ-P3-01, REQ-P3-02, REQ-P5-07).
##
## Every door into them names its sheet by one key (`CIVILIANS`, `NAVY`, …), so a
## cartouche seal, a stat chip, a dossier line and a sheet's own door all press
## the same signal and no caller needs the sheet's class or field. The table is
## the single list: `build_all` mounts each sheet on its named layer and binds its
## doors, `sheets` walks them for the session bind, and the back gesture closes
## them in the order the table prints — a new sheet is one row here plus one field
## on GameHud.

## The door keys: one word per whole-empire sheet.
const CIVILIANS: String = "civilians"
const MUSTER: String = "muster"
const PROVINCES: String = "provinces"
const EYES: String = "eyes"
const COLONIES: String = "colonies"
const COMMAND: String = "command"
const TOWNS: String = "towns"
const WALLS: String = "walls"
const HOSPITALS: String = "hospitals"
const NAVY: String = "navy"
const ARMY: String = "army"

## One row per sheet: the door key, the GameHud field that keeps the typed
## handle, the layer it rides and therefore its place in the back order.
const SHEETS: Array[Dictionary] = [
	{"key": CIVILIANS, "field": "civilian_roster", "layer": "CivilianRosterLayer"},
	{"key": MUSTER, "field": "muster_roll", "layer": "MusterRollLayer"},
	{"key": ARMY, "field": "army_ledger", "layer": "ArmyLedgerLayer"},
	{"key": TOWNS, "field": "towns_ledger", "layer": "TownLedgerLayer"},
	{"key": WALLS, "field": "walls_ledger", "layer": "WallLedgerLayer"},
	{"key": HOSPITALS, "field": "hospitals_ledger", "layer": "HospitalLedgerLayer"},
	{"key": PROVINCES, "field": "province_ledger", "layer": "ProvinceLedgerLayer"},
	{"key": EYES, "field": "spy_ledger", "layer": "SpyLedgerLayer"},
	{"key": COLONIES, "field": "colonies_ledger", "layer": "ColonyLedgerLayer"},
	{"key": COMMAND, "field": "command_ledger", "layer": "CommandLedgerLayer"},
	{"key": NAVY, "field": "navy_ledger", "layer": "NavalLedgerLayer"},
]


## The registry row one door key names, empty when the key names no sheet.
static func spec_for(key: String) -> Dictionary:
	for spec: Dictionary in SHEETS:
		if String(spec["key"]) == key:
			return spec
	return {}


## The sheet a door key opens, null when the key names nothing or the HUD was
## built without that sheet.
static func sheet_for(hud: GameHud, key: String) -> SheetFrame:
	if hud == null:
		return null
	var spec: Dictionary = spec_for(key)
	if spec.is_empty():
		return null
	return hud.get(String(spec["field"])) as SheetFrame


## A door press: the HUD's one keyed door signal ends here, so a seal, a chip, a
## dossier line and a sheet's own door all take the same path.
static func open(hud: GameHud, key: String) -> void:
	var sheet: SheetFrame = sheet_for(hud, key)
	if sheet != null:
		sheet.toggle()


## Mounts every whole-empire sheet and binds its own doors to the HUD's keyed
## signal, so a sheet added to the table needs no second wiring place. The HUD's
## keyed press opens the sheet that key names.
static func build_all(hud: GameHud) -> void:
	hud.ledger_door_pressed.connect(func(key: String) -> void: open(hud, key))
	hud.civilian_roster = _mounted(
		hud, CIVILIANS, CivilianRosterPanel.new()
	) as CivilianRosterPanel
	hud.muster_roll = _mounted(hud, MUSTER, ForceLedgerPanel.new()) as ForceLedgerPanel
	hud.army_ledger = _mounted(hud, ARMY, ArmyLedgerPanel.new()) as ArmyLedgerPanel
	hud.towns_ledger = _mounted(hud, TOWNS, TownLedgerPanel.new()) as TownLedgerPanel
	hud.walls_ledger = _mounted(hud, WALLS, WallLedgerPanel.new()) as WallLedgerPanel
	hud.hospitals_ledger = _mounted(
		hud, HOSPITALS, HospitalLedgerPanel.new()
	) as HospitalLedgerPanel
	hud.province_ledger = _mounted(
		hud, PROVINCES, ProvinceLedgerPanel.new()
	) as ProvinceLedgerPanel
	hud.spy_ledger = _mounted(hud, EYES, SpyLedgerPanel.new()) as SpyLedgerPanel
	hud.colonies_ledger = _mounted(
		hud, COLONIES, ColonyLedgerPanel.new()
	) as ColonyLedgerPanel
	hud.command_ledger = _mounted(
		hud, COMMAND, CommandLedgerPanel.new()
	) as CommandLedgerPanel
	hud.navy_ledger = _mounted(hud, NAVY, NavalLedgerPanel.new()) as NavalLedgerPanel


## Mounts one sheet on the layer its registry row names and binds its own doors
## to the HUD's keyed signal.
static func _mounted(hud: GameHud, key: String, sheet: SheetFrame) -> SheetFrame:
	var spec: Dictionary = spec_for(key)
	if spec.is_empty():
		return sheet
	ModalShell.mount_layer(hud, String(spec["layer"])).add_child(sheet)
	sheet.door_pressed.connect(hud.ledger_door_pressed.emit)
	return sheet


## The sheets in the table's order, nulls dropped, so a HUD built without the
## chrome still reads cleanly.
static func sheets(hud: GameHud) -> Array[SheetFrame]:
	var found: Array[SheetFrame] = []
	for spec: Dictionary in SHEETS:
		var sheet: SheetFrame = sheet_for(hud, String(spec["key"]))
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
