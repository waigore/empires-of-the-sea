extends SceneTree
## Headless free-playtest drive for the ground a province shows
## (wiki: resource-terrain-region-rules § Player-facing terrain display names,
## § Forest terrain split; combat § Modifiers — the province's dominant terrain).
##
##   godot --headless --path . --script res://playtests/playtest_terrain_ground.gd
##
## The court reads one province sheet per province — its Terrain row — and the
## Combat phase reads the same ground through `ArmyModifiers`. A sheet that
## names different ground than the battle fights on is a presentation that
## overrides an outcome (REQ-P2-03), so this drive opens every province on the
## real chart, reads the row the panel prints and compares it with the ground the
## rules use. It also pins every published terrain name to the wiki's table.
##
## Every finding fails the drive (non-zero exit) instead of printing a number
## nobody compares.

const Launch = preload("res://playtests/playtest_launch.gd")
const SEED_TEXT: String = "1500"

## The published display names (wiki: resource-terrain-region-rules
## § Player-facing terrain display names). Water is outside the table.
const PUBLISHED: Dictionary = {
	MapModel.Terrain.PLAINS: "Plains",
	MapModel.Terrain.HARDWOOD_FOREST: "Hardwood Forest",
	MapModel.Terrain.SCRUB_FOREST: "Scrub Forest",
	MapModel.Terrain.HILLS: "Hills",
	MapModel.Terrain.MOUNTAINS: "Mountain",
	MapModel.Terrain.SWAMP: "Swamp",
	MapModel.Terrain.DESERT: "Desert",
}

var _steps: PackedStringArray = PackedStringArray()
var _failures: int = 0
var _screen: MapScreen = null
var _play: PlaySession = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen = await Launch.open_map(self, SEED_TEXT, 0)
	if _screen == null:
		_finish()
		return
	_play = _screen.play
	_say("seed %s — %s, %d provinces" % [
		SEED_TEXT, FactionCatalog.name_of(_play.player_faction),
		_play.model.province_count(),
	])
	_names_pass()
	_ground_pass(_play.model, "%s's chart" % FactionCatalog.region_label(_play.model.region_id))
	# A tie is the seed's own luck: the live chart carries none at this seed, so
	# the drive generates the charts that do and reads their provincials through
	# the same panel.
	for extra: int in [42, 2, 3, 11]:
		var model: MapModel = MapGenerator.new().generate_region(
			extra, FactionCatalog.OLD_WORLD, int(GameConfig.SIZES[0]["width"]),
			int(GameConfig.SIZES[0]["height"])
		)
		_ground_pass(model, "seed %d" % extra)
	_finish()


## Every terrain a court can read carries the published name.
func _names_pass() -> void:
	_say("")
	_say("--- the published names ---")
	for terrain: int in PUBLISHED.keys():
		var shown: String = String(MapModel.TERRAIN_LABELS.get(terrain, ""))
		var wanted: String = String(PUBLISHED[terrain])
		_say("%-16s reads [%s] · the table publishes [%s]" % [
			_enum_name(terrain), shown, wanted,
		])
		_expect(shown == wanted, "%s is named as published" % _enum_name(terrain))


## The province sheet's Terrain row against the ground the battle uses.
func _ground_pass(model: MapModel, label: String) -> void:
	_say("")
	_say("--- the sheet's ground against the battle's, %s ---" % label)
	var mismatch: int = 0
	for province: ProvinceState in model.provinces:
		_play.hud.panels.show_province(model, province.id)
		var sheet: String = String(_play.hud.panels.panel._grid.terrain.text)
		var ground: int = ArmyModifiers.terrain_for(model, province.id)
		var battle: String = String(MapModel.TERRAIN_LABELS.get(ground, "?"))
		if sheet == battle:
			continue
		mismatch += 1
		var counts: Dictionary = {}
		for tile: Vector2i in model.province_tiles(province.id):
			var terrain: int = model.terrain_at(tile.x, tile.y)
			counts[terrain] = int(counts.get(terrain, 0)) + 1
		_say("%s: the sheet reads [%s], the battle fights on [%s] (%s)" % [
			province.name, sheet, battle, _counts_text(counts),
		])
	_say("%d of %d provinces read differently than they fight" % [
		mismatch, model.province_count(),
	])
	_expect(mismatch == 0, "%s: every Terrain row names the ground its battle uses" % label)
	_play.hud.panels.hide_province()


## The map's own enum name, so a finding says which terrain it means.
func _enum_name(terrain: int) -> String:
	return String(MapModel.Terrain.keys()[terrain])


func _counts_text(counts: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var ids: Array = counts.keys()
	ids.sort()
	for terrain: int in ids:
		parts.append("%s %d" % [
			String(MapModel.TERRAIN_LABELS.get(terrain, "?")), int(counts[terrain]),
		])
	return ", ".join(parts)


func _expect(condition: bool, what: String) -> void:
	if condition:
		_say("  ok: %s" % what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failures += 1
	_say("  DEFECT: %s" % what)


func _say(line: String) -> void:
	_steps.append(line)
	print("playtest: ", line)


func _finish() -> void:
	print("\n--- playtest_terrain_ground: %d steps, %d defect(s) ---" % [
		_steps.size(), _failures,
	])
	quit(1 if _failures > 0 else 0)