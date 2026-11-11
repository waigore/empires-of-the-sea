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
var hospital: Label = null

## The province last shown, so a crown-link change repaints without a reload.
var _data: ProvinceState = null


func _ready() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 14)
	add_theme_constant_override("v_separation", 8)
	terrain = _add_row("Terrain")
	port = _add_row("Port")
	town = _add_row("Town")
	road = _add_row("Roads")
	fort = _add_row("Fort")
	hospital = _add_row("Hospital")


func show_province(model: MapModel, province_id: int, data: ProvinceState) -> void:
	_data = data
	terrain.text = _dominant_terrain(model, province_id)
	var port_tile: Vector2i = data.port_tile
	if port_tile.x >= 0:
		var zone: int = model.sea_zone_at(port_tile.x, port_tile.y)
		port.text = "Harbour · %s" % model.sea_zone_name(zone)
	else:
		port.text = "Landlocked"
	town.text = DossierCopy.town(data)
	town.tooltip_text = DossierCopy.town_tip(data)
	fort.text = FortRules.describe(data.fort_level)
	hospital.text = HospitalRules.describe(data.hospital_level)


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


## Repaints the live crown rows after a road completed or a town grew, without
## re-sliding the sheet the player is reading.
func refresh_crown(crown: Dictionary) -> void:
	if _data == null:
		return
	road.text = DossierCopy.crown_roads(_data, crown)
	town.text = DossierCopy.town(_data)
	town.tooltip_text = DossierCopy.town_tip(_data)


func _dominant_terrain(model: MapModel, province_id: int) -> String:
	var counts: Dictionary = {}
	for tile: Vector2i in model.province_tiles(province_id):
		var terrain_id: int = model.terrain_at(tile.x, tile.y)
		counts[terrain_id] = int(counts.get(terrain_id, 0)) + 1
	var best: int = MapModel.Terrain.PLAINS
	var best_count: int = -1
	for terrain_id: int in counts.keys():
		if int(counts[terrain_id]) > best_count:
			best_count = int(counts[terrain_id])
			best = terrain_id
	return String(MapModel.TERRAIN_LABELS.get(best, "Unknown"))


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
	return value
