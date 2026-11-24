extends SceneTree
## Regenerates `tests/data/census_world_160.bin` from seed 160 at Standard size.
## Run when MapGenerator or the census seed changes:
##   godot --headless --path . --script res://tests/write_census_fixture.gd

const Census = preload("res://tests/census_fixture.gd")


func _init() -> void:
	var world: WorldMap = MapGenerator.new().generate_world(
		Census.SEED, Census.WIDTH, Census.HEIGHT
	)
	var bytes: PackedByteArray = Census.pack_world(world)
	var absolute: String = ProjectSettings.globalize_path(Census.PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file: FileAccess = FileAccess.open(Census.PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % Census.PATH)
		quit(1)
		return
	file.store_buffer(bytes)
	file.close()
	print(
		"wrote %s (%d bytes, %d regions)"
		% [Census.PATH, bytes.size(), world.region_count()]
	)
	quit()
