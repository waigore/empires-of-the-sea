class_name ProvinceFactsGrid
extends GridContainer
## The province's fact table: terrain, port, town, roads and fort in one two-
## column grid. It reads the map and the estate survey — the rules decide what
## each row may say (REQ-P3-02).

var terrain: Label = null
var port: Label = null
var town: Label = null
var road: Label = null
var fort: Label = null
## What the wall soaks and what it spares the garrison — the fort table's own
## two figures, so a crown plans a siege against the wall a battle would fight
## (wiki: siege-mechanics § Wall Protection; DR-20261120-06). The row leaves the
## grid for open ground rather than printing a zero.
var wall: Label = null
## The hosts standing on the province's ground, by court and in regiments — the
## count the rules let a crown read (wiki: fog-and-exploration § Order-of-battle
## readings; DR-20261123-13). The row hides for ground nobody stands on rather
## than printing a zero. Its reading is the panel's, handed in as a callable, so
## this grid owns no session.
var hosts: Label = null
## The squadrons standing in the province's harbour, by court, in hulls and in
## the regiments they carry — the count the rules let a crown read in a charted
## port (wiki: fog-and-exploration § Order-of-battle readings; DR-20261123-14,
## DR-20261123-18). The row hides for a harbour no squadron rides rather than
## printing a zero. Its reading is the panel's, handed in as a callable, so this
## grid owns no session.
var harbour: Label = null
var hospital: Label = null
## The courts that have bought land in this province (wiki: diplomacy § GP–Minor
## Rules § Intervention; DR-20261120-05, DR-20261124-07). The row hides for a
## province nobody has bought into rather than printing an absence.
var deeds: Label = null

## The province last shown, so a crown-link change repaints without a reload.
var _data: ProvinceState = null
## value label -> its caption, so a row can hide whole.
var _captions: Dictionary = {}


func _ready() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 8)
	terrain = _add_row("Terrain")
	port = _add_row("Port")
	town = _add_row("Town")
	road = _add_row("Roads")
	fort = _add_row("Fort")
	wall = _add_row("Wall")
	hosts = _add_row("Hosts")
	harbour = _add_row("Squadrons")
	hospital = _add_row("Hospital")
	deeds = _add_row("Deeds")


## `viewer` is the crown reading the sheet and `tech` its own studies: the wall's
## storm clause reads the crown's own battery exactly and another court's as the
## published envelope, because a rival's studies are not hers to read (wiki:
## siege-mechanics § Storming an empty walled province; DR-20261123-20). A grid
## with no viewer reads no battery, so it prints the envelope.
func show_province(
	model: MapModel,
	province_id: int,
	data: ProvinceState,
	viewer: int = -1,
	tech: Dictionary = {}
) -> void:
	_data = data
	terrain.text = _terrain_row(model, province_id)
	var port_tile: Vector2i = data.port_tile
	if port_tile.x >= 0:
		var water: String = ProvinceLedger.harbour_name(model, data)
		port.text = ("Harbour · %s" % water) if not water.is_empty() else "Harbour"
	else:
		port.text = "Landlocked"
	town.text = DossierCopy.town(data)
	town.tooltip_text = DossierCopy.town_tip(data)
	fort.text = FortRules.describe(data.fort_level)
	var known: bool = data.owner == viewer
	_show_row(
		wall,
		WallRead.line(
			data.fort_level, WallRead.storm_line(data.fort_level, tech, known)
		)
	)
	wall.tooltip_text = WallRead.storm_tip(data.fort_level, known)
	# The hosts are the panel's own reading (it alone may ask the session), so a
	# fresh province clears the row until that call arrives.
	set_hosts("")
	# The harbour is the panel's own reading too, so it clears with the hosts.
	set_harbour("")
	hospital.text = HospitalRules.describe(data.hospital_level, data.hospital_staffed)
	_show_row(
		deeds, DeedBar.holders(DeedProtection.province_holders(model, province_id))
	)


## Fill the same rows from a caller's own reading instead of the province
## record: the observatory's province sheet hands over the words its reading
## module wrote, so one grid paints every province sheet (REQ-P3-01). A filled
## grid keeps no province, so a crown-link repaint has nothing to repaint.
func fill(values: Dictionary) -> void:
	_data = null
	terrain.text = String(values.get("terrain", ""))
	port.text = String(values.get("port", ""))
	town.text = String(values.get("town", ""))
	town.tooltip_text = String(values.get("town_tip", ""))
	road.text = String(values.get("roads", ""))
	road.tooltip_text = ""
	fort.text = String(values.get("fort", ""))
	_show_row(wall, String(values.get("wall", "")))
	wall.tooltip_text = String(values.get("wall_tip", ""))
	set_hosts(String(values.get("hosts", "")))
	set_harbour(String(values.get("harbour", "")))
	hospital.text = String(values.get("hospital", ""))
	_show_row(deeds, String(values.get("deeds", "")))


## `crown` is `LandConnectivity.province_link` for this province: whether its
## town reaches the capital. When omitted, the roads row falls back to the
## estate survey (DossierCopy).
func set_estate_roads(
	data: ProvinceState, rows: Array[Dictionary], crown: Dictionary
) -> void:
	if crown.has("linked"):
		road.text = DossierCopy.crown_roads(data, crown)
	else:
		road.text = DossierCopy.roads(rows)
	road.tooltip_text = DossierCopy.roads_tip(data, rows)


## The Hosts row: the courts standing on this ground, each with its regiments
## (`England 3 regiments · Aztec 1 regiment`), or `""` for ground nobody holds —
## the row leaves the grid rather than printing an absence.
func set_hosts(text: String) -> void:
	_show_row(hosts, text)


## The Squadrons row: the courts riding this harbour, each with its hulls and the
## regiments they carry (`England 3 hulls, 2 regiments aboard · Spain 1 hull`),
## or `""` for a harbour no squadron rides — the row leaves the grid rather than
## printing an absence.
func set_harbour(text: String) -> void:
	_show_row(harbour, text)


## Repaints the live crown rows after a road completed or a town grew, without
## re-sliding the sheet the player is reading.
func refresh_crown(crown: Dictionary) -> void:
	if _data == null:
		return
	road.text = DossierCopy.crown_roads(_data, crown)
	town.text = DossierCopy.town(_data)
	town.tooltip_text = DossierCopy.town_tip(_data)


## The ground this province is fought on, in the published display name, and the
## second-most common ground beside it when the province mixes terrain. The main
## reading is [ArmyModifiers.terrain_for]'s own — the same call the Combat phase
## makes — so the sheet cannot name ground the battle would not use on a tie
## (wiki: resource-terrain-region-rules § Player-facing terrain display names;
## combat § Modifiers; REQ-P2-03).
func _terrain_row(model: MapModel, province_id: int) -> String:
	return DossierCopy.terrain(model, province_id)


func _add_row(caption: String) -> Label:
	var key := Label.new()
	key.text = caption
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(key)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", Palette.TEXT)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(value)
	_captions[value] = key
	return value


## A row that has nothing to say leaves the grid rather than printing a blank:
## the caption goes with it, so the table closes up.
func _show_row(value: Label, text: String) -> void:
	if value == null:
		return
	value.text = text
	value.visible = not text.is_empty()
	var key: Label = _captions.get(value, null) as Label
	if key != null:
		key.visible = value.visible
