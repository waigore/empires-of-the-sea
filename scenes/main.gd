extends Node
## Application shell: loads the map screen demo.

const MAP_SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")

## Overridable for tests / e2e smoke (set before add_child).
var map_width: int = 128
var map_height: int = 84


func _ready() -> void:
	InputActions.ensure_actions()
	# One HUD unit == one point on handhelds; a no-op on desktop.
	PlatformDisplay.apply(get_window())
	var screen: MapScreen = MAP_SCREEN.instantiate()
	screen.map_width = map_width
	screen.map_height = map_height
	add_child(screen)
