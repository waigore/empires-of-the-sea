class_name HudLedgerDoors
extends RefCounted
## The crown's whole-empire sheets — the people, the muster roll, its army, the
## realm's provinces, the crown's eyes, its commanders, its towns, walls,
## hospitals and navy — as one registry (REQ-P3-01, REQ-P3-02, REQ-P5-07).
##
## Every door into them names its sheet by one key (`CIVILIANS`, `NAVY`, …), so a
## cartouche seal, a stat chip, a dossier line and a sheet's own door all press
## the same signal and no caller needs the sheet's class or field. The table is
## the single list: `build` mounts each sheet on its named layer and binds its
## doors, `all` walks them for the session bind, and the back gesture closes them
## in the order the table prints — a new sheet is one row here plus one arm of
## `_make`.
##
## The registry owns the mounted sheets. GameHud keeps read-only views of them
## for the bars, the dossiers and the suites, so no handle is a writable field on
## the HUD and no lookup reads a field back by name (REQ-P3-02).

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

## One row per sheet: the door key and the layer it rides, and therefore its
## place in the back order. The sheet's class is `_make`'s, so the table never
## names a HUD field.
const SHEETS: Array[Dictionary] = [
	{"key": CIVILIANS, "layer": "CivilianRosterLayer"},
	{"key": MUSTER, "layer": "MusterRollLayer"},
	{"key": ARMY, "layer": "ArmyLedgerLayer"},
	{"key": TOWNS, "layer": "TownLedgerLayer"},
	{"key": WALLS, "layer": "WallLedgerLayer"},
	{"key": HOSPITALS, "layer": "HospitalLedgerLayer"},
	{"key": PROVINCES, "layer": "ProvinceLedgerLayer"},
	{"key": EYES, "layer": "SpyLedgerLayer"},
	{"key": COLONIES, "layer": "ColonyLedgerLayer"},
	{"key": COMMAND, "layer": "CommandLedgerLayer"},
	{"key": NAVY, "layer": "NavalLedgerLayer"},
]

## The mounted sheets by door key: this registry owns them, not the HUD.
var _sheets: Dictionary = {}


## Mounts every whole-empire sheet on its layer and binds its own doors to the
## HUD's keyed signal, so a sheet added to the table needs no second wiring place.
func build(hud: GameHud) -> void:
	hud.ledger_door_pressed.connect(func(key: String) -> void: open(hud, key))
	for spec: Dictionary in SHEETS:
		var key: String = String(spec["key"])
		var sheet: SheetFrame = _make(key)
		if sheet == null:
			continue
		ModalShell.mount_layer(hud, String(spec["layer"])).add_child(sheet)
		sheet.door_pressed.connect(hud.ledger_door_pressed.emit)
		_sheets[key] = sheet


## The sheet a door key names, null when the key names nothing.
func sheet(key: String) -> SheetFrame:
	return _sheets.get(key) as SheetFrame


## The mounted sheets in the table's order, nulls dropped, so the back gesture
## walks the same list the doors were built from.
func all() -> Array[SheetFrame]:
	var found: Array[SheetFrame] = []
	for spec: Dictionary in SHEETS:
		var sheet: SheetFrame = sheet(String(spec["key"]))
		if sheet != null:
			found.append(sheet)
	return found


## A phone's back press closes the newest ledger a door opened. Returns true
## when a sheet took the press; false leaves the press to the map's dossiers.
func dismiss() -> bool:
	for sheet: SheetFrame in all():
		if sheet.is_open():
			sheet.close()
			return true
	return false


## The sheet one door key mints. One arm per table row: the registry names the
## class, so no caller and no HUD field has to.
static func _make(key: String) -> SheetFrame:
	match key:
		CIVILIANS:
			return CivilianRosterPanel.new()
		MUSTER:
			return ForceLedgerPanel.new()
		ARMY:
			return ArmyLedgerPanel.new()
		TOWNS:
			return TownLedgerPanel.new()
		WALLS:
			return WallLedgerPanel.new()
		HOSPITALS:
			return HospitalLedgerPanel.new()
		PROVINCES:
			return ProvinceLedgerPanel.new()
		EYES:
			return SpyLedgerPanel.new()
		COLONIES:
			return ColonyLedgerPanel.new()
		COMMAND:
			return CommandLedgerPanel.new()
		NAVY:
			return NavalLedgerPanel.new()
	return null


# --- the HUD's doors ---------------------------------------------------------


## The registry row one door key names, empty when the key names no sheet.
static func spec_for(key: String) -> Dictionary:
	for spec: Dictionary in SHEETS:
		if String(spec["key"]) == key:
			return spec
	return {}


## The sheet a door key opens, null when the key names nothing or the HUD was
## built without that sheet.
static func sheet_for(hud: GameHud, key: String) -> SheetFrame:
	if hud == null or hud.ledger_doors == null:
		return null
	return hud.ledger_doors.sheet(key)


## A door press: the HUD's one keyed door signal ends here, so a seal, a chip, a
## dossier line and a sheet's own door all take the same path.
static func open(hud: GameHud, key: String) -> void:
	var sheet: SheetFrame = sheet_for(hud, key)
	if sheet != null:
		sheet.toggle()


## Mounts every whole-empire sheet once, from the HUD's build (HudDossiers).
static func build_all(hud: GameHud) -> void:
	if hud == null or hud.ledger_doors == null:
		return
	hud.ledger_doors.build(hud)


## The sheets in the table's order, nulls dropped, so a HUD built without the
## chrome still reads cleanly.
static func sheets(hud: GameHud) -> Array[SheetFrame]:
	if hud == null or hud.ledger_doors == null:
		return []
	return hud.ledger_doors.all()


## Binds every sheet to the session the screen is playing, once the region is
## painted and the economy exists (MapPlaySetup.build_hud).
static func bind_all(hud: GameHud, play: PlaySession) -> void:
	for sheet: SheetFrame in sheets(hud):
		sheet.bind(play)


## A phone's back press closes the newest ledger a door opened. Returns true
## when a sheet took the press; false leaves the press to the map's dossiers.
static func dismiss_open(hud: GameHud) -> bool:
	if hud == null or hud.ledger_doors == null:
		return false
	return hud.ledger_doors.dismiss()
