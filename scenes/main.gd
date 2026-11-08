extends Node
## Application shell: loads the map screen demo.

const MAP_SCREEN: PackedScene = preload("res://scenes/map_screen.tscn")


func _ready() -> void:
	InputActions.ensure_actions()
	add_child(MAP_SCREEN.instantiate())
